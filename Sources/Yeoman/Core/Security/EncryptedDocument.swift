import Foundation

/// Call on a serial queue. Failed reads disable writes until the caller explicitly recovers.
public final class EncryptedDocument {
    private let directory: SecureDirectory
    private let name: String
    private let cipher: RecordCipher
    private let limit: Int
    private var blocked = false
    public init(directory: SecureDirectory, name: String, secrets: SecretStore, limit: Int) throws {
        self.directory = directory; self.name = name; self.limit = limit
        cipher = try RecordCipher.load(secrets: secrets, account: name + "-key", existingData: directory.exists(name))
    }
    public func read() throws -> Data? {
        do {
            guard try directory.exists(name) else { return nil }
            return try cipher.open(directory.read(name, limit: limit + 28), record: name)
        } catch { blocked = true; throw error }
    }
    public func write(_ plaintext: Data) throws {
        guard !blocked, plaintext.count <= limit else { throw SecurityFailure.rejected("Speicher gesperrt oder Größenlimit überschritten.") }
        try directory.write(cipher.seal(plaintext, record: name), name: name)
    }
}
