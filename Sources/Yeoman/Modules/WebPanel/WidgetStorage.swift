import Foundation

public final class WidgetStorage {
    private let queue = DispatchQueue(label: "de.trst.Yeoman.widgets.storage", qos: .utility)
    private let url: URL
    private let defaults: UserDefaults
    private let secrets: SecretStore
    private var document: EncryptedDocument?
    private var failed = false
    public init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Yeoman"),
                defaults: UserDefaults = .standard, secrets: SecretStore = SecureFileSecretStore()) {
        self.url = url; self.defaults = defaults; self.secrets = secrets
    }
    private static func decodeAndRepair(_ data: Data) throws -> (items: [WebWidgetItem], repaired: Bool) {
        guard data.count <= 1_048_576 else { throw SecurityFailure.rejected("Widget-Konfiguration zu groß.") }
        var items = try JSONDecoder().decode([WebWidgetItem].self, from: data)
        guard items.count <= SecurityPolicy.widgetCount else {
            throw SecurityFailure.rejected("Zu viele Widgets.")
        }
        var repaired = false
        // Repair invalid/all-zero UUIDs to avoid WebKit crash (AUD-05)
        for i in items.indices {
            if !items[i].id.isValidWebKitIdentifier {
                items[i].id = UUID()
                repaired = true
            }
        }
        guard Set(items.map(\.id)).count == items.count else {
            throw SecurityFailure.rejected("Doppelte Kennungen.")
        }
        return (items, repaired)
    }
    public static func decode(_ data: Data) throws -> [WebWidgetItem] {
        try decodeAndRepair(data).items
    }
    public func load(completion: @escaping (Result<[WebWidgetItem], Error>) -> Void) {
        queue.async {
            let result: Result<[WebWidgetItem], Error>
            do {
                let root = try SecureDirectory(self.url)
                let document = try EncryptedDocument(directory: root, name: "widgets-v1.enc", secrets: self.secrets, limit: 1_048_576)
                self.document = document
                let encrypted = try document.read()
                let legacy = self.defaults.data(forKey: "web_panel_widgets_list_json")
                let decoded = try Self.decodeAndRepair(encrypted ?? legacy ?? Data("[]".utf8))
                // Persist migrations and repaired identifiers before exposing them. Otherwise
                // a repaired ID would select a different persistent WebKit profile each launch.
                if encrypted == nil || decoded.repaired {
                    try document.write(JSONEncoder().encode(decoded.items))
                }
                self.defaults.removeObject(forKey: "web_panel_widgets_list_json")
                result = .success(decoded.items)
            } catch { self.failed = true; result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    public func save(_ items: [WebWidgetItem], completion: @escaping (Error?) -> Void) {
        queue.async {
            var failure: Error?
            do {
                guard !self.failed, let document = self.document else { throw SecurityFailure.rejected("Widget-Speicher gesperrt.") }
                let data = try JSONEncoder().encode(items); _ = try Self.decode(data)
                try document.write(data)
            } catch { failure = error }
            DispatchQueue.main.async { completion(failure) }
        }
    }
}
