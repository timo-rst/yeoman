import Foundation
import YeomanCore

do {
    let args = CommandLine.arguments
    if args.count == 3 && args[1] == "--recover" {
        try UpdateInstaller.recover(target: URL(fileURLWithPath: args[2]))
        exit(0)
    }
    guard args.count == 4 else { throw SecurityFailure.rejected("Ungültige Installer-Argumente.") }
    let staging = URL(fileURLWithPath: args[1]), target = URL(fileURLWithPath: args[2])
    guard let identityData = Data(base64Encoded: args[3]) else { throw SecurityFailure.rejected("Prozessidentität fehlt.") }
    let identity = try JSONDecoder().decode(ProcessIdentity.self, from: identityData)
    defer { try? FileManager.default.removeItem(at: staging) }
    try UpdateInstaller.install(staging: staging, target: target, oldProcess: identity) {
        let directory = try SecureDirectory(staging, create: false)
        try directory.write(Data(), name: "helper-ready")
    }
    let opened = try BoundedProcess.run("/usr/bin/open", ["-n", target.path], timeout: 10, limit: 65_536)
    guard opened.status == 0 else { throw SecurityFailure.rejected("Die aktualisierte Anwendung konnte nicht gestartet werden.") }
} catch {
    // No secrets or downloaded strings in output. The recovery directory preserves the old app.
    FileHandle.standardError.write(Data("Updateinstallation fehlgeschlagen. Vorhandene Sicherung bleibt erhalten.\n".utf8))
    exit(1)
}
