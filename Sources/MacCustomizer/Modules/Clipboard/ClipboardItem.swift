import Foundation
import AppKit

public enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case url
    case file
    case code
    case image
}

public struct ClipboardItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let content: String
    public let type: ClipboardContentType
    public let createdAt: Date
    public var isPinned: Bool
    public var sourceApp: String?
    public var imageFileName: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var imageByteSize: Int?
    
    public init(
        id: UUID = UUID(),
        content: String,
        type: ClipboardContentType = .text,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        sourceApp: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        imageByteSize: Int? = nil
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.sourceApp = sourceApp
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageByteSize = imageByteSize
    }
    
    public var imageURL: URL? {
        guard let fileName = imageFileName else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("MacCustomizer", isDirectory: true)
            .appendingPathComponent("clipboard_images", isDirectory: true)
            .appendingPathComponent(fileName)
    }
    
    public var image: NSImage? {
        guard let url = imageURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
    
    public var formattedDimensions: String {
        if let w = imageWidth, let h = imageHeight, w > 0, h > 0 {
            return "\(w) × \(h) px"
        }
        return ""
    }
    
    public var formattedByteSize: String {
        guard let bytes = imageByteSize, bytes > 0 else { return "" }
        let kb = Double(bytes) / 1024.0
        if kb >= 1024.0 {
            return String(format: "%.1f MB", kb / 1024.0)
        } else {
            return String(format: "%.0f KB", kb)
        }
    }
    
    public var preview: String {
        if type == .image {
            if !formattedDimensions.isEmpty {
                return "Foto / Grafik (\(formattedDimensions))"
            }
            return "Foto / Grafik"
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 120 {
            return String(trimmed.prefix(120)) + "…"
        }
        return trimmed
    }
    
    public var characterCount: Int {
        content.count
    }
    
    public var lineCount: Int {
        content.components(separatedBy: .newlines).count
    }
}
