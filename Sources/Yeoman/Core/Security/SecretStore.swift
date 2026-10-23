import Foundation
import Security
import CryptoKit

public protocol SecretStore {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(_ account: String) throws
}

public struct KeychainSecretStore: SecretStore {
    public init() {}
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "de.trst.Yeoman.security.v1", kSecAttrAccount as String: account]
    }
    public func read(_ account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return data
    }
    public func write(_ data: Data, account: String) throws {
        let q = query(account)
        let attrs = [kSecValueData as String: data]
        var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var added = q
            added[kSecValueData as String] = data
            // macOS login Keychain supports ad-hoc builds without provisioned
            // access-group entitlements. Explicitly trust only this application.
            // A changed ad-hoc code identity may require user authorization again.
            var application: SecTrustedApplication?
            var access: SecAccess?
            let trusted = SecTrustedApplicationCreateFromPath(nil, &application)
            guard trusted == errSecSuccess, let application else { throw failure(trusted) }
            let created = SecAccessCreate("Yeoman private data" as CFString, [application] as CFArray, &access)
            guard created == errSecSuccess, let access else { throw failure(created) }
            added[kSecAttrAccess as String] = access
            status = SecItemAdd(added as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    public func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private func failure(_ status: OSStatus) -> Error {
        SecurityFailure.rejected("Schlüsselbundzugriff fehlgeschlagen (\(status)).")
    }
}

/// Local, file-based secret store that manages encryption keys in a private 0700 directory
/// with 0600 file permissions. Avoids intrusive and scary macOS Keychain prompts for open
/// source ad-hoc builds while keeping stored documents AES-GCM encrypted.
public struct SecureFileSecretStore: SecretStore {
    public let directoryURL: URL
    private static let legacyAccounts: Set<String> = [
        "github-token", "clipboard-v1.enc-key", "widgets-v1.enc-key"
    ]

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directoryURL = appSupport.appendingPathComponent("Yeoman/.secrets", isDirectory: true)
        }
    }

    private func validate(_ account: String) throws {
        guard !account.isEmpty, account.utf8.count <= 128 else {
            throw SecurityFailure.rejected("Ungültige Kontobezeichnung.")
        }
    }

    private func name(_ account: String) throws -> String {
        try validate(account)
        let digest = SHA256.hash(data: Data(account.utf8))
        return "v2-" + digest.map { String(format: "%02x", $0) }.joined() + ".key"
    }

    // Compatibility with the first file-store release. Production account names are fixed
    // and collision-free; all new writes use the collision-resistant digest mapping above.
    private func legacyName(_ account: String) throws -> String {
        try validate(account)
        let safeScalars = account.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }
        let safe = String(safeScalars)
        guard !safe.isEmpty, safe != ".", safe != ".." else {
            throw SecurityFailure.rejected("Ungültige Kontobezeichnung.")
        }
        return safe + ".key"
    }

    public func read(_ account: String) throws -> Data? {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return nil }
        let dir = try SecureDirectory(directoryURL, create: false)
        let current = try name(account)
        if try dir.exists(current) { return try dir.read(current, limit: 4096) }
        guard Self.legacyAccounts.contains(account) else { return nil }
        let legacy = try legacyName(account)
        guard try dir.exists(legacy) else { return nil }
        let data = try dir.read(legacy, limit: 4096)
        try dir.write(data, name: current)
        try dir.remove(legacy)
        return data
    }

    public func write(_ data: Data, account: String) throws {
        guard data.count <= 4096 else { throw SecurityFailure.rejected("Schlüsseldaten zu groß.") }
        let dir = try SecureDirectory(directoryURL, create: true)
        try dir.write(data, name: name(account))
    }

    public func delete(_ account: String) throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let dir = try SecureDirectory(directoryURL, create: false)
        try dir.remove(name(account))
        if Self.legacyAccounts.contains(account) {
            try dir.remove(legacyName(account))
        }
    }
}

public enum SecretMigration {
    public static func validatedToken(_ raw: String) throws -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 4096,
              !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw SecurityFailure.rejected("Ungültiges GitHub-Token.")
        }
        return token
    }
    public static func token(defaults: UserDefaults, secrets: SecretStore) throws -> String {
        if let current = try secrets.read("github-token") {
            guard let raw = String(data: current, encoding: .utf8) else { throw SecurityFailure.rejected("Ungültiges Token im geschützten Speicher.") }
            let token = try validatedToken(raw)
            defaults.removeObject(forKey: "update_github_token")
            return token
        }
        guard let old = defaults.string(forKey: "update_github_token"), !old.isEmpty else { return "" }
        let token = try validatedToken(old)
        try secrets.write(Data(token.utf8), account: "github-token")
        defaults.removeObject(forKey: "update_github_token")
        return token
    }
}

public struct RecordCipher {
    private let key: SymmetricKey
    public init(key: Data) throws {
        guard key.count == 32 else { throw SecurityFailure.rejected("Ungültiger Speicherschlüssel.") }
        self.key = SymmetricKey(data: key)
    }
    public static func load(secrets: SecretStore, account: String, existingData: Bool) throws -> RecordCipher {
        if let key = try secrets.read(account) { return try RecordCipher(key: key) }
        guard !existingData else { throw SecurityFailure.rejected("Speicherschlüssel fehlt. Bestehende Daten bleiben unverändert.") }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try secrets.write(key, account: account)
        return try RecordCipher(key: key)
    }
    public func seal(_ data: Data, record: String) throws -> Data {
        let box = try AES.GCM.seal(data, using: key, authenticating: Data("Yeoman/v1/\(record)".utf8))
        guard let combined = box.combined else { throw SecurityFailure.rejected("Verschlüsselung fehlgeschlagen.") }
        return combined
    }
    public func open(_ data: Data, record: String) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key,
                         authenticating: Data("Yeoman/v1/\(record)".utf8))
    }
}
