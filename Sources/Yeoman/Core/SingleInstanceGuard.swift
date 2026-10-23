import Foundation
import AppKit
import Darwin

/// Enforces single-instance execution for Yeoman.
/// If another instance of Yeoman is already running, this guard activates the running
/// instance, instructs it to display its main settings window, and terminates the
/// duplicate process before duplicate modules or menu bar items are initialized.
public final class SingleInstanceGuard {
    private static var lockFileDescriptor: Int32 = -1
    public static let reopenNotificationName = Notification.Name("de.trst.Yeoman.reopen")
    
    /// Checks if another instance of Yeoman is already running.
    /// If so, notifies the running instance to open its main window, activates it, and returns false.
    /// If this is the only instance, acquires an exclusive kernel file lock and returns true.
    public static func acquireOrActivateExisting(bundleIdentifier: String? = nil, lockDirectory: URL? = nil) -> Bool {
        let bundleID = bundleIdentifier ?? Bundle.main.bundleIdentifier ?? "de.trst.Yeoman"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        // 1. Check if another instance is registered with LaunchServices / WindowServer
        let existingApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }
        
        // Determine lockfile path
        let appSupportDir: URL
        if let customDir = lockDirectory {
            appSupportDir = customDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            appSupportDir = appSupport.appendingPathComponent("Yeoman", isDirectory: true)
        }
        
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lockFileURL = appSupportDir.appendingPathComponent(".instance.lock", isDirectory: false)
        
        let fd = open(lockFileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        if fd >= 0 {
            if flock(fd, LOCK_EX | LOCK_NB) != 0 {
                // Lock held by another process!
                close(fd)
                notifyAndActivateExisting(existingApps: existingApps, lockFileURL: lockFileURL)
                return false
            }
            
            // If another instance was found in NSRunningApplication
            if let existing = existingApps.first {
                if !existing.isTerminated {
                    flock(fd, LOCK_UN)
                    close(fd)
                    notifyAndActivateExisting(existingApps: existingApps, lockFileURL: lockFileURL)
                    return false
                }
            }
            
            // Hold lock for the lifetime of this process
            self.lockFileDescriptor = fd
            ftruncate(fd, 0)
            let pidStr = "\(currentPID)\n"
            _ = pidStr.withCString { Darwin.write(fd, $0, strlen($0)) }
            return true
        }
        
        // Fallback if file opening failed: check running applications
        if !existingApps.isEmpty {
            notifyAndActivateExisting(existingApps: existingApps, lockFileURL: nil)
            return false
        }
        
        return true
    }
    
    private static func notifyAndActivateExisting(existingApps: [NSRunningApplication], lockFileURL: URL?) {
        // 1. Post distributed notification to instruct the existing instance to open its window
        DistributedNotificationCenter.default().postNotificationName(
            reopenNotificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        
        // 2. Activate via NSRunningApplication
        if let existing = existingApps.first, !existing.isTerminated {
            if #available(macOS 14.0, *) {
                existing.activate()
            } else {
                existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            return
        }
        
        // 3. Fallback: Try reading PID from lockfile
        if let lockFileURL = lockFileURL {
            if let rawData = try? Data(contentsOf: lockFileURL),
               let pidString = String(data: rawData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let pid = pid_t(pidString),
               let app = NSRunningApplication(processIdentifier: pid),
               !app.isTerminated {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                }
            }
        }
    }
    
    /// Releases the instance lock (used during testing).
    public static func releaseLockForTesting() {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }
}
