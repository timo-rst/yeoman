import Foundation
import CryptoKit
import Security
import Darwin

/// Public trust anchor only. Configure before distributing updates. No private keys.
/// Developer ID/notarization deliberately not required (user decision).
public enum UpdateTrust {
    public static var publicKeyBase64 = "GWiEpIZVe2QPQ1OLJam1y6c7xFQb+LlI/FvqXuavDSM="
    public static func parseKey(from base64: String) throws -> Curve25519.Signing.PublicKey {
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            throw SecurityFailure.rejected("Updateinstallation gesperrt: öffentlicher Updateschlüssel noch nicht konfiguriert.")
        }
        return try Curve25519.Signing.PublicKey(rawRepresentation: data)
    }
    public static func key() throws -> Curve25519.Signing.PublicKey {
        try parseKey(from: publicKeyBase64)
    }
}

public enum ReleaseKeyPolicy {
    public static func externalPath(_ raw: String, repository: URL) throws -> URL {
        let repository = repository.resolvingSymlinksInPath().standardizedFileURL
        let requested = URL(fileURLWithPath: raw).standardizedFileURL
        let parent = requested.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let resolved = parent.appendingPathComponent(requested.lastPathComponent, isDirectory: false).standardizedFileURL
        guard resolved.path != repository.path,
              !resolved.path.hasPrefix(repository.path + "/") else {
            throw SecurityFailure.rejected("Privater Schlüssel darf nicht im Repository liegen.")
        }
        return resolved
    }
    public static func validatePrivateFile(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1,
              (info.st_mode & 0o077) == 0 else {
            throw SecurityFailure.rejected("Private Schlüsseldatei muss dem aktuellen Benutzer gehören und 0600 oder restriktiver sein.")
        }
    }
}

