import SwiftUI
import AppKit

public struct ClipboardView: View {
    @ObservedObject var store = ClipboardHistoryStore.shared
    @State private var hoveredId: UUID?
    @State private var copiedId: UUID?
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar Header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Zwischenablage durchsuchen...", text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !store.searchQuery.isEmpty {
                    Button(action: { store.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Menu {
                    Button("Nicht angepinnte löschen") {
                        store.clearUnpinned()
                    }
                    Button("Gesamten Verlauf löschen", role: .destructive) {
                        store.clearAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // List of clipboard items
            if store.filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(store.searchQuery.isEmpty ? "Zwischenablage ist leer" : "Keine Treffer gefunden")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.filteredItems) { item in
                            ClipboardRowView(
                                item: item,
                                isHovered: hoveredId == item.id,
                                isJustCopied: copiedId == item.id,
                                onSelect: {
                                    ClipboardMonitor.shared.copyToClipboard(item.content)
                                    copiedId = item.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        if copiedId == item.id {
                                            copiedId = nil
                                        }
                                    }
                                },
                                onTogglePin: {
                                    store.togglePin(for: item)
                                },
                                onDelete: {
                                    store.removeItem(id: item.id)
                                }
                            )
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredId = item.id
                                } else if hoveredId == item.id {
                                    hoveredId = nil
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("\(store.items.count) Einträge im Verlauf")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Klick zum Kopieren")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 360, height: 420)
    }
}

struct ClipboardRowView: View {
    let item: ClipboardItem
    let isHovered: Bool
    let isJustCopied: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                // Type icon
                Image(systemName: iconForType(item.type))
                    .foregroundColor(iconColorForType(item.type))
                    .font(.system(size: 13))
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                
                // Content preview
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.preview)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 6) {
                        if let app = item.sourceApp {
                            Text(app)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(formatTime(item.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        Text("• \(item.characterCount) Zeichen")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                
                Spacer()
                
                if isJustCopied {
                    Text("Kopiert!")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.trailing, 4)
                }
                
                // Action buttons on hover or pin
                if isHovered || item.isPinned {
                    HStack(spacing: 4) {
                        Button(action: onTogglePin) {
                            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 11))
                                .foregroundColor(item.isPinned ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(item.isPinned ? "Lösen" : "Anpinnen")
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Löschen")
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconForType(_ type: ClipboardContentType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .file: return "doc"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
    
    private func iconColorForType(_ type: ClipboardContentType) -> Color {
        switch type {
        case .text: return .secondary
        case .url: return .blue
        case .file: return .orange
        case .code: return .purple
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
