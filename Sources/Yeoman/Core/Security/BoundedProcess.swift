import Foundation
import Darwin

public struct ProcessOutput {
    public let data: Data
    public let status: Int32
}

public enum BoundedProcess {
    /// Only waits for children created here. Both pipes are drained concurrently.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 5,
                           limit: Int = 4 * 1_048_576, currentDirectory: URL? = nil) throws -> ProcessOutput {
        let child = Process(), out = Pipe(), err = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.currentDirectoryURL = currentDirectory
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        child.standardOutput = out; child.standardError = err
        let lock = NSLock(), done = DispatchSemaphore(value: 0), readers = DispatchGroup()
        var output = Data(), exceeded = false, total = 0
        child.terminationHandler = { _ in done.signal() }
        try child.run()
        for (pipe, capture) in [(out, true), (err, false)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    lock.lock()
                    if data.count > limit - total { exceeded = true }
                    else { total += data.count; if capture { output.append(data) } }
                    let stop = exceeded
                    lock.unlock()
                    if stop && child.isRunning { child.terminate() }
                }
            }
        }
        let timedOut = done.wait(timeout: .now() + timeout) == .timedOut
        if timedOut && child.isRunning {
            child.terminate()
            if done.wait(timeout: .now() + 0.25) == .timedOut && child.isRunning {
                Darwin.kill(child.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 2)
            }
        }
        // Supplied executables must not daemonize or leave descendants holding pipes.
        guard readers.wait(timeout: .now() + 2) == .success else {
            throw SecurityFailure.rejected("Subprozess-Ausgabe nicht geschlossen.")
        }
        guard !timedOut, !exceeded else { throw SecurityFailure.rejected("Subprozess hat Zeit- oder Ausgabegrenze überschritten.") }
        return ProcessOutput(data: output, status: child.terminationStatus)
    }
}

public struct ProcessIdentity: Codable, Equatable {
    public let pid: Int32
    public let uid: UInt32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64
    public let name: String
    public init(pid: Int32, uid: UInt32, startSeconds: UInt64, startMicroseconds: UInt64, name: String) {
        self.pid = pid; self.uid = uid; self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds; self.name = name
    }
    public static func read(_ pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info) else { return nil }
        let name = withUnsafeBytes(of: info.pbi_name) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ProcessIdentity(pid: pid, uid: info.pbi_uid, startSeconds: info.pbi_start_tvsec,
                               startMicroseconds: info.pbi_start_tvusec, name: name)
    }
}

public struct ProcessSample: Equatable {
    public let pid: Int32
    public let cpuPercent: Double
    public let residentKB: Double
    public let command: String
    public init(pid: Int32, cpuPercent: Double, residentKB: Double, command: String) {
        self.pid = pid; self.cpuPercent = cpuPercent; self.residentKB = residentKB; self.command = command
    }
}

public enum ProcessSnapshotParser {
    public static func parse(_ line: String) -> ProcessSample? {
        let parts = line.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4, let rawPID = Int(parts[0]), let pid = pid_t(exactly: rawPID), pid > 0,
              let cpu = Double(parts[1]), cpu.isFinite, cpu >= 0,
              let resident = Double(parts[2]), resident.isFinite, resident >= 0 else { return nil }
        return ProcessSample(pid: pid, cpuPercent: cpu, residentKB: resident,
                             command: String(parts[3].prefix(1024)))
    }
}

public enum TerminationPolicy {
    public static let protectedNames: Set<String> = ["kernel_task", "launchd", "WindowServer", "loginwindow",
        "systemstats", "diskarbitrationd", "coreauthd", "securityd", "opendirectoryd", "syslogd",
        "notifyd", "configd", "powerd", "Yeoman", "MacCustomizer"]
    public static func terminate(expected: ProcessIdentity, ownPID: Int32 = getpid(), uid: UInt32 = geteuid(),
                                 lookup: (Int32) -> ProcessIdentity? = ProcessIdentity.read,
                                 signal: (Int32) -> Bool = { Darwin.kill($0, SIGKILL) == 0 }) -> Bool {
        guard expected.pid > 1, expected.pid != ownPID, expected.uid == uid,
              !protectedNames.contains(expected.name), lookup(expected.pid) == expected else { return false }
        // Darwin kill has no compare-and-signal primitive: a residual PID race remains.
        return signal(expected.pid)
    }
}
