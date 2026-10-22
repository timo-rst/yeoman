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
            guard let raw = String(data: current, encoding: .utf8) else { throw SecurityFailure.rejected("Ungültiges Token im Schlüsselbund.") }
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
