import Foundation
import Combine
import AppKit

public struct ClipboardSnapshot: Codable {
    public var items: [ClipboardItem] = []
    public var images: [String: Data] = [:]
    public init() {}
    public func validate() throws {
        guard items.count <= 500, Set(items.map(\.id)).count == items.count else { throw SecurityFailure.rejected("Ungültiger Clipboard-Verlauf.") }
        var bytes = 0
        for item in items {
            guard item.content.utf8.count <= SecurityPolicy.textBytes,
                  (item.sourceApp?.utf8.count ?? 0) <= 1024 else { throw SecurityFailure.rejected("Clipboard-Eintrag zu groß.") }
            bytes += item.content.utf8.count
            if item.type == .image {
                guard item.imageFileName == "\(item.id.uuidString).png", let image = images[item.id.uuidString],
                      image.count <= SecurityPolicy.imageBytes,
                      let w = item.imageWidth, let h = item.imageHeight, w > 0, h > 0,
                      w <= SecurityPolicy.imagePixels / h else { throw SecurityFailure.rejected("Ungültiger Bildverweis.") }
                bytes += image.count
            } else if item.imageFileName != nil { throw SecurityFailure.rejected("Unerwarteter Bildverweis.") }
        }
        guard images.count == items.filter({ $0.type == .image }).count,
              bytes <= 70 * 1_048_576 else { throw SecurityFailure.rejected("Clipboard-Gesamtgrenze überschritten.") }
    }
}

