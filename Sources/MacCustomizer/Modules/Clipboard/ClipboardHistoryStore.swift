import Foundation
import Combine
import AppKit

public final class ClipboardHistoryStore: ObservableObject {
    public static let shared = ClipboardHistoryStore()
    
    @Published public var items: [ClipboardItem] = []
    @Published public var searchQuery: String = ""
    @Published public var maxItems: Int = 100
    
    private let storageURL: URL
    private let imagesDirectory: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("MacCustomizer", isDirectory: true)
        self.imagesDirectory = directory.appendingPathComponent("clipboard_images", isDirectory: true)
        
        let dirAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: dirAttributes)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: dirAttributes)
        try? FileManager.default.setAttributes(dirAttributes, ofItemAtPath: directory.path)
        try? FileManager.default.setAttributes(dirAttributes, ofItemAtPath: imagesDirectory.path)
        
        self.storageURL = directory.appendingPathComponent("clipboard_history.json")
        load()
    }
    
    public var filteredItems: [ClipboardItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedQuery.isEmpty {
            return items
        }
        return items.filter { item in
            if item.content.lowercased().contains(trimmedQuery) { return true }
            if let app = item.sourceApp, app.lowercased().contains(trimmedQuery) { return true }
            if item.type == .image && item.formattedDimensions.lowercased().contains(trimmedQuery) { return true }
            return false
        }
    }
    
    public func addItem(content: String, type: ClipboardContentType = .text, sourceApp: String? = nil) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Remove existing identical item if not pinned, so it jumps to top
        if let existingIndex = items.firstIndex(where: { $0.content == content && $0.type != .image }) {
            let existing = items[existingIndex]
            if existing.isPinned {
                return
            }
            items.remove(at: existingIndex)
        }
        
        let newItem = ClipboardItem(content: content, type: type, sourceApp: sourceApp)
        items.insert(newItem, at: 0)
        
        trimExcessItems()
        save()
    }
    
    public func addImageItem(image: NSImage, sourceApp: String? = nil, isScreenshot: Bool? = nil) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }
        
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let byteSize = pngData.count
        
        // Avoid duplicate spam if identical image size was copied in the last entry
        if let first = items.first, first.type == .image, first.imageByteSize == byteSize, first.imageWidth == width, first.imageHeight == height {
            return
        }
        
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        do {
            try pngData.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            return
        }
        
        let isScreen = isScreenshot ?? {
            if let app = sourceApp?.lowercased() {
                return app.contains("screenshot") ||
                       app.contains("bildschirmfoto") ||
                       app.contains("screencapture") ||
                       app.contains("cleanshot") ||
                       app.contains("shottr") ||
                       app.contains("snagit") ||
                       app.contains("kap") ||
                       app.contains("grab")
            }
            return false
        }()
        
        let newItem = ClipboardItem(
            id: id,
            content: "\(isScreen ? "Screenshot" : "Bild") (\(width) × \(height))",
            type: .image,
            createdAt: Date(),
            sourceApp: sourceApp,
            imageFileName: fileName,
            imageWidth: width,
            imageHeight: height,
            imageByteSize: byteSize,
            isScreenshot: isScreen
        )
        
        items.insert(newItem, at: 0)
        trimExcessItems()
        save()
        
        ClipboardImageCache.shared.preheatThumbnail(for: fileName, originalURL: fileURL, maxPixelSize: 120)
        ClipboardImageCache.shared.preheatThumbnail(for: fileName, originalURL: fileURL, maxPixelSize: 300)
    }
    
    public func togglePin(for item: ClipboardItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPinned.toggle()
            save()
        }
    }
    
    public func removeItem(id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            deleteImageFileIfNeeded(for: item)
        }
        items.removeAll { $0.id == id }
        save()
    }
    
    public func clearUnpinned() {
        for item in items where !item.isPinned {
            deleteImageFileIfNeeded(for: item)
        }
        items.removeAll { !$0.isPinned }
        save()
    }
    
    public func clearAll() {
        for item in items {
            deleteImageFileIfNeeded(for: item)
        }
        items.removeAll()
        save()
    }
    
    private func trimExcessItems() {
        if items.count > maxItems {
            var nonPinnedIndices = items.indices.filter { !items[$0].isPinned }
            while items.count > maxItems && !nonPinnedIndices.isEmpty {
                let removeIdx = nonPinnedIndices.removeLast()
                let item = items[removeIdx]
                deleteImageFileIfNeeded(for: item)
                items.remove(at: removeIdx)
            }
        }
    }
    
    private func deleteImageFileIfNeeded(for item: ClipboardItem) {
        guard let fileName = item.imageFileName else { return }
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        ClipboardImageCache.shared.evict(fileName: fileName)
        
        let prefix = fileName.replacingOccurrences(of: ".png", with: "")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path) {
            for f in files where f.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(f))
            }
        }
    }
    
    private func save() {
        DispatchQueue.global(qos: .utility).async { [items = self.items, url = self.storageURL] in
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(items) {
                try? data.write(to: url, options: [.atomic, .completeFileProtection])
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
