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

public enum ClipboardPreviewDismissalAction: Equatable {
    case none
    case closePreviewOnly
    case closePreviewAndPopover
}

public enum ClipboardPreviewDismissalPolicy {
    public static func actionForOutsideEvent(
        isPinned: Bool,
        isPreviewShown: Bool,
        isPopoverShown: Bool,
        clickedInsidePreview: Bool,
        clickedInsidePopover: Bool
    ) -> ClipboardPreviewDismissalAction {
        guard !isPinned else { return .none }
        if isPreviewShown {
            return clickedInsidePreview ? .none : .closePreviewAndPopover
        }
        if isPopoverShown {
            return clickedInsidePopover ? .none : .closePreviewAndPopover
        }
        return .none
    }
}

public final class ClipboardImagePreviewController: NSObject {
    public static let shared = ClipboardImagePreviewController()

    private final class PreviewPanel: NSPanel {
        var onEscape: (() -> Void)?

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func cancelOperation(_ sender: Any?) {
            onEscape?()
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onEscape?()
                return
            }
            super.keyDown(with: event)
        }
    }

    private var panel: PreviewPanel?
    private weak var parentWindow: NSWindow?

    public var isShown: Bool {
        panel?.isVisible == true
    }

    public var panelWindow: NSWindow? {
        panel
    }

    private override init() {
        super.init()
    }

    public func present(
        item: ClipboardItem,
        relativeTo parentWindow: NSWindow?,
        onCopy: @escaping () -> Void,
        onOpenFullImage: @escaping () -> Void
    ) {
        closePreviewOnly(restoreParentFocus: false)

        let panelSize = NSSize(width: 520, height: 440)
        let targetScreen = parentWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        var origin: NSPoint
        if let parentFrame = parentWindow?.frame {
            origin = NSPoint(
                x: parentFrame.midX - panelSize.width / 2,
                y: parentFrame.midY - panelSize.height / 2
            )
        } else if let visibleFrame = targetScreen?.visibleFrame {
            origin = NSPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.midY - panelSize.height / 2
            )
        } else {
            origin = NSPoint(x: 200, y: 200)
        }

        if let visibleFrame = targetScreen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
            origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - panelSize.height - 8)
        }

        let panel = PreviewPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.level = parentWindow?.level ?? .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.onEscape = { [weak self] in
            self?.closePreviewOnly()
        }

        let modalView = ImageDetailModalView(
            item: item,
            onCopy: onCopy,
            onOpenFullImage: onOpenFullImage,
            onClose: { [weak self] in
                self?.closePreviewOnly()
            }
        )
        let hostingController = NSHostingController(rootView: modalView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController

        self.panel = panel
        self.parentWindow = parentWindow

        if let parentWindow {
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    public func closePreviewOnly(restoreParentFocus: Bool = true) {
        let parent = self.parentWindow
        if let panel = self.panel {
            if let attachedParent = panel.parent {
                attachedParent.removeChildWindow(panel)
            }
            panel.orderOut(nil)
            panel.contentViewController = nil
            panel.onEscape = nil
            self.panel = nil
        }
        self.parentWindow = nil

        if restoreParentFocus, let parent, parent.isVisible {
            parent.makeKey()
        }
    }
}

public final class ClipboardFullImageWindowController: NSObject, NSWindowDelegate {
    public static let shared = ClipboardFullImageWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public static func initialContentSize(for item: ClipboardItem, visibleFrame: CGRect) -> CGSize {
        let minWidth: CGFloat = 520
        let minHeight: CGFloat = 400
        let maxWidth = max(minWidth, floor(visibleFrame.width * 0.85))
        let maxHeight = max(minHeight, floor(visibleFrame.height * 0.85))

        guard let w = item.imageWidth, let h = item.imageHeight, w > 0, h > 0 else {
            return CGSize(width: min(760, maxWidth), height: min(560, maxHeight))
        }

        let chromeHeight: CGFloat = 84
        let desiredWidth = CGFloat(w)
        let desiredHeight = CGFloat(h) + chromeHeight

        if desiredWidth <= maxWidth && desiredHeight <= maxHeight {
            return CGSize(
                width: max(minWidth, desiredWidth),
                height: max(minHeight, desiredHeight)
            )
        }

        let availableImageHeight = max(200, maxHeight - chromeHeight)
        let scale = min(maxWidth / desiredWidth, availableImageHeight / CGFloat(h), 1.0)
        let scaledW = floor(desiredWidth * scale)
        let scaledH = floor(CGFloat(h) * scale) + chromeHeight

        return CGSize(
            width: min(maxWidth, max(minWidth, scaledW)),
            height: min(maxHeight, max(minHeight, scaledH))
        )
    }

    public func present(item: ClipboardItem) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let contentSize = Self.initialContentSize(for: item, visibleFrame: visibleFrame)

        let targetWindow: NSWindow
        if let existing = window {
            targetWindow = existing
        } else {
            let created = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.minSize = NSSize(width: 480, height: 360)
            created.isReleasedWhenClosed = false
            created.delegate = self
            SettingsWindowPolicy.apply(to: created)
            self.window = created
            targetWindow = created
        }

        targetWindow.title = item.isScreenshotItem
            ? l10n("clipboard.preview_title_screenshot")
            : l10n("clipboard.preview_title_image")
        SettingsWindowPolicy.apply(to: targetWindow)
        targetWindow.contentViewController = NSHostingController(
            rootView: ClipboardFullImageView(item: item) {
                ClipboardMonitor.shared.copyItemToClipboard(item)
            }
        )
        targetWindow.setContentSize(contentSize)
        targetWindow.center()
        targetWindow.orderFrontRegardless()
        targetWindow.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow === window {
            closingWindow.contentViewController = nil
        }
    }
}

