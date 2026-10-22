import Foundation
import CryptoKit
import Darwin
import YeomanCore

func repositoryRoot() -> URL {
    let fileManager = FileManager.default
    let starts = [URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
                  URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()]
    for start in starts {
        var candidate = start.standardizedFileURL
        while candidate.path != "/" {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path),
               fileManager.fileExists(atPath: candidate.appendingPathComponent(".git").path) { return candidate }
            candidate.deleteLastPathComponent()
        }
    }
    return starts[0].resolvingSymlinksInPath().standardizedFileURL
}

do {
    let args = CommandLine.arguments
    if args.count == 2 && args[1] == "--check-trust" {
        _ = try UpdateTrust.key()
    } else if args.count == 3 && args[1] == "--generate-key" {
        let repository = repositoryRoot()
        let url = try ReleaseKeyPolicy.externalPath(args[2], repository: repository)
        let key = Curve25519.Signing.PrivateKey()
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SecurityFailure.rejected("Schlüsseldatei konnte nicht exklusiv angelegt werden.") }
        let data = Data(key.rawRepresentation.base64EncodedString().utf8)
        var succeeded = false
        defer { close(fd); if !succeeded { unlink(url.path) } }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SecurityFailure.rejected("Schlüssel konnte nicht gespeichert werden.") }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw SecurityFailure.rejected("Schlüssel konnte nicht synchronisiert werden.") }
        succeeded = true
        print("Öffentlicher Schlüssel für UpdateTrust.publicKeyBase64:")
        print(key.publicKey.rawRepresentation.base64EncodedString())
    } else {
        guard args.count == 5, ReleaseVersion(args[1]) != nil else {
            throw SecurityFailure.rejected("Aufruf: YeomanReleaseSign VERSION ZIP PRIVATE_KEY_FILE OUTPUT_JSON")
        }
        let repository = repositoryRoot()
        let privateURL = try ReleaseKeyPolicy.externalPath(args[3], repository: repository)
        try ReleaseKeyPolicy.validatePrivateFile(privateURL)
        let raw = try SecureDirectory.readExternal(privateURL, limit: 256)
        guard let keyData = Data(base64Encoded: String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SecurityFailure.rejected("Ungültige Schlüsseldatei.")
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        guard key.publicKey.rawRepresentation == (try UpdateTrust.key()).rawRepresentation else {
            throw SecurityFailure.rejected("Signierschlüssel passt nicht zum eingebauten öffentlichen Schlüssel.")
        }
        let archive = try SecureDirectory.readExternal(URL(fileURLWithPath: args[2]).resolvingSymlinksInPath(), limit: 128 * 1_048_576)
        let hash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        let metadata = SignedUpdate.Metadata(version: args[1], size: archive.count, sha256: hash)
        let payload = try JSONEncoder().encode(metadata)
        let signed = SignedUpdate(payload: payload, signature: try key.signature(for: payload))
        try JSONEncoder().encode(signed).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
}
