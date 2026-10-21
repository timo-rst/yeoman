import Foundation
import Combine

public final class ClipboardHistoryStore: ObservableObject {
    public static let shared = ClipboardHistoryStore()
    
    @Published public var items: [ClipboardItem] = []
    @Published public var searchQuery: String = ""
    @Published public var maxItems: Int = 100
    
    private let storageURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("MacCustomizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageURL = directory.appendingPathComponent("clipboard_history.json")
        load()
    }
    
    public var filteredItems: [ClipboardItem] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return items
        }
        let query = searchQuery.lowercased()
        return items.filter { $0.content.lowercased().contains(query) }
    }
    
    public func addItem(content: String, type: ClipboardContentType = .text, sourceApp: String? = nil) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Remove existing identical item if not pinned, so it jumps to top
        if let existingIndex = items.firstIndex(where: { $0.content == content }) {
            let existing = items[existingIndex]
            if existing.isPinned {
                return
            }
            items.remove(at: existingIndex)
        }
        
        let newItem = ClipboardItem(content: content, type: type, sourceApp: sourceApp)
        items.insert(newItem, at: 0)
        
        // Trim excess unpinned items
        if items.count > maxItems {
            var nonPinnedIndices = items.indices.filter { !items[$0].isPinned }
            while items.count > maxItems && !nonPinnedIndices.isEmpty {
                let removeIdx = nonPinnedIndices.removeLast()
                items.remove(at: removeIdx)
            }
        }
        
        save()
    }
    
    public func togglePin(for item: ClipboardItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPinned.toggle()
            save()
        }
    }
    
    public func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }
    
    public func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        save()
    }
    
    public func clearAll() {
        items.removeAll()
        save()
    }
    
    private func save() {
        DispatchQueue.global(qos: .utility).async { [items = self.items, url = self.storageURL] in
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(items) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        if let data = try? Data(contentsOf: storageURL),
           let loaded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            self.items = loaded
        }
    }
}
