import SwiftUI
import WebKit

public struct WebPanelSettingsView: View {
    @ObservedObject var module: WebPanelModule
    @State private var isShowingEditor: Bool = false
    @State private var editingWidget: WebWidgetItem? = nil
    @State private var widgetToDelete: WebWidgetItem? = nil
    @State private var showingDeleteConfirm: Bool = false
    
    public init(module: WebPanelModule) {
        self.module = module
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Web-Widgets")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Web-Apps direkt als Menüleisten-Symbole mit Live-Fenster nutzen.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("Modul aktiv", isOn: $module.isEnabled)
                            .toggleStyle(.switch)
                    }
                    
                    HStack {
                        Text("\(module.widgets.count) Web-Widget(s) eingerichtet • \(module.widgets.filter { $0.isEnabled }.count) aktiv in der Menüleiste")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        Button(action: {
                            editingWidget = nil
                            isShowingEditor = true
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
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
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
                                editingWidget = nil
                                isShowingEditor = true
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
                                    editingWidget = widget
                                    isShowingEditor = true
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
                    Text("Sitzungen & Cache")
                        .font(.headline)
                    
                    Text("Cookies und Logins aller Widgets (z.B. Proton Calendar oder Google) werden dauerhaft im WebKit-Speicher gesichert.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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
            .padding(20)
        }
        .sheet(isPresented: $isShowingEditor) {
            WebWidgetEditorSheet(
                initialWidget: editingWidget,
                onSave: { savedItem in
                    if editingWidget != nil {
                        module.updateWidget(savedItem)
                    } else {
                        module.addWidget(savedItem)
                    }
                    isShowingEditor = false
                },
                onCancel: {
                    isShowingEditor = false
                }
            )
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
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {}
    }
}

// MARK: - Row View

struct WebWidgetRowView: View {
    let widget: WebWidgetItem
    let onToggleEnabled: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onOpen: () -> Void
    @ObservedObject private var faviconManager = WebFaviconManager.shared
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                
                if widget.useFavicon, let icon = faviconManager.previewIcon(for: widget.url, widgetId: widget.id) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: widget.iconName)
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(widget.title)
                        .font(.system(size: 14, weight: .semibold))
                    
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
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // Open Popover
                Button(action: onOpen) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Öffnen")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Fenster in Menüleiste öffnen")
                
                // Edit
                Button(action: onEdit) {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                        Text("Bearbeiten")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Widget bearbeiten")
                
                // Delete
                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                        Text("Löschen")
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Widget löschen")
                
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)
                
                // In Menu Bar Toggle
                Toggle("", isOn: Binding(
                    get: { widget.isEnabled },
                    set: { onToggleEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help("In Menüleiste anzeigen")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
    }
}

// MARK: - Guided Setup / Edit Wizard with Live Preview

struct WebWidgetEditorSheet: View {
    @State private var title: String
    @State private var url: String
    @State private var iconName: String
    @State private var useFavicon: Bool
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
        onSave: @escaping (WebWidgetItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isEditing = (initialWidget != nil)
        self.originalId = initialWidget?.id
        
        let initialTitle = initialWidget?.title ?? "Mein Kalender"
        let initialURL = initialWidget?.url ?? "https://calendar.proton.me"
        let initialIcon = initialWidget?.iconName ?? "calendar"
        let initialUseFavicon = initialWidget?.useFavicon ?? true
        let initialPreset = initialWidget?.sizePreset ?? .widget
        let initialW = initialWidget?.customWidth ?? 320
        let initialH = initialWidget?.customHeight ?? 400
        let initialUA = initialWidget?.userAgentMode ?? .auto
        let initialZoom = initialWidget?.zoomScale ?? (initialPreset == .widget ? 0.85 : 1.0)
        let initialEnabled = initialWidget?.isEnabled ?? true
        let initialPinned = initialWidget?.isPinned ?? false
        let initialBar = initialWidget?.showsAddressBar ?? false
        
        _title = State(initialValue: initialTitle)
        _url = State(initialValue: initialURL)
        _iconName = State(initialValue: initialIcon)
        _useFavicon = State(initialValue: initialUseFavicon)
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
            initialURL: initialURL,
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Web-Widget bearbeiten" : "Neues Web-Widget einrichten")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Konfiguriere URL, Größe und Smartphone-Darstellung mit Live-Vorschau.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Abbrechen", action: onCancel)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Main Content: Split into Settings (Left) and Live-Preview (Right)
            HStack(spacing: 0) {
                // Left Column: Configuration Forms
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 1. Name & Menüleisten-Symbol
                        VStack(alignment: .leading, spacing: 12) {
                            Text("1. Name & Menüleisten-Symbol")
                                .font(.headline)
                            
                            HStack(spacing: 12) {
                                // Live Icon Preview
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                        )
                                    
                                    if useFavicon, let favicon = faviconManager.previewIcon(for: url, widgetId: originalId) {
                                        Image(nsImage: favicon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 22, height: 22)
                                            .clipShape(RoundedRectangle(cornerRadius: 3.5))
                                    } else {
                                        Image(systemName: iconName)
                                            .font(.system(size: 18))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                
                                TextField("Widget-Name (z.B. Proton Kalender)", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Divider()
                            
                            // Website Logo Option
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle("Website-Logo automatisch verwenden", isOn: $useFavicon)
                                    .fontWeight(.medium)
                                
                                Text("Verwendet das farbige Original-Logo der Website für die Menüleiste. Falls nicht verfügbar oder offline, wird das unten gewählte Symbol verwendet.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if useFavicon {
                                    HStack(spacing: 8) {
                                        if let favicon = faviconManager.previewIcon(for: url, widgetId: originalId) {
                                            Image(nsImage: favicon)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 18, height: 18)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                            Text("Website-Logo aktiv")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                                .fontWeight(.medium)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text("Logo wird geladen...")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            faviconManager.fetchFavicon(for: url, widgetId: originalId)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.clockwise")
                                                Text("Neu laden")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                                }
                            }
                            
                            Divider()
                            
                            // Symbol Selection
                            VStack(alignment: .leading, spacing: 6) {
                                Text(useFavicon ? "Ersatz-Symbol auswählen (falls kein Logo verfügbar):" : "Symbol für die Menüleiste auswählen:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
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
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        // 2. Ziel-URL
                        VStack(alignment: .leading, spacing: 10) {
                            Text("2. Ziel-Webseite (URL)")
                                .font(.headline)
                            
                            HStack {
                                TextField("https://...", text: $url, onCommit: {
                                    applyURLChange()
                                })
                                .textFieldStyle(.roundedBorder)
                                
                                Button("Laden") {
                                    applyURLChange()
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            Text("Schnellvorlagen:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
                                QuickButton(name: "Proton Calendar", icon: "calendar") {
                                    setPreset(url: "https://calendar.proton.me", name: "Proton Kalender", icon: "calendar", preset: .widget)
                                }
                                QuickButton(name: "Google Calendar", icon: "calendar") {
                                    setPreset(url: "https://calendar.google.com", name: "Google Kalender", icon: "calendar", preset: .widget)
                                }
                                QuickButton(name: "Notion", icon: "note.text") {
                                    setPreset(url: "https://www.notion.so", name: "Notion", icon: "note.text", preset: .iphone8)
                                }
                                QuickButton(name: "ChatGPT", icon: "bubble.left.and.bubble.right") {
                                    setPreset(url: "https://chatgpt.com", name: "ChatGPT", icon: "bubble.left.and.bubble.right", preset: .iphone14)
                                }
                                QuickButton(name: "Todoist", icon: "checklist") {
                                    setPreset(url: "https://app.todoist.com", name: "Todoist", icon: "checklist", preset: .iphoneSE)
                                }
                                QuickButton(name: "GitHub", icon: "chevron.left.forwardslash.chevron.right") {
                                    setPreset(url: "https://github.com", name: "GitHub", icon: "chevron.left.forwardslash.chevron.right", preset: .iphone14)
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        // 3. Fenstergröße & User-Agent
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("3. Fenstergröße & Ansicht")
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(effectiveWidth)) × \(Int(effectiveHeight)) pt")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                            }
                            
                            Picker("Vorlage:", selection: $sizePreset) {
                                ForEach(WebSizePreset.allCases) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: sizePreset) {
                                if sizePreset == .widget && (zoomScale == 1.0 || zoomScale == 0) {
                                    zoomScale = 0.85
                                }
                                updateLivePreview()
                            }
                            
                            if sizePreset == .custom {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Breite:")
                                        Spacer()
                                        Text("\(Int(customWidth)) pt").monospacedDigit()
                                    }
                                    Slider(value: $customWidth, in: 280...1200, step: 10) { _ in
                                        updateLivePreview()
                                    }
                                    
                                    HStack {
                                        Text("Höhe:")
                                        Spacer()
                                        Text("\(Int(customHeight)) pt").monospacedDigit()
                                    }
                                    Slider(value: $customHeight, in: 300...1000, step: 10) { _ in
                                        updateLivePreview()
                                    }
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Seiten-Skalierung (Zoom):")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(Int(zoomScale * 100))%").monospacedDigit()
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.bold)
                                }
                                Slider(value: $zoomScale, in: 0.5...1.5, step: 0.05) { _ in
                                    updateLivePreview()
                                }
                                Text("Skaliert Webseiten herunter, damit sie im Widget optimal ohne horizontales Scrollen lesbar sind.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            Text("Darstellung (Mobil / Desktop):")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
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
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        // 4. Optionen
                        VStack(alignment: .leading, spacing: 8) {
                            Text("4. Optionen")
                                .font(.headline)
                            
                            Toggle("In Menüleiste anzeigen", isOn: $isEnabled)
                            Toggle("Adressleiste standardmäßig einblenden", isOn: $showsAddressBar)
                            Toggle("Fenster anheften (Pin)", isOn: $isPinned)
                        }
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
                                    Text(title.isEmpty ? url : title)
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
                                
                                // Live WebView
                                WebViewRepresentable(controller: previewController)
                                    .frame(width: effectiveWidth, height: effectiveHeight)
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
                Spacer()
                Button(isEditing ? "Änderungen speichern" : "Web-Widget erstellen") {
                    let item = WebWidgetItem(
                        id: originalId ?? UUID(),
                        title: title.isEmpty ? "Web-Widget" : title,
                        url: url.isEmpty ? "https://calendar.proton.me" : url,
                        iconName: iconName,
                        useFavicon: useFavicon,
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 880, idealWidth: 920, maxWidth: 1050, minHeight: 620, idealHeight: 660, maxHeight: 720)
        .onAppear {
            updateLivePreview()
            if useFavicon {
                faviconManager.fetchFavicon(for: url, widgetId: originalId)
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
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        url = str
        updateLivePreview()
        if useFavicon {
            faviconManager.fetchFavicon(for: str, widgetId: originalId)
        }
    }
    
    private func setPreset(url newURL: String, name: String, icon: String, preset: WebSizePreset) {
        self.url = newURL
        self.title = name
        self.iconName = icon
        self.sizePreset = preset
        if preset == .widget {
            self.zoomScale = 0.85
        }
        updateLivePreview()
        if useFavicon {
            faviconManager.fetchFavicon(for: newURL, widgetId: originalId)
        }
    }
    
    private func updateLivePreview() {
        var str = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
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