public final class ClipboardHistoryStore: ObservableObject {
    private struct LegacyMigration {
        let directory: SecureDirectory
        let imageNames: Set<String>
    }
    public static let shared = ClipboardHistoryStore()
    @Published public private(set) var items: [ClipboardItem] = []
    @Published public private(set) var storageError: String?
    @Published public private(set) var isPersistent = false
    @Published public var searchQuery = ""
    @Published public var maxItems = 100 {
        didSet {
            let count = min(500, max(1, maxItems))
            queue.async { self.itemLimit = count; self.mutate { _ in } }
        }
    }
    private let queue = DispatchQueue(label: "de.trst.Yeoman.clipboard.persistence", qos: .utility)
    private let imageQueue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 2; return q
    }()
    private let imageLock = NSLock()
    private var publishedImages: [String: Data] = [:]
    private var state = ClipboardSnapshot()
    private var itemLimit = 100
    private var persistent = false
    private var document: EncryptedDocument?
    private var blocked = false
    private var generation = 0
    private var commitScheduled = false
    private var committed = ClipboardSnapshot()
    private let directoryURL: URL?
    private let secrets: SecretStore
    private let defaults: UserDefaults

    public init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Yeoman"),
                secrets: SecretStore = SecureFileSecretStore(), defaults: UserDefaults = .standard) {
        self.directoryURL = directory; self.secrets = secrets; self.defaults = defaults
        queue.async { self.load() }
    }
    public var filteredItems: [ClipboardItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return query.isEmpty ? items : items.filter { $0.content.lowercased().contains(query) || ($0.sourceApp?.lowercased().contains(query) ?? false) }
    }
    public func setPersistent(_ enabled: Bool) {
        queue.async {
            do {
                guard !self.blocked else { throw SecurityFailure.rejected("Speicher gesperrt; vorhandene Daten bleiben unverändert.") }
                if enabled { try self.ensureDocument(); try self.persist(self.state) }
                else if let document = self.document {
                    try document.write(JSONEncoder().encode(ClipboardSnapshot()))
                }
                self.persistent = enabled
                self.defaults.set(enabled, forKey: "clipboard_encrypted_persistence")
                DispatchQueue.main.async { self.isPersistent = enabled }
            } catch { self.report(error) }
        }
    }
    public func addItem(content: String, type: ClipboardContentType = .text, sourceApp: String? = nil) {
        guard type != .image, content.utf8.count <= SecurityPolicy.textBytes,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        queue.async {
            self.mutate { next in
                if next.items.contains(where: { $0.content == content && $0.isPinned }) { return }
                next.items.removeAll { $0.type != .image && $0.content == content }
                next.items.insert(ClipboardItem(content: content, type: type, sourceApp: sourceApp.map { String($0.prefix(256)) }), at: 0)
            }
        }
    }
    public func addImageData(_ data: Data, sourceApp: String? = nil, isScreenshot: Bool? = nil) {
        guard data.count <= SecurityPolicy.imageBytes else { return }
        scheduleImage(sourceApp: sourceApp, isScreenshot: isScreenshot) { data }
    }
    public func addImageFile(_ url: URL, sourceApp: String? = nil, isScreenshot: Bool? = nil) {
        guard url.isFileURL,
              ["png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp", "ico"].contains(url.pathExtension.lowercased()) else { return }
        scheduleImage(sourceApp: sourceApp, isScreenshot: isScreenshot) {
            try SecureDirectory.readExternal(url, limit: SecurityPolicy.imageBytes)
        }
    }
    private func scheduleImage(sourceApp: String?, isScreenshot: Bool?, load: @escaping () throws -> Data) {
        queue.async {
            guard !self.blocked, self.imageQueue.operationCount < 2 else { return }
            let generation = self.generation
            self.imageQueue.addOperation {
                do {
                    let data = try load()
                    guard data.count <= SecurityPolicy.imageBytes else { return }
                    let image = try BoundedImage.decode(data)
                    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                          png.count <= SecurityPolicy.imageBytes else { return }
                    self.queue.async {
                        guard self.generation == generation else { return }
                        self.mutate { next in
                            let id = UUID()
                            let item = ClipboardItem(id: id, content: "Bild (\(image.width) × \(image.height))", type: .image,
                                sourceApp: sourceApp.map { String($0.prefix(256)) }, imageFileName: "\(id.uuidString).png",
                                imageWidth: image.width, imageHeight: image.height, imageByteSize: png.count, isScreenshot: isScreenshot)
                            next.items.insert(item, at: 0); next.images[id.uuidString] = png
                        }
                    }
                } catch { self.report(error) }
            }
        }
    }
    public func imageData(for item: ClipboardItem) -> Data? {
        guard item.type == .image, item.imageFileName == "\(item.id.uuidString).png" else { return nil }
        imageLock.lock(); defer { imageLock.unlock() }
        return publishedImages[item.id.uuidString]
    }
    public func togglePin(for item: ClipboardItem) {
        queue.async { self.mutate { next in if let i = next.items.firstIndex(where: { $0.id == item.id }) { next.items[i].isPinned.toggle() } } }
    }
    public func removeItem(id: UUID) { remove { $0.id == id } }
    public func clearUnpinned() { remove { !$0.isPinned } }
    public func clearAll() { remove { _ in true } }
    private func remove(_ predicate: @escaping (ClipboardItem) -> Bool) {
        queue.async {
            self.generation += 1; self.imageQueue.cancelAllOperations()
            self.mutate { next in next.items.removeAll(where: predicate) }
        }
    }
    private func mutate(_ body: (inout ClipboardSnapshot) -> Void) {
        guard !blocked else { return }
        var next = state; body(&next)
        while next.items.count > itemLimit {
            guard let i = next.items.lastIndex(where: { !$0.isPinned }) else { report(SecurityFailure.rejected("Clipboard-Limit erreicht.")); return }
            next.items.remove(at: i)
        }
        let ids = Set(next.items.filter { $0.type == .image }.map { $0.id.uuidString })
        next.images = next.images.filter { ids.contains($0.key) }
        do {
            try next.validate()
            state = next
            if !commitScheduled {
                commitScheduled = true
                queue.asyncAfter(deadline: .now() + 0.05) { self.commitPending() }
            }
        } catch { report(error) }
    }
    private func commitPending() {
        guard commitScheduled else { return }
        commitScheduled = false
        do {
            if persistent { try persist(state) }
            committed = state; publish()
        } catch { state = committed; report(error) }
    }
    private func persist(_ snapshot: ClipboardSnapshot) throws {
        try ensureDocument()
        guard let document else { throw SecurityFailure.rejected("Persistenz nicht verfügbar.") }
        try document.write(JSONEncoder().encode(snapshot))
    }
    private func ensureDocument() throws {
        guard document == nil else { return }
        guard let directoryURL else { throw SecurityFailure.rejected("Flüchtiger Test-Speicher.") }
        let directory = try SecureDirectory(directoryURL)
        document = try EncryptedDocument(directory: directory, name: "clipboard-v1.enc", secrets: secrets, limit: SecurityPolicy.historyBytes)
    }
    private func load() {
        guard let directoryURL else { return }
        do {
            let directory = try SecureDirectory(directoryURL)
            let existing = try directory.exists("clipboard-v1.enc")
            let legacy = try directory.exists("clipboard_history.json")
            let oldURL = directoryURL.deletingLastPathComponent().appendingPathComponent("MacCustomizer")
            let oldExists = FileManager.default.fileExists(atPath: oldURL.path)
            let userPref = defaults.object(forKey: "clipboard_encrypted_persistence") as? Bool
            let migrationDone = defaults.bool(forKey: "clipboard_legacy_migration_done")

            // User preference ALWAYS takes precedence over directory presence (AUD-02)
            if let userPref {
                persistent = userPref
            } else if !migrationDone && (legacy || oldExists) {
                persistent = true
            } else {
                persistent = false
            }

            if existing || persistent {
                try ensureDocument()
                if let data = try document?.read() {
                    state = try JSONDecoder().decode(ClipboardSnapshot.self, from: data)
                    try state.validate()
                }

                // If legacy files exist, always migrate/merge them instead of deleting without import (AUD-03)
                var migratedSources = [LegacyMigration]()
                if legacy {
                    if let migration = try migrate(directory) {
                        migratedSources.append(migration)
                    }
                }
                if oldExists {
                    let oldDir = try SecureDirectory(oldURL, create: false)
                    if let migration = try migrate(oldDir) {
                        migratedSources.append(migration)
                    }
                }

                if !migratedSources.isEmpty || !existing {
                    if persistent {
                        try persist(state)
                    }
                }

                // Clean only migrated sources after successful encrypted commit
                if persistent && (existing || !migratedSources.isEmpty || migrationDone) {
                    for migration in migratedSources {
                        try cleanLegacy(migration)
                    }
                    defaults.set(true, forKey: "clipboard_legacy_migration_done")
                }
            }
            defaults.set(persistent, forKey: "clipboard_encrypted_persistence")
            committed = state; publish()
        } catch { blocked = true; report(error) }
    }
    private func migrate(_ directory: SecureDirectory) throws -> LegacyMigration? {
        guard try directory.exists("clipboard_history.json") else { return nil }
        let data = try directory.read("clipboard_history.json", limit: SecurityPolicy.historyBytes)
        let old = try JSONDecoder().decode([ClipboardItem].self, from: data)
        guard old.count <= 500 else { throw SecurityFailure.rejected("Alter Verlauf zu groß.") }
        var next = state
        for item in old {
            if let existing = next.items.first(where: { $0.id == item.id }) {
                guard existing == item else { throw SecurityFailure.rejected("Widersprüchliche Legacy-Einträge; Quelldaten bleiben erhalten.") }
            } else {
                next.items.append(item)
            }
        }
        var importedImageNames = Set<String>()
        if old.contains(where: { $0.type == .image }) {
            if try directory.exists("clipboard_images") {
                let images = try directory.child("clipboard_images", create: false)
                for item in old where item.type == .image {
                    guard item.imageFileName == "\(item.id.uuidString).png" else { throw SecurityFailure.rejected("Unsicherer Legacy-Bildpfad.") }
                    let imageName = item.imageFileName!
                    if try images.exists(imageName) {
                        let bytes = try images.read(imageName, limit: SecurityPolicy.imageBytes)
                        _ = try BoundedImage.decode(bytes)
                        if let existing = next.images[item.id.uuidString] {
                            guard existing == bytes else {
                                throw SecurityFailure.rejected("Widersprüchliche Legacy-Bilddaten; Quelldaten bleiben erhalten.")
                            }
                        } else {
                            next.images[item.id.uuidString] = bytes
                        }
                        importedImageNames.insert(imageName)
                        for size in [120, 200, 300] {
                            let thumbnail = imageName + "_thumb_\(size).jpg"
                            if try images.exists(thumbnail) { importedImageNames.insert(thumbnail) }
                        }
                    }
                }
            }
        }
        try next.validate()
        state = next
        return LegacyMigration(directory: directory, imageNames: importedImageNames)
    }
    private func cleanLegacy(_ migration: LegacyMigration) throws {
        let directory = migration.directory
        if try directory.exists("clipboard_images") {
            let images = try directory.child("clipboard_images", create: false)
            // Delete only files proven to belong to records committed to the encrypted
            // snapshot. UUID-shaped but unreferenced files may belong to another writer.
            for name in migration.imageNames {
                try images.remove(name)
            }
            if (try? FileManager.default.contentsOfDirectory(atPath: images.url.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: images.url)
            }
        }
        try directory.remove("clipboard_history.json")
        if (try? FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty) == true &&
           directory.url.lastPathComponent == "MacCustomizer" {
            try? FileManager.default.removeItem(at: directory.url)
        }
    }
    private func publish() {
        let snapshot = state, persistent = persistent
        DispatchQueue.main.async {
            self.imageLock.lock(); self.publishedImages = snapshot.images; self.imageLock.unlock()
            ClipboardImageCache.shared.clear()
            self.items = snapshot.items; self.isPersistent = persistent
        }
    }
    private func report(_ error: Error) { DispatchQueue.main.async { self.storageError = error.localizedDescription } }
    /// Deterministic test barrier; never needed by the UI.
    public func flushForTesting() {
        queue.sync {}
        imageQueue.waitUntilAllOperationsAreFinished()
        queue.sync { commitPending() }
    }
}
