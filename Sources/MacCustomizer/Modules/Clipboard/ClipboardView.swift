import SwiftUI
import AppKit

public enum ClipboardTabFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case text = "text"
    case images = "images"
    case pinned = "pinned"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .all: return l10n("clipboard.all")
        case .text: return l10n("clipboard.texts")
        case .images: return l10n("clipboard.images")
        case .pinned: return l10n("clipboard.favorites")
        }
    }
    
    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .images: return "photo"
        case .pinned: return "pin.fill"
        }
    }
}

public struct ClipboardView: View {
    @ObservedObject var store = ClipboardHistoryStore.shared
    @ObservedObject var l10nObj = LocalizationManager.shared
    @State private var selectedTab: ClipboardTabFilter = .all
    @State private var previewItem: ClipboardItem? = nil
    public var onCopy: (() -> Void)?
    
    public init(onCopy: (() -> Void)? = nil) {
        self.onCopy = onCopy
    }
    
    private var displayedItems: [ClipboardItem] {
        let baseItems = store.filteredItems
        switch selectedTab {
        case .all:
            return baseItems
        case .text:
            return baseItems.filter { $0.type != .image }
        case .images:
            return baseItems.filter { $0.type == .image }
        case .pinned:
            return baseItems.filter { $0.isPinned }
        }
    }
    
    private var imageItemsCount: Int {
        store.items.filter { $0.type == .image }.count
    }
    
    private var textItemsCount: Int {
        store.items.filter { $0.type != .image }.count
    }
    
    private var pinnedItemsCount: Int {
        store.items.filter { $0.isPinned }.count
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar Header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(l10n("clipboard.search"), text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        if let firstItem = displayedItems.first {
                            ClipboardMonitor.shared.copyItemToClipboard(firstItem)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onCopy?()
                            }
                        }
                    }
                
                if !store.searchQuery.isEmpty {
                    Button(action: { store.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Menu {
                    Button(l10n("clipboard.clear_unpinned")) {
                        store.clearUnpinned()
                    }
                    Button(l10n("clipboard.clear_all"), role: .destructive) {
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
            
            // Category Tabs Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(ClipboardTabFilter.allCases) { tab in
                        let isSelected = selectedTab == tab
                        let count: Int = {
                            switch tab {
                            case .all: return store.items.count
                            case .text: return textItemsCount
                            case .images: return imageItemsCount
                            case .pinned: return pinnedItemsCount
                            }
                        }()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedTab = tab
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11))
                                Text(tab.title)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .lineLimit(1)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.18))
                                        )
                                        .foregroundColor(isSelected ? .white : .secondary)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content Area
            if displayedItems.isEmpty {
                emptyStateView()
            } else {
                // List View for All tabs (Alle, Texte, Bilder, Favoriten)
                itemListView()
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("\(displayedItems.count) von \(store.items.count) Einträgen")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Klick zum Kopieren in Zwischenablage")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 380, height: 480)
        .sheet(item: $previewItem) { item in
            ImageDetailModalView(item: item) {
                ClipboardMonitor.shared.copyItemToClipboard(item)
                onCopy?()
            }
        }
    }
    
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 12) {
            if selectedTab == .images {
                Image(systemName: "photo")
                    .font(.system(size: 38))
                    .foregroundColor(.accentColor.opacity(0.7))
                Text("Keine Bilder im Zwischenspeicher")
                    .font(.headline)
                Text("Kopiere ein Bild im Browser, erstelle einen Screenshot oder kopiere eine Bilddatei im Finder – sie erscheint sofort hier.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
            } else if selectedTab == .pinned {
                Image(systemName: "pin.slash")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("Keine Favoriten vorhanden")
                    .font(.headline)
                Text("Bewege die Maus über einen Eintrag und klicke auf das Pin-Symbol, um ihn dauerhaft oben zu behalten.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text(store.searchQuery.isEmpty ? "Zwischenablage ist leer" : "Keine Treffer gefunden")
                    .font(.headline)
                Text("Kopierte Texte, Links und Bilder werden hier automatisch erfasst.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
    
    @ViewBuilder
    private func itemListView() -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(displayedItems) { item in
                    ClipboardRowView(
                        item: item,
                        onSelect: {
                            ClipboardMonitor.shared.copyItemToClipboard(item)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onCopy?()
                            }
                        },
                        onTogglePin: { store.togglePin(for: item) },
                        onDelete: { store.removeItem(id: item.id) },
                        onZoom: item.type == .image ? { previewItem = item } : nil
                    )
                }
            }
            .padding(6)
        }
    }
}

