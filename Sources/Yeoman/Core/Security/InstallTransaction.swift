import Foundation
import Darwin

public enum InstallTransaction {
    public static func recover(target: URL, backup: URL, verify: (URL) throws -> Void) throws {
        guard !FileManager.default.fileExists(atPath: target.path),
              FileManager.default.fileExists(atPath: backup.path) else {
            throw SecurityFailure.rejected("Wiederherstellung überschreibt keine vorhandene Anwendung.")
        }
        try verify(backup)
        try FileManager.default.moveItem(at: backup, to: target)
    }
    /// Caller serializes installations. Both staged and backup live on target volume.
    public static func replace<V: Equatable>(staged: URL, target: URL, backup: URL,
                                            verify: (URL) throws -> V,
                                            move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        let stagedIdentity = try verify(staged)
        guard !FileManager.default.fileExists(atPath: backup.path) else { throw SecurityFailure.rejected("Wiederherstellung erforderlich; Sicherung bleibt erhalten.") }
        try move(target, backup)
        do {
            try move(staged, target)
            let targetIdentity = try verify(target)
            guard targetIdentity == stagedIdentity else {
                throw SecurityFailure.rejected("Installierte Bundle-Identität stimmt nicht mit dem geprüften Staging-Bundle überein.")
            }
        } catch {
            // Move failed/new target aside before restoring the original; never delete the backup.
            if FileManager.default.fileExists(atPath: target.path) {
                if FileManager.default.fileExists(atPath: staged.path) {
                    try? FileManager.default.removeItem(at: staged)
                }
                try? move(target, staged)
                if FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.removeItem(at: target)
                }
            }
            if FileManager.default.fileExists(atPath: backup.path) {
                try move(backup, target)
            }
            throw error
        }
    }

    public static func replace(staged: URL, target: URL, backup: URL,
                               verify: (URL) throws -> Void,
                               move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        try replace(staged: staged, target: target, backup: backup, verify: { url -> Bool in
            try verify(url)
            return true
        }, move: move)
    }
}

public enum UpdateInstaller {
    private static func withRecoveryLock<T>(_ recovery: SecureDirectory, create: Bool, _ body: () throws -> T) throws -> T {
        let flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC | (create ? O_CREAT : 0)
        let lockFD = openat(recovery.descriptor, "lock", flags, 0o600)
        guard lockFD >= 0 else { throw SecurityFailure.rejected("Update-Sperre nicht verfügbar.") }
        defer { close(lockFD) }
        try SecureDirectory.validate(lockFD, directory: false)
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw SecurityFailure.rejected("Ein Update läuft bereits.") }
        return try body()
    }
    public static func install(staging: URL, target: URL, oldProcess: ProcessIdentity, wait: TimeInterval = 30,
                               ready: () throws -> Void = {}) throws {
        let key = try UpdateTrust.key()
        guard target.pathExtension == "app", target.lastPathComponent == "Yeoman.app",
              oldProcess.uid == geteuid(), oldProcess.pid > 1 else { throw SecurityFailure.rejected("Ungültiges Installationsziel.") }
        let download = try SecureDirectory(staging, create: false)
        let envelope = try JSONDecoder().decode(SignedUpdate.self, from: download.read("update.json", limit: 32768))
        let current = try BundleVerifier.readVersion(target)
        try BundleVerifier.verify(target, version: current)
        let metadata = try envelope.verified(key: key, current: current)
        let archive = try download.read("update.zip", limit: 128 * 1_048_576)
        try SignedUpdate.verifyArchive(archive, metadata: metadata)

        let recoveryURL = target.deletingLastPathComponent().appendingPathComponent(".Yeoman.recovery")
        let recovery = try SecureDirectory(recoveryURL)
        try withRecoveryLock(recovery, create: true) {
            let backup = recoveryURL.appendingPathComponent("previous.app")
            // Existing backups are preserved for explicit recovery; never overwrite them.
            guard !(try recovery.exists("previous.app")) else { throw SecurityFailure.rejected("Vorherige Updatesicherung vorhanden. Wiederherstellung prüfen.") }
            let workName = "stage-" + UUID().uuidString
            let work = try recovery.child(workName)
            defer { try? FileManager.default.removeItem(at: work.url) }
            try work.write(archive, name: "archive.zip")
            let extract = try work.child("extracted")
            try SafeArchive.extract(archiveURL: work.url.appendingPathComponent("archive.zip"), to: extract)
            let newApp = extract.url.appendingPathComponent("Yeoman.app")
            try BundleVerifier.verify(newApp, version: metadata.version)
            // Tell the still-running app only after signature, archive and bundle checks succeeded.
            try ready()
            let start = ProcessInfo.processInfo.systemUptime
            while ProcessIdentity.read(oldProcess.pid) == oldProcess {
                guard ProcessInfo.processInfo.systemUptime - start < wait else { throw SecurityFailure.rejected("Yeoman wurde nicht rechtzeitig beendet.") }
                Thread.sleep(forTimeInterval: 0.1)
            }
            // Journal before the first rename; after a crash the new app can acknowledge
            // the commit, or the helper in previous.app can restore a missing target.
            try recovery.write(Data(metadata.version.utf8), name: "installed-version")
            try InstallTransaction.replace(staged: newApp, target: target, backup: backup) {
                try BundleVerifier.verify($0, version: metadata.version)
            }
        }
        // Backup remains until a later successful app launch acknowledges the transaction.
    }
    public static func recover(target: URL) throws {
        guard target.lastPathComponent == "Yeoman.app" else { throw SecurityFailure.rejected("Ungültiges Wiederherstellungsziel.") }
        let recovery = try SecureDirectory(target.deletingLastPathComponent().appendingPathComponent(".Yeoman.recovery"), create: false)
        try withRecoveryLock(recovery, create: false) {
            try InstallTransaction.recover(target: target, backup: recovery.url.appendingPathComponent("previous.app")) { app in
                let version = try BundleVerifier.readVersion(app)
                try BundleVerifier.verify(app, version: version)
            }
            try recovery.remove("installed-version")
        }
    }
    public static func acknowledgeLaunch(target: URL) throws {
        guard target.lastPathComponent == "Yeoman.app" else { throw SecurityFailure.rejected("Ungültiges Installationsziel.") }
        let recoveryURL = target.deletingLastPathComponent().appendingPathComponent(".Yeoman.recovery")
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { return }
        let recovery = try SecureDirectory(recoveryURL, create: false)
        try withRecoveryLock(recovery, create: false) {
            guard try recovery.exists("installed-version") else { return }
            let version = String(decoding: try recovery.read("installed-version", limit: 64), as: UTF8.self)
            try BundleVerifier.verify(target, version: version)
            if try recovery.exists("previous.app") {
                _ = try recovery.child("previous.app", create: false)
                try FileManager.default.removeItem(at: recoveryURL.appendingPathComponent("previous.app"))
            }
            try recovery.remove("installed-version")
        }
    }
}