private struct ClipboardWindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowObservingView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? WindowObservingView {
            view.onResolve = onResolve
            DispatchQueue.main.async {
                onResolve(view.window)
            }
        }
    }

    private final class WindowObservingView: NSView {
        var onResolve: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onResolve?(window)
        }
    }
}

public struct ClipboardView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var l10nObj = LocalizationManager.shared
    @State private var selectedTab: ClipboardTabFilter = .all
    @State private var hostingWindow: NSWindow? = nil
    public var onCopy: (() -> Void)?
    public var onDismissPopover: (() -> Void)?
    private let pinPreference: PopoverPinPreference?
    
    public init(
        store: ClipboardHistoryStore = .shared,
        onCopy: (() -> Void)? = nil,
        onDismissPopover: (() -> Void)? = nil,
        pinPreference: PopoverPinPreference? = nil
    ) {
        self.store = store
        self.onCopy = onCopy
        self.onDismissPopover = onDismissPopover
        self.pinPreference = pinPreference
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
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
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
                Text(String(format: l10n("clipboard.items_count_format"), displayedItems.count, store.items.count))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(l10n("clipboard.footer_hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
                if let pinPreference {
                    PopoverPinButton(preference: pinPreference)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 380, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            ClipboardWindowReader { window in
                if let window {
                    hostingWindow = window
                }
            }
            .frame(width: 0, height: 0)
        )
        .environment(\.controlActiveState, .active)
        .focusEffectDisabled()
    }
    
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 12) {
            if selectedTab == .images {
                Image(systemName: "photo")
                    .font(.system(size: 38))
                    .foregroundColor(.accentColor.opacity(0.7))
                Text(l10n("clipboard.empty_images_title"))
                    .font(.headline)
                Text(l10n("clipboard.empty_images_sub"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
            } else if selectedTab == .pinned {
                Image(systemName: "pin.slash")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text(l10n("clipboard.empty_pinned_title"))
                    .font(.headline)
                Text(l10n("clipboard.empty_pinned_sub"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text(store.searchQuery.isEmpty ? l10n("clipboard.empty_history_title") : l10n("clipboard.empty_no_results"))
                    .font(.headline)
                Text(l10n("clipboard.empty_history_sub"))
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
                        onZoom: item.type == .image ? {
                            ClipboardImagePreviewController.shared.present(
                                item: item,
                                relativeTo: hostingWindow ?? NSApp.keyWindow,
                                onCopy: {
                                    ClipboardMonitor.shared.copyItemToClipboard(item)
                                    onCopy?()
                                },
                                onOpenFullImage: {
                                    ClipboardImagePreviewController.shared.closePreviewOnly(restoreParentFocus: false)
                                    if let pinPreference, !pinPreference.isPinned {
                                        PopoverFocusCoordinator.shared.cancelSuppression()
                                        onDismissPopover?()
                                    }
                                    ClipboardFullImageWindowController.shared.present(item: item)
                                }
                            )
                        } : nil
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
                            if app.contains("iPhone") || app.contains("iPad") || app.contains("Universal Clipboard") {
                                HStack(spacing: 3) {
                                    Image(systemName: "iphone")
                                    Text(app)
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            } else {
                                Text(app)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(formatTime(item.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        if item.type == .image && !item.formattedByteSize.isEmpty {
                            Text("• \(item.formattedByteSize)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                        } else if item.type != .image {
                            Text("• \(item.characterCount) \(l10n("clipboard.characters"))")
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
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .focusEffectDisabled()
                            .help(l10n("clipboard.zoom"))
                        }
                        
                        Button(action: onTogglePin) {
                            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 11))
                                .foregroundColor(item.isPinned ? .accentColor : .secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
                        .help(item.isPinned ? l10n("clipboard.unpin") : l10n("clipboard.pin"))
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
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
        formatter.locale = Locale(identifier: LocalizationManager.shared.effectiveLanguage.rawValue)
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Detail Modal View
struct ImageDetailModalView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onOpenFullImage: () -> Void
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10nObj = LocalizationManager.shared
    @State private var fullImage: NSImage? = nil
    @State private var isImageHovered: Bool = false

    private func closePreview() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.isScreenshotItem ? l10n("clipboard.preview_title_screenshot") : l10n("clipboard.preview_title_image"))
                        .font(.headline)
                    if let app = item.sourceApp {
                        Text(String(format: l10n("clipboard.copied_from_format"), app))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { closePreview() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            
            // Image Canvas
            ZStack {
                if let img = fullImage {
                    Button(action: { onOpenFullImage() }) {
                        ZStack(alignment: .bottomTrailing) {
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

                            if isImageHovered {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(l10n("clipboard.open_full_image"))
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.72)))
                                .padding(8)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .onHover { hovering in
                        isImageHovered = hovering
                    }
                    .help(l10n("clipboard.open_full_image"))
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
            HStack(spacing: 10) {
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

                Button(action: { onOpenFullImage() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text(l10n("clipboard.open_full_image"))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .foregroundColor(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                
                Button(action: {
                    onCopy()
                    closePreview()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                        Text(l10n("clipboard.copy_to_clipboard"))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                    .foregroundColor(.white)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(width: 520, height: 440)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.controlActiveState, .active)
        .focusEffectDisabled()
    }
}

// MARK: - Full Image Window View
struct ClipboardFullImageView: View {
    let item: ClipboardItem
    let onCopy: () -> Void

    @ObservedObject private var l10nObj = LocalizationManager.shared
    @State private var fullImage: NSImage? = nil
    @State private var isFitToWindow: Bool = true
    @State private var zoomScale: CGFloat = 1.0
    @State private var isJustCopied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.isScreenshotItem ? l10n("clipboard.preview_title_screenshot") : l10n("clipboard.preview_title_image"))
                        .font(.headline)
                    if let app = item.sourceApp {
                        Text(String(format: l10n("clipboard.copied_from_format"), app))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Zoom controls
                HStack(spacing: 4) {
                    Button(action: {
                        isFitToWindow = true
                    }) {
                        Text(l10n("clipboard.fit_to_window"))
                            .font(.system(size: 11, weight: isFitToWindow ? .semibold : .regular))
                            .foregroundColor(isFitToWindow ? .white : .primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isFitToWindow ? Color.accentColor : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()

                    Divider()
                        .frame(height: 14)

                    Button(action: {
                        isFitToWindow = false
                        zoomScale = max(0.25, zoomScale - 0.25)
                    }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()

                    Button(action: {
                        isFitToWindow = false
                        zoomScale = 1.0
                    }) {
                        Text(isFitToWindow ? "100%" : "\(Int(zoomScale * 100))%")
                            .font(.system(size: 11, weight: !isFitToWindow && abs(zoomScale - 1.0) < 0.01 ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundColor(!isFitToWindow ? .primary : .secondary)
                            .frame(minWidth: 42)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(!isFitToWindow ? Color(nsColor: .controlColor) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()

                    Button(action: {
                        isFitToWindow = false
                        zoomScale = min(4.0, zoomScale + 0.25)
                    }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Main Image Canvas
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if let img = fullImage {
                    if isFitToWindow {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        GeometryReader { geo in
                            ScrollView([.horizontal, .vertical]) {
                                Image(nsImage: img)
                                    .resizable()
                                    .frame(
                                        width: max(1, img.size.width * zoomScale),
                                        height: max(1, img.size.height * zoomScale)
                                    )
                                    .padding(16)
                                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .center)
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom Footer
            HStack(spacing: 14) {
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

                if isJustCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(l10n("clipboard.copied"))
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                }

                Button(action: {
                    onCopy()
                    isJustCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isJustCopied = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                        Text(l10n("clipboard.copy_to_clipboard"))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                    .foregroundColor(.white)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 480, minHeight: 360)
        .focusEffectDisabled()
        .onAppear {
            loadFullResolutionImage()
        }
        .onChange(of: item.id) {
            fullImage = nil
            loadFullResolutionImage()
        }
    }

    private func loadFullResolutionImage() {
        let targetItem = item
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = ClipboardHistoryStore.shared.imageData(for: targetItem),
                  let cgImage = try? BoundedImage.decode(data) else {
                return
            }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                if targetItem.id == self.item.id {
                    self.fullImage = image
                }
            }
        }
    }
}
