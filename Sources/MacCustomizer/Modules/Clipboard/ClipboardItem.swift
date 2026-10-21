import Foundation

public enum ClipboardContentType: String, Codable {
    case text
    case url
    case file
    case code
}

public struct ClipboardItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let content: String
    public let type: ClipboardContentType
    public let createdAt: Date
    public var isPinned: Bool
    public var sourceApp: String?
    
    public init(
        id: UUID = UUID(),
        content: String,
        type: ClipboardContentType = .text,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        sourceApp: String? = nil
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.sourceApp = sourceApp
    }
    
    public var preview: String {
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
