import SwiftUI
import WebKit

public enum WebWidgetEditorMode: Identifiable {
    case create
    case edit(WebWidgetItem)

    public var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let widget):
            return "edit_\(widget.id.uuidString)"
        }
    }

    public var widget: WebWidgetItem? {
        switch self {
        case .create: return nil
        case .edit(let widget): return widget
        }
    }

    public var isEditing: Bool {
        switch self {
        case .create: return false
        case .edit: return true
        }
    }
}

public struct WebPanelSettingsView: View {
    @ObservedObject var module: WebPanelModule
    @ObservedObject var l10nObj = LocalizationManager.shared
    @State private var editorMode: WebWidgetEditorMode? = nil
    @State private var widgetToDelete: WebWidgetItem? = nil
    @State private var showingDeleteConfirm: Bool = false

    public init(module: WebPanelModule) {
        self.module = module
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let error = module.storageError { Text(error).font(.caption).foregroundColor(.red).padding() }
            if let error = WebFaviconManager.shared.legacyCleanupError { Text(error).font(.caption).foregroundColor(.red).padding() }
            // Header
            ModuleHeaderView(
                title: l10n("web_panel.title"),
                subtitle: l10n("web_panel.subtitle"),
                icon: "globe",
                isEnabled: $module.isEnabled,
                extraContent: {
                    HStack {
                        let activeCount = module.widgets.filter { $0.isEnabled }.count
                        Text(String(format: l10n("web_panel.status_count"), module.widgets.count, activeCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()

                        Button(action: {
                            editorMode = .create
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text(l10n("web_panel.add_button"))
                            }
                            .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {

                // Widgets List
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(l10n("web_panel.active_widgets"))
                            .font(.headline)
                        Spacer()
                    }

                    if module.widgets.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(l10n("web_panel.empty_title"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(l10n("web_panel.empty_subtitle"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)

                            Button(l10n("web_panel.empty_btn")) {
                                editorMode = .create
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else {
                        ForEach(module.widgets) { widget in
                            WebWidgetRowView(
                                widget: widget,
                                onToggleEnabled: { enabled in
                                    module.toggleWidget(id: widget.id, isEnabled: enabled)
                                },
                                onEdit: {
                                    editorMode = .edit(widget)
                                },
                                onUpdateWidget: { updated in
                                    module.updateWidget(updated)
                                },
                                onDelete: {
                                    widgetToDelete = widget
                                    showingDeleteConfirm = true
                                },
                                onOpen: {
                                    module.openWidgetPopover(id: widget.id)
                                }
                            )
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

                // Website Data & Cache
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text(l10n("web_panel.cache_title"))
                            .font(.headline)
                        InfoTooltip(text: l10n("web_panel.cache_tooltip"))
                    }

                    Button(role: .destructive, action: clearAllWebsiteData) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text(l10n("web_panel.cache_clear_btn"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .disabled(!module.isEnabled)
                .opacity(module.isEnabled ? 1.0 : 0.6)
            }
            .padding(20)
        }
    }
        .sheet(item: $editorMode) { mode in
            WebWidgetEditorSheet(
                initialWidget: mode.widget,
                onSave: { savedItem in
                    if mode.isEditing {
                        module.updateWidget(savedItem)
                    } else {
                        module.addWidget(savedItem)
                    }
                    editorMode = nil
                },
                onCancel: {
                    editorMode = nil
                }
            )
            .id(mode.id)
        }
        .confirmationDialog(
            String(format: l10n("web_panel.delete_alert_message"), widgetToDelete?.title ?? ""),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(l10n("common.delete"), role: .destructive) {
                if let id = widgetToDelete?.id {
                    module.deleteWidget(id: id)
                }
            }
            Button(l10n("common.cancel"), role: .cancel) {}
        }
    }

    private func clearAllWebsiteData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        // Include orphaned profiles left by deleted/corrupt legacy widget records, not only
        // identifiers that are still present in the current configuration.
        WKWebsiteDataStore.fetchAllDataStoreIdentifiers { identifiers in
            for identifier in identifiers where identifier.isValidWebKitIdentifier {
                WKWebsiteDataStore(forIdentifier: identifier)
                    .removeData(ofTypes: types, modifiedSince: .distantPast) {}
            }
        }
        // Also clear legacy default store from before profiles were introduced (AUD-08)
        WKWebsiteDataStore.default()
            .removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }
}

// MARK: - Row View

struct WebWidgetRowView: View {
    let widget: WebWidgetItem
    let onToggleEnabled: (Bool) -> Void
    let onEdit: () -> Void
    let onUpdateWidget: (WebWidgetItem) -> Void
    let onDelete: () -> Void
    let onOpen: () -> Void
    @ObservedObject private var faviconManager = WebFaviconManager.shared
    @State private var showIconPopover: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            // Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                if widget.useFavicon, let icon = faviconManager.previewIcon(for: widget.url, widgetId: widget.id, selectedFaviconURL: widget.selectedFaviconURL, removeWhite: widget.removeWhiteBackground) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: widget.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(widget.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    if widget.useFavicon {
                        Text(l10n("web_panel.badge_web_icon"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.18)))
                            .foregroundColor(.purple)
                    } else {
                        Text(l10n("web_panel.badge_symbol"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundColor(.secondary)
                    }

                    Text("\(Int(widget.effectiveWidth)) × \(Int(widget.effectiveHeight)) pt")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .foregroundColor(.secondary)

                    if widget.userAgentMode == .mobile {
                        Text(l10n("web_panel.badge_smartphone"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.18)))
                            .foregroundColor(.blue)
                    }
                }

                Text(widget.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // Actions: Arranged in a balanced 2x2 grid
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Button(action: onOpen) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                            Text(l10n("web_panel.btn_open"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(l10n("web_panel.btn_open"))

                    Button(action: { showIconPopover.toggle() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "photo")
                            Text(l10n("web_panel.btn_icon"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(l10n("web_panel.btn_icon"))
                    .popover(isPresented: $showIconPopover, arrowEdge: .trailing) {
                        WebWidgetIconPickerPopover(
                            widget: widget,
                            onUpdate: onUpdateWidget,
                            onDismiss: { showIconPopover = false }
                        )
                    }
                }

                GridRow {
                    Button(action: onEdit) {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil")
                            Text(l10n("web_panel.btn_edit"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(l10n("web_panel.btn_edit"))

                    Button(role: .destructive, action: onDelete) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text(l10n("common.delete"))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(l10n("common.delete"))
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Divider()
                .frame(height: 38)
                .padding(.horizontal, 4)

            // In Menu Bar Toggle
            VStack(spacing: 3) {
                Toggle("", isOn: Binding(
                    get: { widget.isEnabled },
                    set: { onToggleEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                Text(l10n("web_panel.menubar_label"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .help(widget.isEnabled ? "In Menüleiste aktiviert" : "In Menüleiste deaktiviert")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
    }
}

// MARK: - Dedicated Lightweight Icon & Logo Picker Popover

struct WebWidgetIconPickerPopover: View {
    let widget: WebWidgetItem
    let onUpdate: (WebWidgetItem) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var faviconManager = WebFaviconManager.shared
    @State private var useFavicon: Bool
    @State private var selectedFaviconURL: String?
    @State private var removeWhiteBackground: Bool
    @State private var iconName: String

    init(widget: WebWidgetItem, onUpdate: @escaping (WebWidgetItem) -> Void, onDismiss: @escaping () -> Void) {
        self.widget = widget
        self.onUpdate = onUpdate
        self.onDismiss = onDismiss
        _useFavicon = State(initialValue: widget.useFavicon)
        _selectedFaviconURL = State(initialValue: widget.selectedFaviconURL)
        _removeWhiteBackground = State(initialValue: widget.removeWhiteBackground)
        _iconName = State(initialValue: widget.iconName)
    }

    private func applyChange() {
        var updated = widget
        updated.useFavicon = useFavicon
        updated.selectedFaviconURL = selectedFaviconURL
        updated.removeWhiteBackground = removeWhiteBackground
        updated.iconName = iconName
        onUpdate(updated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with current live icon preview badge and title
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )

                    if useFavicon, let icon = faviconManager.previewIcon(for: widget.url, widgetId: widget.id, selectedFaviconURL: selectedFaviconURL, removeWhite: removeWhiteBackground) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 3.5))
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 15))
                            .foregroundColor(.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n("web_panel.logo_picker_header"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(widget.title)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(l10n("common.close"))
            }

            Divider()

            // Web Favicon Options
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Toggle(l10n("web_panel.logo_picker_website_logo"), isOn: Binding(
                        get: { useFavicon },
                        set: { val in
                            useFavicon = val
                            applyChange()
                        }
                    ))
                    .fontWeight(.medium)

                    InfoTooltip(text: l10n("web_panel.logo_picker_website_logo_tooltip"))
                }

                if useFavicon {
                    let options = faviconManager.options(for: widget.id)
                    if !options.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text(String(format: l10n("web_panel.logo_picker_available"), options.count))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                if selectedFaviconURL != nil {
                                    Button(l10n("web_panel.logo_picker_auto")) {
                                        selectedFaviconURL = nil
                                        applyChange()
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.link)
                                }

                                Button(action: {
                                    faviconManager.discoverFavicons(for: widget.url, widgetId: widget.id)
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help(l10n("web_panel.editor_rescan"))
                            }

                            let columns = [GridItem(.adaptive(minimum: 64, maximum: 74), spacing: 6)]
                            let grid = LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(options) { opt in
                                    let isAuto = (selectedFaviconURL == nil && opt == options.first)
                                    let isChosen = (selectedFaviconURL == opt.urlString)
                                    let isSelected = isChosen || isAuto

                                    Button(action: {
                                        selectedFaviconURL = opt.urlString
                                        applyChange()
                                    }) {
                                        VStack(spacing: 2) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color(nsColor: .controlBackgroundColor))
                                                    .frame(width: 30, height: 30)

                                                if let img = faviconManager.icon(forOption: opt.urlString, widgetId: widget.id, removeWhite: removeWhiteBackground) {
                                                    Image(nsImage: img)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(width: 18, height: 18)
                                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                                } else {
                                                    Image(systemName: "photo")
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                                            )
                                            .overlay(
                                                Group {
                                                    if isSelected {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.accentColor)
                                                            .background(Circle().fill(Color.white))
                                                            .offset(x: 11, y: -11)
                                                    }
                                                }
                                            )

                                            Text(opt.label)
                                                .font(.system(size: 8.5, weight: isSelected ? .bold : .regular))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)

                                            Text(opt.isTransparent ? l10n("web_panel.editor_badge_transparent") : l10n("web_panel.editor_badge_background"))
                                                .font(.system(size: 7, weight: .medium))
                                                .foregroundColor(opt.isTransparent ? .green : .secondary)
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 0.5)
                                                .background(Capsule().fill(opt.isTransparent ? Color.green.opacity(0.15) : Color.primary.opacity(0.06)))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help(opt.urlString)
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 1)

                            if options.count > 8 {
                                ScrollView(.vertical, showsIndicators: true) {
                                    grid
                                }
                                .frame(maxHeight: 140)
                            } else {
                                grid
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Toggle(l10n("web_panel.logo_picker_transparent_bg"), isOn: Binding(
                            get: { removeWhiteBackground },
                            set: { val in
                                removeWhiteBackground = val
                                applyChange()
                            }
                        ))
                        .font(.caption)

                        InfoTooltip(text: l10n("web_panel.logo_picker_transparent_bg_tooltip"))
                    }
                }
            }

            Divider()

            // SF Symbols Grid
            VStack(alignment: .leading, spacing: 6) {
                Text(useFavicon ? l10n("web_panel.logo_picker_fallback_symbol") : l10n("web_panel.logo_picker_select_symbol"))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28))], spacing: 6) {
                    ForEach([
                        "calendar", "calendar.badge.clock", "note.text",
                        "bubble.left.and.bubble.right", "globe", "safari",
                        "checklist", "bookmark", "envelope", "bell",
                        "sparkles", "star", "music.note", "chart.bar",
                        "chevron.left.forwardslash.chevron.right", "tray.full", "cloud", "person"
                    ], id: \.self) { icon in
                        Button(action: {
                            iconName = icon
                            applyChange()
                        }) {
                            Image(systemName: icon)
                                .font(.system(size: 13))
                                .foregroundColor(iconName == icon ? .white : .primary)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(iconName == icon ? Color.accentColor : Color(nsColor: .controlColor))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(l10n("common.done")) { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if faviconManager.options(for: widget.id).isEmpty && !widget.url.isEmpty {
                faviconManager.discoverFavicons(for: widget.url, widgetId: widget.id)
            }
        }
    }
}

// MARK: - Guided Setup / Edit Wizard with Live Preview

struct WebWidgetEditorSheet: View {
    @State private var title: String
    @State private var url: String
    @State private var iconName: String
    @State private var useFavicon: Bool
    @State private var selectedFaviconURL: String?
    @State private var removeWhiteBackground: Bool
    @State private var isLogoSettingsExpanded: Bool = false
    @State private var isSizeSettingsExpanded: Bool = false
    @State private var isExtraOptionsExpanded: Bool = false
    @State private var sizePreset: WebSizePreset
    @State private var customWidth: CGFloat
    @State private var customHeight: CGFloat
    @State private var userAgentMode: WebUserAgentMode
    @State private var zoomScale: Double
    @State private var isEnabled: Bool
    @State private var isPinned: Bool
    @State private var showsAddressBar: Bool
    @State private var showsTopBar: Bool

    @StateObject private var previewController: WebPanelController
    @ObservedObject private var faviconManager = WebFaviconManager.shared

    let isEditing: Bool
    let originalId: UUID?
    let editorWidgetId: UUID
    let onSave: (WebWidgetItem) -> Void
    let onCancel: () -> Void

    public init(
        initialWidget: WebWidgetItem?,
        startWithIconPicker: Bool = false,
        onSave: @escaping (WebWidgetItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isEditing = (initialWidget != nil)
        self.originalId = initialWidget?.id
        let targetId = initialWidget?.id ?? UUID()
        self.editorWidgetId = targetId

        let initialTitle = initialWidget?.title ?? ""
        let initialURL = initialWidget?.url ?? ""
        let initialIcon = initialWidget?.iconName ?? "globe"
        let initialUseFavicon = initialWidget?.useFavicon ?? true
        let initialSelectedFaviconURL = initialWidget?.selectedFaviconURL
        let initialRemoveWhite = initialWidget?.removeWhiteBackground ?? true
        let initialPreset = initialWidget?.sizePreset ?? .custom
        let initialW = initialWidget?.customWidth ?? 320
        let initialH = initialWidget?.customHeight ?? 400
        let initialUA = initialWidget?.userAgentMode ?? .auto
        let initialZoom = initialWidget?.zoomScale ?? 0.85
        let initialEnabled = initialWidget?.isEnabled ?? true
        let initialPinned = initialWidget?.isPinned ?? false
        let initialBar = initialWidget?.showsAddressBar ?? false
        let initialShowsTopBar = initialWidget?.showsTopBar ?? true

        _title = State(initialValue: initialTitle)
        _url = State(initialValue: initialURL)
        _iconName = State(initialValue: initialIcon)
        _useFavicon = State(initialValue: initialUseFavicon)
        _selectedFaviconURL = State(initialValue: initialSelectedFaviconURL)
        _removeWhiteBackground = State(initialValue: initialRemoveWhite)
        _isLogoSettingsExpanded = State(initialValue: startWithIconPicker)
        _isSizeSettingsExpanded = State(initialValue: false)
        _isExtraOptionsExpanded = State(initialValue: false)
        _sizePreset = State(initialValue: initialPreset)
        _customWidth = State(initialValue: initialW)
        _customHeight = State(initialValue: initialH)
        _userAgentMode = State(initialValue: initialUA)
        _zoomScale = State(initialValue: initialZoom)
        _isEnabled = State(initialValue: initialEnabled)
        _isPinned = State(initialValue: initialPinned)
        _showsAddressBar = State(initialValue: initialBar)
        _showsTopBar = State(initialValue: initialShowsTopBar)

        let targetW = initialPreset == .custom ? initialW : initialPreset.dimensions.width
        let preview = WebPanelController(
            initialURL: initialURL.isEmpty ? "about:blank" : initialURL,
            widgetID: targetId,
            userAgentMode: initialUA,
            targetWidth: targetW,
            zoomScale: initialZoom
        )
        if !initialURL.isEmpty {
            preview.associatedItem = WebWidgetItem(
                id: targetId,
                title: initialTitle,
                url: initialURL,
                useFavicon: initialUseFavicon,
                selectedFaviconURL: initialSelectedFaviconURL,
                removeWhiteBackground: initialRemoveWhite
            )
        }
        _previewController = StateObject(wrappedValue: preview)

        self.onSave = onSave
        self.onCancel = onCancel
    }

    var effectiveWidth: CGFloat {
        sizePreset == .custom ? customWidth : sizePreset.dimensions.width
    }

    var effectiveHeight: CGFloat {
        sizePreset == .custom ? customHeight : sizePreset.dimensions.height
    }

    var body: some View {
        VStack(spacing: 0) {
            // Wizard Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: isEditing ? "slider.horizontal.2.square" : "plus.square.fill.on.square.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text(isEditing ? l10n("web_panel.editor_edit_title") : l10n("web_panel.editor_new_title"))
                        .font(.title3)
                        .fontWeight(.bold)
                    InfoTooltip(text: l10n("web_panel.editor_subtitle"))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Main Content: Split into Settings (Left) and Live-Preview (Right)
            HStack(spacing: 0) {
                // Left Column: Configuration Forms
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Name & Ziel-Webseite (URL)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 26, height: 26)
                                    Image(systemName: "globe")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }

                                Text(l10n("web_panel.editor_sec1"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)

                                Spacer()
                            }

                            Divider()
                                .padding(.bottom, 2)

                            // Name Row
                            VStack(alignment: .leading, spacing: 5) {
                                Text(l10n("web_panel.editor_name_label"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 10) {
                                    // Live Icon Preview Badge
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(nsColor: .controlColor))
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                            )

                                        if useFavicon, let favicon = faviconManager.previewIcon(for: url, widgetId: editorWidgetId, selectedFaviconURL: selectedFaviconURL, removeWhite: removeWhiteBackground) {
                                            Image(nsImage: favicon)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 22, height: 22)
                                                .clipShape(RoundedRectangle(cornerRadius: 3.5))
                                        } else {
                                            Image(systemName: iconName)
                                                .font(.system(size: 17))
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .help(l10n("web_panel.editor_logo_section"))

                                    TextField(l10n("web_panel.editor_name_placeholder"), text: $title)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            // URL Row
                            VStack(alignment: .leading, spacing: 5) {
                                Text(l10n("web_panel.editor_url_label"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    TextField("https://...", text: $url, onCommit: {
                                        applyURLChange()
                                    })
                                    .textFieldStyle(.roundedBorder)

                                    Button(action: {
                                        applyURLChange()
                                    }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text(l10n("web_panel.editor_load_btn"))
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                }
                            }

                            // Schnellvorlagen
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(l10n("web_panel.editor_templates"))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    InfoTooltip(text: l10n("web_panel.editor_templates_tooltip"))
                                }

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    QuickButton(name: "Google Gemini", icon: "sparkles") {
                                        setPreset(url: "https://gemini.google.com", name: "Google Gemini", icon: "sparkles", preset: .smartphone)
                                    }
                                    QuickButton(name: "Proton Calendar", icon: "calendar") {
                                        setPreset(url: "https://calendar.proton.me", name: l10n("web_panel.template_proton_cal"), icon: "calendar", preset: .widget)
                                    }
                                    QuickButton(name: "Google Calendar", icon: "calendar") {
                                        setPreset(url: "https://calendar.google.com", name: l10n("web_panel.template_google_cal"), icon: "calendar", preset: .widget)
                                    }
                                    QuickButton(name: "Notion", icon: "note.text") {
                                        setPreset(url: "https://www.notion.so", name: "Notion", icon: "note.text", preset: .large)
                                    }
                                    QuickButton(name: "Todoist", icon: "checklist") {
                                        setPreset(url: "https://app.todoist.com", name: "Todoist", icon: "checklist", preset: .widget)
                                    }
                                    QuickButton(name: "GitHub", icon: "chevron.left.forwardslash.chevron.right") {
                                        setPreset(url: "https://github.com", name: "GitHub", icon: "chevron.left.forwardslash.chevron.right", preset: .smartphone)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )

                        // Menüleisten-Symbol & Logo (Als einklappbares Untermenü)
                        EditorCollapsibleSection(
                            icon: "photo.badge.checkmark",
                            title: l10n("web_panel.editor_logo_section"),
                            isExpanded: $isLogoSettingsExpanded,
                            trailingBadge: {
                                Text(useFavicon ? l10n("web_panel.logo_picker_auto") : l10n("web_panel.badge_symbol"))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.primary.opacity(0.06))
                                    )
                            }
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                // Website Logo Option
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Toggle(l10n("web_panel.editor_auto_logo"), isOn: $useFavicon)
                                            .fontWeight(.medium)
                                        InfoTooltip(text: l10n("web_panel.editor_auto_logo_tooltip"))
                                    }

                                    if useFavicon {
                                        // Status & Refresh
                                        HStack(spacing: 8) {
                                            if let favicon = faviconManager.previewIcon(for: url, widgetId: editorWidgetId, selectedFaviconURL: selectedFaviconURL, removeWhite: removeWhiteBackground) {
                                                Image(nsImage: favicon)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 18, height: 18)
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                                Text(selectedFaviconURL != nil ? l10n("web_panel.editor_selected_logo_active") : l10n("web_panel.editor_best_logo_active"))
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                                    .fontWeight(.medium)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text(url.isEmpty ? l10n("web_panel.editor_enter_url_hint") : l10n("web_panel.editor_searching_logos"))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            if !url.isEmpty {
                                                Button(action: {
                                                    if let web = previewController.webView {
                                                        let item = WebWidgetItem(
                                                            id: editorWidgetId,
                                                            title: title,
                                                            url: url,
                                                            useFavicon: useFavicon,
                                                            selectedFaviconURL: selectedFaviconURL,
                                                            removeWhiteBackground: removeWhiteBackground
                                                        )
                                                        previewController.associatedItem = item
                                                        faviconManager.clearCache(for: item)
                                                        faviconManager.extractFaviconFromWebView(web, for: item)
                                                        previewController.reload()
                                                    }
                                                }) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "arrow.clockwise")
                                                        Text(l10n("web_panel.editor_rescan"))
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }
                                        }
                                        .padding(8)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))

                                        // Discovered Favicon Options Gallery
                                        let options = faviconManager.options(for: editorWidgetId)
                                        if !options.isEmpty {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack(spacing: 5) {
                                                    Text(String(format: l10n("web_panel.logo_picker_available"), options.count))
                                                        .font(.caption2)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.primary)
                                                    InfoTooltip(text: l10n("web_panel.editor_options_tooltip"))

                                                    Spacer()

                                                    if selectedFaviconURL != nil {
                                                        Button(l10n("web_panel.editor_auto_select")) {
                                                            selectedFaviconURL = nil
                                                        }
                                                        .font(.caption2)
                                                        .buttonStyle(.link)
                                                    }
                                                }

                                                let editorColumns = [GridItem(.adaptive(minimum: 70, maximum: 84), spacing: 8)]
                                                let editorGrid = LazyVGrid(columns: editorColumns, spacing: 8) {
                                                    ForEach(options) { opt in
                                                        let isAuto = (selectedFaviconURL == nil && opt == options.first)
                                                        let isChosen = (selectedFaviconURL == opt.urlString)
                                                        let isSelected = isChosen || isAuto

                                                        Button(action: {
                                                            selectedFaviconURL = opt.urlString
                                                        }) {
                                                            VStack(spacing: 4) {
                                                                ZStack {
                                                                    RoundedRectangle(cornerRadius: 6)
                                                                        .fill(Color(nsColor: .controlBackgroundColor))
                                                                        .frame(width: 34, height: 34)

                                                                    if let img = faviconManager.icon(forOption: opt.urlString, widgetId: editorWidgetId, removeWhite: removeWhiteBackground) {
                                                                        Image(nsImage: img)
                                                                            .resizable()
                                                                            .aspectRatio(contentMode: .fit)
                                                                            .frame(width: 22, height: 22)
                                                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                                                    } else {
                                                                        Image(systemName: "photo")
                                                                            .foregroundColor(.secondary)
                                                                    }
                                                                }
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 6)
                                                                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                                                                )
                                                                .overlay(
                                                                    Group {
                                                                        if isSelected {
                                                                            Image(systemName: "checkmark.circle.fill")
                                                                                .font(.system(size: 11))
                                                                                .foregroundColor(.accentColor)
                                                                                .background(Circle().fill(Color.white))
                                                                                .offset(x: 13, y: -13)
                                                                        }
                                                                    }
                                                                )

                                                                Text(opt.label)
                                                                    .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                                                                    .foregroundColor(.primary)
                                                                    .lineLimit(1)

                                                                Text(opt.isTransparent ? l10n("web_panel.editor_badge_transparent") : l10n("web_panel.editor_badge_background"))
                                                                    .font(.system(size: 8, weight: .medium))
                                                                    .foregroundColor(opt.isTransparent ? .green : .secondary)
                                                                    .padding(.horizontal, 4)
                                                                    .padding(.vertical, 1)
                                                                    .background(Capsule().fill(opt.isTransparent ? Color.green.opacity(0.15) : Color.primary.opacity(0.06)))
                                                            }
                                                            .frame(maxWidth: .infinity)
                                                            .padding(5)
                                                            .background(
                                                                RoundedRectangle(cornerRadius: 8)
                                                                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                                                            )
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help(opt.urlString)
                                                    }
                                                }
                                                .padding(.vertical, 3)
                                                .padding(.horizontal, 1)

                                                if options.count > 10 {
                                                    ScrollView(.vertical, showsIndicators: true) {
                                                        editorGrid
                                                    }
                                                    .frame(maxHeight: 160)
                                                } else {
                                                    editorGrid
                                                }
                                            }
                                        }

                                        // Remove White Background Toggle
                                        HStack(spacing: 6) {
                                            Toggle(l10n("web_panel.logo_picker_transparent_bg"), isOn: $removeWhiteBackground)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            InfoTooltip(text: l10n("web_panel.editor_remove_white_tooltip"))
                                        }
                                    }
                                }

                                Divider()
                                    .padding(.vertical, 2)

                                // Symbol Selection
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 5) {
                                        Text(useFavicon ? l10n("web_panel.editor_fallback_symbol_label") : l10n("web_panel.editor_menubar_symbol_label"))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if useFavicon {
                                            InfoTooltip(text: l10n("web_panel.editor_fallback_symbol_tooltip"))
                                        }
                                    }

                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 32))], spacing: 6) {
                                        ForEach([
                                            "calendar", "calendar.badge.clock", "note.text",
                                            "bubble.left.and.bubble.right", "globe", "safari",
                                            "checklist", "bookmark", "envelope", "bell",
                                            "sparkles", "star", "music.note", "chart.bar",
                                            "chevron.left.forwardslash.chevron.right", "tray.full", "cloud", "person"
                                        ], id: \.self) { icon in
                                            Button(action: { iconName = icon }) {
                                                Image(systemName: icon)
                                                    .font(.system(size: 14))
                                                    .foregroundColor(iconName == icon ? .white : .primary)
                                                    .frame(width: 30, height: 30)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(iconName == icon ? Color.accentColor : Color(nsColor: .controlColor))
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(iconName == icon ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Fenstergröße & Ansicht (Einklappbar)
                        EditorCollapsibleSection(
                            icon: "aspectratio",
                            title: l10n("web_panel.editor_sec2"),
                            isExpanded: $isSizeSettingsExpanded,
                            trailingBadge: {
                                Text("\(Int(effectiveWidth)) × \(Int(effectiveHeight)) pt")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.accentColor.opacity(0.12))
                                    )
                            }
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker(l10n("web_panel.editor_size_label"), selection: $sizePreset) {
                                    ForEach(WebSizePreset.allCases) { preset in
                                        Text(preset.localizedTitle).tag(preset)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: sizePreset) {
                                    if sizePreset != .custom {
                                        customWidth = sizePreset.dimensions.width
                                        customHeight = sizePreset.dimensions.height
                                    }
                                    if sizePreset == .widget && (zoomScale == 1.0 || zoomScale == 0) {
                                        zoomScale = 0.85
                                    }
                                    updateLivePreview()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(l10n("web_panel.editor_width"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(customWidth)) pt").monospacedDigit()
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    Slider(value: $customWidth, in: 280...1200, step: 10) { _ in
                                        if sizePreset != .custom {
                                            sizePreset = .custom
                                        }
                                        updateLivePreview()
                                    }

                                    HStack {
                                        Text(l10n("web_panel.editor_height"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(customHeight)) pt").monospacedDigit()
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    Slider(value: $customHeight, in: 300...1000, step: 10) { _ in
                                        if sizePreset != .custom {
                                            sizePreset = .custom
                                        }
                                        updateLivePreview()
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 5) {
                                        Text(l10n("web_panel.editor_zoom"))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        InfoTooltip(text: l10n("web_panel.editor_zoom_tooltip"))
                                        Spacer()
                                        Text("\(Int(zoomScale * 100))%").monospacedDigit()
                                            .foregroundColor(.accentColor)
                                            .fontWeight(.bold)
                                    }
                                    Slider(value: $zoomScale, in: 0.5...1.5, step: 0.05) { _ in
                                        updateLivePreview()
                                    }
                                }

                                Divider()

                                HStack(spacing: 5) {
                                    Text(l10n("web_panel.editor_appearance"))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    InfoTooltip(text: l10n("web_panel.editor_appearance_tooltip"))
                                }

                                Picker("", selection: $userAgentMode) {
                                    ForEach(WebUserAgentMode.allCases) { mode in
                                        Text(mode.localizedTitle).tag(mode)
                                    }
                                }
                                .pickerStyle(.radioGroup)
                                .onChange(of: userAgentMode) {
                                    updateLivePreview()
                                }
                            }
                        }

                        // 3. Weitere Optionen (Einklappbar)
                        EditorCollapsibleSection(
                            icon: "slider.horizontal.3",
                            title: l10n("web_panel.editor_sec3"),
                            isExpanded: $isExtraOptionsExpanded
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Toggle(l10n("web_panel.editor_pin"), isOn: $isPinned)
                                    InfoTooltip(text: l10n("web_panel.editor_pin_tooltip"))
                                }

                                HStack(spacing: 6) {
                                    Toggle(l10n("web_panel.editor_nav_bar"), isOn: $showsAddressBar)
                                    InfoTooltip(text: l10n("web_panel.editor_nav_bar_tooltip"))
                                }

                                HStack(spacing: 6) {
                                    Toggle(l10n("web_panel.editor_top_bar"), isOn: $showsTopBar)
                                    InfoTooltip(text: l10n("web_panel.editor_top_bar_tooltip"))
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(width: 380)

                Divider()

                // Right Column: Live Preview Area!
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.accentColor)
                        Text(String(format: l10n("web_panel.preview_title"), Int(effectiveWidth), Int(effectiveHeight)))
                            .font(.headline)
                        Spacer()

                        Button(action: {
                            previewController.reload()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(l10n("web_panel.preview_reload"))
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    // Live Preview with isolated layout bounds
                    GeometryReader { geo in
                        let scale = previewScale(containerWidth: geo.size.width, containerHeight: geo.size.height)
                        let deviceW = max(1, effectiveWidth)
                        let deviceH = max(1, effectiveHeight + (showsTopBar ? 28 : 0))

                        ZStack {
                            // Device Frame Outline
                            VStack(spacing: 0) {
                                if showsTopBar {
                                    // Fake Titlebar
                                    HStack(spacing: 6) {
                                        Circle().fill(Color.red.opacity(0.8)).frame(width: 8, height: 8)
                                        Circle().fill(Color.yellow.opacity(0.8)).frame(width: 8, height: 8)
                                        Circle().fill(Color.green.opacity(0.8)).frame(width: 8, height: 8)
                                        Spacer()
                                        Text(title.isEmpty ? (url.isEmpty ? "Vorschau" : url) : title)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(userAgentMode == .desktop ? "Desktop" : "Mobil")
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                            .foregroundColor(.accentColor)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color(nsColor: .controlBackgroundColor))

                                    Divider()
                                }

                                // Live WebView or Placeholder when empty
                                if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "globe")
                                            .font(.system(size: 40))
                                            .foregroundColor(.secondary.opacity(0.35))
                                        Text(l10n("web_panel.preview_empty_title"))
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        Text(l10n("web_panel.preview_empty_sub"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: 240)
                                    }
                                    .frame(width: effectiveWidth, height: effectiveHeight)
                                    .background(Color(nsColor: .windowBackgroundColor))
                                } else {
                                    WebViewRepresentable(controller: previewController)
                                        .frame(width: effectiveWidth, height: effectiveHeight)
                                }
                            }
                            .frame(width: deviceW, height: deviceH)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            .scaleEffect(scale)
                            .frame(width: deviceW * scale, height: deviceH * scale)
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                    }
                    .padding(.bottom, 12)
                }
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
            }

            Divider()

            // Bottom Action Bar
            HStack {
                Button(l10n("common.cancel")) {
                    if !isEditing {
                        faviconManager.removeWidget(WebWidgetItem(id: editorWidgetId, title: "", url: ""))
                    }
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? l10n("common.save") : l10n("web_panel.editor_create_btn")) {
                    var finalURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalURL.isEmpty && !finalURL.hasPrefix("http://") && !finalURL.hasPrefix("https://") {
                        finalURL = "https://" + finalURL
                    }
                    let defaultTitle = URL(string: finalURL)?.host ?? "Web-Widget"
                    let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTitle : title

                    let item = WebWidgetItem(
                        id: originalId ?? editorWidgetId,
                        title: finalTitle,
                        url: finalURL,
                        iconName: iconName,
                        useFavicon: useFavicon,
                        selectedFaviconURL: selectedFaviconURL,
                        removeWhiteBackground: removeWhiteBackground,
                        sizePreset: sizePreset,
                        customWidth: customWidth,
                        customHeight: customHeight,
                        userAgentMode: userAgentMode,
                        zoomScale: zoomScale,
                        isEnabled: isEnabled,
                        isPinned: isPinned,
                        showsAddressBar: showsAddressBar,
                        showsTopBar: showsTopBar
                    )
                    onSave(item)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 880, idealWidth: 920, maxWidth: 1050, minHeight: 620, idealHeight: 660, maxHeight: 720)
        .onAppear {
            updateLivePreview()
            if useFavicon && !url.isEmpty {
                faviconManager.discoverFavicons(for: url, widgetId: editorWidgetId)
            }
        }
    }

    private func previewScale(containerWidth: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let padding: CGFloat = 36
        let availW = max(50, containerWidth - padding)
        let availH = max(50, containerHeight - padding)
        let targetW = max(1, effectiveWidth)
        let targetH = max(1, effectiveHeight + 28)
        let scaleW = availW / targetW
        let scaleH = availH / targetH
        return min(1.0, min(scaleW, scaleH))
    }

    private func applyURLChange() {
        var str = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return }
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        url = str
        selectedFaviconURL = nil
        updateLivePreview()
        if useFavicon {
            faviconManager.discoverFavicons(for: str, widgetId: editorWidgetId)
        }
    }

    private func setPreset(url newURL: String, name: String, icon: String, preset: WebSizePreset) {
        self.url = newURL
        self.title = name
        self.iconName = icon
        self.sizePreset = preset
        self.customWidth = preset.dimensions.width
        self.customHeight = preset.dimensions.height
        self.selectedFaviconURL = nil
        if preset == .widget {
            self.zoomScale = 0.85
        }
        updateLivePreview()
        if useFavicon {
            faviconManager.discoverFavicons(for: newURL, widgetId: editorWidgetId)
        }
    }

    private func updateLivePreview() {
        var str = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty {
            str = "about:blank"
        } else if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        let item = WebWidgetItem(
            id: editorWidgetId,
            title: title,
            url: str,
            useFavicon: useFavicon,
            selectedFaviconURL: selectedFaviconURL,
            removeWhiteBackground: removeWhiteBackground
        )
        previewController.associatedItem = item
        previewController.updateConfig(
            userAgentMode: userAgentMode,
            targetWidth: effectiveWidth,
            zoomScale: zoomScale,
            newURL: str
        )
    }
}

struct EditorCollapsibleSection<Content: View, TrailingBadge: View>: View {
    let icon: String
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let trailingBadge: () -> TrailingBadge
    @ViewBuilder let content: () -> Content

    @State private var isHeaderHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 26, height: 26)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    trailingBadge()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHeaderHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
            .onHover { hovering in
                isHeaderHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                content()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

extension EditorCollapsibleSection where TrailingBadge == EmptyView {
    init(
        icon: String,
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            icon: icon,
            title: title,
            isExpanded: isExpanded,
            trailingBadge: { EmptyView() },
            content: content
        )
    }
}

struct QuickButton: View {
    let name: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isHovered ? .accentColor : .accentColor.opacity(0.85))
                    .frame(width: 14, height: 14)

                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.4))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