// MARK: - Fast Thumbnail View
struct ClipboardThumbnailView: View {
    let item: ClipboardItem
    let maxPixelSize: CGFloat
    
    @State private var thumbnail: NSImage?
    
    init(item: ClipboardItem, maxPixelSize: CGFloat = 200) {
        self.item = item
        self.maxPixelSize = maxPixelSize
        // Immediate synchronous memory cache check: if already cached, 0ms latency, zero flicker!
        _thumbnail = State(initialValue: ClipboardImageCache.shared.cachedThumbnail(for: item, maxPixelSize: maxPixelSize))
    }
    
    var body: some View {
        ZStack {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.4))
                    )
            }
        }
        .onAppear {
            if thumbnail == nil {
                ClipboardImageCache.shared.loadThumbnail(for: item, maxPixelSize: maxPixelSize) { img in
                    self.thumbnail = img
                }
            }
        }
        .onChange(of: item.id) {
            if let cached = ClipboardImageCache.shared.cachedThumbnail(for: item, maxPixelSize: maxPixelSize) {
                self.thumbnail = cached
            } else {
                self.thumbnail = nil
                ClipboardImageCache.shared.loadThumbnail(for: item, maxPixelSize: maxPixelSize) { img in
                    self.thumbnail = img
                }
            }
        }
    }
}

// MARK: - Row View for List Mode
struct ClipboardRowView: View {
    let item: ClipboardItem
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    var onZoom: (() -> Void)? = nil
    
    @State private var isHovered: Bool = false
    @State private var isJustCopied: Bool = false
    
    var body: some View {
        Button(action: {
            isJustCopied = true
            onSelect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isJustCopied = false
            }
        }) {
            HStack(alignment: .center, spacing: 10) {
                // If item is image, show miniature thumbnail
                if item.type == .image {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.1))
                            .frame(width: 44, height: 44)
                        
                        ClipboardThumbnailView(item: item, maxPixelSize: 120)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                } else {
                    // Type icon
                    Image(systemName: iconForType(item.type))
                        .foregroundColor(iconColorForType(item.type))
                        .font(.system(size: 13))
                        .frame(width: 20, height: 20)
                }
                
                // Content preview
                VStack(alignment: .leading, spacing: 3) {
                    if item.type == .image {
                        HStack(spacing: 6) {
                            Text(item.imageTypeTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                            if !item.formattedDimensions.isEmpty {
                                Text(item.formattedDimensions)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text(item.preview)
                            .font(.system(size: 12))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.primary)
                    }
                    
                    HStack(spacing: 6) {
                        if let app = item.sourceApp {
                            Text(app)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(formatTime(item.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        if item.type == .image && !item.formattedByteSize.isEmpty {
                            Text("• \(item.formattedByteSize)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                        } else if item.type != .image {
                            Text("• \(item.characterCount) Zeichen")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
                
                Spacer()
                
                if isJustCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(l10n("clipboard.copied"))
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .padding(.trailing, 4)
                }
                
                // Action buttons
                if isHovered || item.isPinned {
                    HStack(spacing: 6) {
                        if let onZoom = onZoom {
                            Button(action: onZoom) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(l10n("clipboard.zoom"))
                        }
                        
                        Button(action: onTogglePin) {
                            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 11))
                                .foregroundColor(item.isPinned ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(item.isPinned ? l10n("clipboard.unpin") : l10n("clipboard.pin"))
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(l10n("clipboard.delete"))
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
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func iconForType(_ type: ClipboardContentType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .file: return "doc"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        }
    }
    
    private func iconColorForType(_ type: ClipboardContentType) -> Color {
        switch type {
        case .text: return .secondary
        case .url: return .blue
        case .file: return .orange
        case .code: return .purple
        case .image: return .green
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Detail Modal View
struct ImageDetailModalView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: NSImage? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.imageTypeTitle)-Vorschau")
                        .font(.headline)
                    if let app = item.sourceApp {
                        Text("Kopiert aus: \(app)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            
            // Image Canvas
            ZStack {
                if let img = fullImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 480, maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                } else {
                    ProgressView()
                        .frame(maxWidth: 480, maxHeight: 340)
                }
            }
            .padding(.horizontal, 16)
            .onAppear {
                ClipboardImageCache.shared.loadFullImage(for: item) { img in
                    self.fullImage = img
                }
            }
            
            // Info bar
            HStack(spacing: 16) {
                if !item.formattedDimensions.isEmpty {
                    Label(item.formattedDimensions, systemImage: "aspectratio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !item.formattedByteSize.isEmpty {
                    Label(item.formattedByteSize, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: {
                    onCopy()
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                        Text("In Zwischenablage kopieren")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(width: 520, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