public struct ReleaseVersion: Comparable {
    public let parts: [Int]
    public init?(_ raw: String) {
        let text = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              parts.allSatisfy({ $0.count <= 8 && ($0.count == 1 || $0.first != "0") }) else { return nil }
        self.parts = parts.map { Int($0)! } + Array(repeating: 0, count: 3 - parts.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

public enum UpdateURLPolicy {
    public static let repositoryPath = "/timo-rst/mac_customizer"
    public static let api = URL(string: "https://api.github.com/repos/timo-rst/mac_customizer/releases/latest")!
    // GitHub's runner network reference lists this exact host for release assets.
    public static let cdnHosts: Set<String> = ["release-assets.githubusercontent.com"]
    public static func transport(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https",
              c.user == nil, c.password == nil, c.fragment == nil,
              c.port == nil || c.port == 443 else { return false }
        return c.host != nil
    }
    public static func asset(_ url: URL) -> Bool {
        guard transport(url), url.host == "github.com", url.query == nil,
              url.path.hasPrefix(repositoryPath + "/releases/download/") else { return false }
        let suffix = String(url.path.dropFirst((repositoryPath + "/releases/download/").count))
        let components = suffix.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 2 && ReleaseVersion(String(components[0])) != nil &&
            ["Yeoman.zip", "Yeoman.update.json"].contains(String(components[1]))
    }
    public static func releasePage(_ url: URL) -> Bool {
        guard transport(url), url.host == "github.com", url.query == nil else { return false }
        if url.path == repositoryPath + "/releases" { return true }
        let prefix = repositoryPath + "/releases/tag/"
        return url.path.hasPrefix(prefix) && ReleaseVersion(String(url.path.dropFirst(prefix.count))) != nil
    }
    public static func redirect(_ url: URL, apiRequest: Bool, count: Int) -> Bool {
        guard count <= 4, transport(url) else { return false }
        return apiRequest ? url == api : (asset(url) || cdnHosts.contains(url.host ?? ""))
    }
}

public struct SignedUpdate: Codable {
    public let payload: Data
    public let signature: Data
    public struct Metadata: Codable {
        public let product: String
        public let version: String
        public let archive: String
        public let size: Int
        public let sha256: String
        public init(product: String = "de.trst.Yeoman", version: String, archive: String = "Yeoman.zip", size: Int, sha256: String) {
            self.product = product; self.version = version; self.archive = archive; self.size = size; self.sha256 = sha256
        }
    }
    public init(payload: Data, signature: Data) { self.payload = payload; self.signature = signature }
    public func verified(key: Curve25519.Signing.PublicKey, current: String) throws -> Metadata {
        guard payload.count <= 16384, key.isValidSignature(signature, for: payload) else {
            throw SecurityFailure.rejected("Ungültige Updatesignatur.")
        }
        let metadata = try JSONDecoder().decode(Metadata.self, from: payload)
        guard metadata.product == "de.trst.Yeoman", metadata.archive == "Yeoman.zip",
              metadata.size > 0, metadata.size <= 128 * 1_048_576,
              metadata.sha256.count == 64, metadata.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let new = ReleaseVersion(metadata.version), let old = ReleaseVersion(current), new > old else {
            throw SecurityFailure.rejected("Ungültige Update-Metadaten oder Downgrade.")
        }
        return metadata
    }
    public static func verifyArchive(_ data: Data, metadata: Metadata) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == metadata.size, digest == metadata.sha256 else { throw SecurityFailure.rejected("Updatearchiv wurde verändert.") }
    }
}

public struct BundleIdentity: Equatable {
    public let bundleID: String
    public let version: String
    public let executableHash: String
    public let cdhash: Data?

    public init(bundleID: String, version: String, executableHash: String, cdhash: Data?) {
        self.bundleID = bundleID
        self.version = version
        self.executableHash = executableHash
        self.cdhash = cdhash
    }
}

public enum BundleVerifier {
    public static func readPlist(_ url: URL) throws -> [String: Any] {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        let values = try plistURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink == false, values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= 512 * 1024 else {
            throw SecurityFailure.rejected("Ungültige oder fehlende Info.plist im Bundle.")
        }
        let data = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw SecurityFailure.rejected("Info.plist konnte nicht gelesen werden.")
        }
        return plist
    }

    public static func readVersion(_ url: URL) throws -> String {
        let plist = try readPlist(url)
        guard let version = plist["CFBundleShortVersionString"] as? String,
              ReleaseVersion(version) != nil else {
            throw SecurityFailure.rejected("Installierte Version nicht lesbar.")
        }
        return version
    }

    @discardableResult
    public static func verify(_ url: URL, version: String) throws -> BundleIdentity {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink == false, values.isDirectory == true else {
            throw SecurityFailure.rejected("Ungültiges Bundle-Verzeichnis.")
        }
        // Read fresh Info.plist directly from disk to bypass stale Bundle(url:) cache (AUD-01)
        let plist = try readPlist(url)
        guard let bundleID = plist["CFBundleIdentifier"] as? String, bundleID == "de.trst.Yeoman",
              let bundleVersion = plist["CFBundleShortVersionString"] as? String, bundleVersion == version else {
            throw SecurityFailure.rejected("Falsches Update-Bundle oder falsche Version.")
        }
        let execName = (plist["CFBundleExecutable"] as? String) ?? "Yeoman"
        let execURL = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(execName)
        let execValues = try execURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard execValues.isSymbolicLink == false, execValues.isRegularFile == true else {
            throw SecurityFailure.rejected("Hauptprogramm im Bundle fehlt oder ist verlinkt.")
        }
        let execData = try Data(contentsOf: execURL)
        let execHash = SHA256.hash(data: execData).map { String(format: "%02x", $0) }.joined()

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate), nil) == errSecSuccess else {
            throw SecurityFailure.rejected("Integritätsprüfung der App-Signatur fehlgeschlagen.")
        }

        var signingInfo: CFDictionary?
        var cdhash: Data?
        if SecCodeCopySigningInformation(code, SecCSFlags(), &signingInfo) == errSecSuccess,
           let dict = signingInfo as? [String: Any] {
            cdhash = dict[kSecCodeInfoUnique as String] as? Data
        }

        return BundleIdentity(bundleID: bundleID, version: bundleVersion, executableHash: execHash, cdhash: cdhash)
    }
}
