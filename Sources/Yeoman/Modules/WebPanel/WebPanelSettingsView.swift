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
                        Text("\(module.widgets.count) Web-Widget(s) eingerichtet • \(module.widgets.filter { $0.isEnabled }.count) aktiv in der Menüleiste")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        Button(action: {
                            editorMode = .create
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Neues Web-Widget hinzufügen")
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
                        Text("Deine aktiven Web-Widgets")
                            .font(.headline)
                        Spacer()
                    }
                    
                    if module.widgets.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Noch keine Web-Widgets erstellt")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Klicke auf den Button oben, um dein erstes Web-Widget anzulegen.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
                            
                            Button("Jetzt erstes Widget anlegen") {
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
                        Text("Sitzungen & Cache")
                            .font(.headline)
                        InfoTooltip(text: "Cookies und Logins aller Widgets (z. B. Proton Calendar oder Google) werden dauerhaft im WebKit-Speicher gesichert.")
                    }
                    
                    Button(role: .destructive, action: clearAllWebsiteData) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Alle Cache- und Website-Daten löschen")
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
            "Möchtest du das Web-Widget „\(widgetToDelete?.title ?? "")“ wirklich löschen?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let id = widgetToDelete?.id {
                    module.deleteWidget(id: id)
                }
            }
            Button("Abbrechen", role: .cancel) {}
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
                        Text("Web-Icon")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.18)))
                            .foregroundColor(.purple)
                    } else {
                        Text("Symbol")
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
                        Text("Smartphone")
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
            
            // Actions: Arranged in a balanced 2x2 grid (Öffnen + Icon oben, Bearbeiten + Löschen unten)
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Button(action: onOpen) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Öffnen")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Fenster in Menüleiste öffnen")
                    
                    Button(action: { showIconPopover.toggle() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "photo")
                            Text("Icon")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Menüleisten-Symbol & Logo anpassen")
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
                            Text("Bearbeiten")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Widget bearbeiten")
                    
                    Button(role: .destructive, action: onDelete) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text("Löschen")
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Widget löschen")
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
                
                Text("Menüleiste")
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
                    Text("Symbol & Logo wählen")
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
                .help("Schließen")
            }
            
            Divider()
            
            // Web Favicon Options
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Toggle("Website-Logo verwenden", isOn: Binding(
                        get: { useFavicon },
                        set: { val in
                            useFavicon = val
                            applyChange()
                        }
                    ))
                    .fontWeight(.medium)
                    
                    InfoTooltip(text: "Verwendet das farbige Original-Logo der Website direkt in der Menüleiste.")
                }
                
                if useFavicon {
                    let options = faviconManager.options(for: widget.id)
                    if !options.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text("Verfügbare Logos (\(options.count)):")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                if selectedFaviconURL != nil {
                                    Button("Automatisch") {
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
                                .help("Neu scannen")
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
                                            
                                            Text(opt.isTransparent ? "Transparent" : "Hintergrund")
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
                        Toggle("Weißer Hintergrund transparent machen", isOn: Binding(
                            get: { removeWhiteBackground },
                            set: { val in
                                removeWhiteBackground = val
                                applyChange()
                            }
                        ))
                        .font(.caption)
                        
                        InfoTooltip(text: "Entfernt automatisch weiße Flächen aus quadratischen Logos.")
                    }
                }
            }
            
            Divider()
            
            // SF Symbols Grid
            VStack(alignment: .leading, spacing: 6) {
                Text(useFavicon ? "Ersatz-Symbol (Fallback):" : "Symbol auswählen:")
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
                Button("Fertig") { onDismiss() }
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
    
    @StateObject private var previewController: WebPanelController
    @ObservedObject private var faviconManager = WebFaviconManager.shared
    
    let isEditing: Bool
    let originalId: UUID?
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
        
        let targetW = initialPreset == .custom ? initialW : initialPreset.dimensions.width
        _previewController = StateObject(wrappedValue: WebPanelController(
            initialURL: initialURL.isEmpty ? "about:blank" : initialURL,
            userAgentMode: initialUA,
            targetWidth: targetW,
            zoomScale: initialZoom
        ))
        
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
                HStack(spacing: 6) {
                    Text(isEditing ? "Web-Widget bearbeiten" : "Neues Web-Widget")
                        .font(.title3)
                        .fontWeight(.bold)
                    InfoTooltip(text: "Konfiguriere URL, Größe und Ansicht mit interaktiver Live-Vorschau.")
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
                    VStack(alignment: .leading, spacing: 16) {
                        // 1. Name & Ziel-Webseite (URL)
                        VStack(alignment: .leading, spacing: 14) {
                            Text("1. Name & Ziel-Webseite (URL)")
                                .font(.headline)
                            
                            // Name Row
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Name des Web-Widgets:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 10) {
                                    // Live Icon Preview Badge
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                            )
                                        
                                        if useFavicon, let favicon = faviconManager.previewIcon(for: url, widgetId: originalId, selectedFaviconURL: selectedFaviconURL, removeWhite: removeWhiteBackground) {
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
                                    .help("Aktuelles Icon / Logo")
                                    
                                    TextField("z. B. Proton Kalender, Gemini, Notizen...", text: $title)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            
                            // URL Row
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Website-Adresse (URL):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 8) {
                                    TextField("https://...", text: $url, onCommit: {
                                        applyURLChange()
                                    })
                                    .textFieldStyle(.roundedBorder)
                                    
                                    Button("Laden") {
                                        applyURLChange()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            
                            // Schnellvorlagen
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Text("Schnellvorlagen:")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    InfoTooltip(text: "Klicke auf eine Vorlage, um Name, Ziel-Adresse und optimale Fenstergröße sofort zu übernehmen.")
                                }
                                
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
                                    QuickButton(name: "Google Gemini", icon: "sparkles") {
                                        setPreset(url: "https://gemini.google.com", name: "Google Gemini", icon: "sparkles", preset: .smartphone)
                                    }
                                    QuickButton(name: "Proton Calendar", icon: "calendar") {
                                        setPreset(url: "https://calendar.proton.me", name: "Proton Kalender", icon: "calendar", preset: .widget)
                                    }
                                    QuickButton(name: "Google Calendar", icon: "calendar") {
                                        setPreset(url: "https://calendar.google.com", name: "Google Kalender", icon: "calendar", preset: .widget)
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
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        // Menüleisten-Symbol & Logo (Als einklappbares Untermenü)
                        DisclosureGroup(isExpanded: $isLogoSettingsExpanded) {
                            VStack(alignment: .leading, spacing: 12) {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                // Website Logo Option
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Toggle("Website-Logo automatisch verwenden", isOn: $useFavicon)
                                            .fontWeight(.medium)
                                        InfoTooltip(text: "Verwendet das farbige Original-Logo der Website. Transparente Symbole werden bevorzugt.")
                                    }
                                    
                                    if useFavicon {
                                        // Status & Refresh
                                        HStack(spacing: 8) {
                                            if let favicon = faviconManager.previewIcon(for: url, widgetId: originalId, selectedFaviconURL: selectedFaviconURL, removeWhite: removeWhiteBackground) {
                                                Image(nsImage: favicon)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 18, height: 18)
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                                Text(selectedFaviconURL != nil ? "Ausgewähltes Logo aktiv" : "Bestes transparentes Logo aktiv")
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                                    .fontWeight(.medium)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text(url.isEmpty ? "Gib oben eine URL ein" : "Logos werden gesucht...")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if !url.isEmpty {
                                                Button(action: {
                                                    faviconManager.discoverFavicons(for: url, widgetId: originalId)
                                                }) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "arrow.clockwise")
                                                        Text("Neu scannen")
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }
                                        }
                                        .padding(8)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                                        
                                        // Discovered Favicon Options Gallery
                                        let options = faviconManager.options(for: originalId)
                                        if !options.isEmpty {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack(spacing: 5) {
                                                    Text("Verfügbare Logos (\(options.count)):")
                                                        .font(.caption2)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.primary)
                                                    InfoTooltip(text: "Gefundene Favicon- und App-Icon-Varianten. Klicke ein Logo an, um es festzulegen.")
                                                    
                                                    Spacer()
                                                    
                                                    if selectedFaviconURL != nil {
                                                        Button("Automatisch wählen") {
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
                                                                    
                                                                    if let id = originalId, let img = faviconManager.icon(forOption: opt.urlString, widgetId: id, removeWhite: removeWhiteBackground) {
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
                                                                
                                                                Text(opt.isTransparent ? "Transparent" : "Mit Hintergrund")
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
                                            Toggle("Weißer Hintergrund transparent machen", isOn: $removeWhiteBackground)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            InfoTooltip(text: "Entfernt automatisch weiße Flächen aus Logos (z. B. bei quadratischen iOS-Kacheln).")
                                        }
                                    }
                                }
                                
                                Divider()
                                    .padding(.vertical, 2)
                                
                                // Symbol Selection
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 5) {
                                        Text(useFavicon ? "Ersatz-Symbol:" : "Symbol für Menüleiste:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if useFavicon {
                                            InfoTooltip(text: "Wird in der Menüleiste angezeigt, falls die Website kein Web-Logo liefert.")
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
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.badge.checkmark")
                                    .foregroundColor(.accentColor)
                                Text("Menüleisten-Symbol & Logo anpassen")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(useFavicon ? "Automatisch" : "Symbol")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isLogoSettingsExpanded.toggle()
                                }
                            }
                            .onHover { isHovered in
                                if isHovered {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        // 2. Fenstergröße & Ansicht (Einklappbar)
                        DisclosureGroup(isExpanded: $isSizeSettingsExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Picker("Größe:", selection: $sizePreset) {
                                    ForEach(WebSizePreset.allCases) { preset in
                                        Text(preset.rawValue).tag(preset)
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
                                        Text("Breite:")
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
                                        Text("Höhe:")
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
                                        Text("Seiten-Skalierung (Zoom):")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        InfoTooltip(text: "Skaliert Webseiten herunter, damit sie im Widget optimal ohne horizontales Scrollen lesbar sind.")
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
                                    Text("Darstellung:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    InfoTooltip(text: "Mobil erzwingt ein schmales Smartphone-Layout (ideal für Widgets). Desktop lädt die Standard-Website.")
                                }
                                
                                Picker("", selection: $userAgentMode) {
                                    ForEach(WebUserAgentMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.radioGroup)
                                .onChange(of: userAgentMode) {
                                    updateLivePreview()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "aspectratio")
                                    .foregroundColor(.accentColor)
                                Text("2. Fenstergröße & Ansicht")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(effectiveWidth)) × \(Int(effectiveHeight)) pt")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSizeSettingsExpanded.toggle()
                                }
                            }
                            .onHover { isHovered in
                                if isHovered {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        // 3. Weitere Optionen (Einklappbar)
                        DisclosureGroup(isExpanded: $isExtraOptionsExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                HStack(spacing: 6) {
                                    Toggle("Fenster anheften (Pin)", isOn: $isPinned)
                                    InfoTooltip(text: "Hält das Widget-Fenster dauerhaft geöffnet, auch wenn du in eine andere App klickst oder außerhalb des Fensters tippst.")
                                }
                                
                                HStack(spacing: 6) {
                                    Toggle("Such- & Navigationsleiste anzeigen", isOn: $showsAddressBar)
                                    InfoTooltip(text: "Blendet eine Leiste mit Adress-/Suchfeld sowie Vor-, Zurück-, Neuladen- und Zoom-Buttons am unteren Rand des Widgets ein.")
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundColor(.accentColor)
                                Text("3. Weitere Optionen")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(isPinned && showsAddressBar ? "Pin & Suchleiste" : (isPinned ? "Angeheftet" : (showsAddressBar ? "Suchleiste" : "Standard")))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isExtraOptionsExpanded.toggle()
                                }
                            }
                            .onHover { isHovered in
                                if isHovered {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
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
                        Text("Live-Vorschau (\(Int(effectiveWidth)) × \(Int(effectiveHeight)) pt)")
                            .font(.headline)
                        Spacer()
                        
                        Button(action: {
                            previewController.reload()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Neu laden")
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
                        let deviceH = max(1, effectiveHeight + 28)
                        
                        ZStack {
                            // Device Frame Outline
                            VStack(spacing: 0) {
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
                                
                                // Live WebView or Placeholder when empty
                                if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "globe")
                                            .font(.system(size: 40))
                                            .foregroundColor(.secondary.opacity(0.35))
                                        Text("Noch keine Webseite geladen")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        Text("Gib links eine URL ein oder wähle eine Vorlage, um die Live-Vorschau zu starten.")
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
                Button("Abbrechen", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Änderungen speichern" : "Web-Widget erstellen") {
                    var finalURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalURL.isEmpty && !finalURL.hasPrefix("http://") && !finalURL.hasPrefix("https://") {
                        finalURL = "https://" + finalURL
                    }
                    let defaultTitle = URL(string: finalURL)?.host ?? "Web-Widget"
                    let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTitle : title
                    
                    let item = WebWidgetItem(
                        id: originalId ?? UUID(),
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
                        showsAddressBar: showsAddressBar
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
                faviconManager.discoverFavicons(for: url, widgetId: originalId)
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
            faviconManager.discoverFavicons(for: str, widgetId: originalId)
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
            faviconManager.discoverFavicons(for: newURL, widgetId: originalId)
        }
    }
    
    private func updateLivePreview() {
        var str = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty {
            str = "about:blank"
        } else if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        previewController.updateConfig(
            userAgentMode: userAgentMode,
            targetWidth: effectiveWidth,
            zoomScale: zoomScale,
            newURL: str
        )
    }
}

struct QuickButton: View {
    let name: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
        }
        .buttonStyle(.plain)
    }
}
