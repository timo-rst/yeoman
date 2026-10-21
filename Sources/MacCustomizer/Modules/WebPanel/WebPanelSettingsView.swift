import SwiftUI
import WebKit

public struct WebPanelSettingsView: View {
    @ObservedObject var module: WebPanelModule
    @State private var urlInput: String = ""
    @State private var showingResetAlert: Bool = false
    
    public init(module: WebPanelModule) {
        self.module = module
        _urlInput = State(initialValue: module.targetURL)
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Web-Widget (MenuBarX-Modul)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Binde Web-Apps wie Proton Calendar, Notion oder ChatGPT als schlankes Popover direkt in die Menüleiste ein.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("Modul aktiv", isOn: $module.isEnabled)
                            .toggleStyle(.switch)
                    }
                }
                
                Divider()
                
                // Ziel-URL & Vorlagen
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ziel-Webseite (URL)")
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                        
                        TextField("https://calendar.proton.me", text: $urlInput, onCommit: {
                            applyURL()
                        })
                        .textFieldStyle(.roundedBorder)
                        
                        Button("Übernehmen") {
                            applyURL()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    
                    Text("Beliebte Schnellvorlagen:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                        QuickURLButton(title: "Proton Calendar", icon: "calendar", url: "https://calendar.proton.me") {
                            selectURL("https://calendar.proton.me", icon: "calendar")
                        }
                        QuickURLButton(title: "Google Calendar", icon: "calendar", url: "https://calendar.google.com") {
                            selectURL("https://calendar.google.com", icon: "calendar")
                        }
                        QuickURLButton(title: "Notion", icon: "note.text", url: "https://www.notion.so") {
                            selectURL("https://www.notion.so", icon: "note.text")
                        }
                        QuickURLButton(title: "ChatGPT", icon: "bubble.left.and.bubble.right", url: "https://chatgpt.com") {
                            selectURL("https://chatgpt.com", icon: "bubble.left.and.bubble.right")
                        }
                        QuickURLButton(title: "Todoist", icon: "checklist", url: "https://app.todoist.com") {
                            selectURL("https://app.todoist.com", icon: "checklist")
                        }
                        QuickURLButton(title: "GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com") {
                            selectURL("https://github.com", icon: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Fenstergröße (Größen-Vorlagen)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Fenstergröße & Display-Format")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(module.panelWidth)) × \(Int(module.panelHeight)) pt")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundColor(.accentColor)
                    }
                    
                    Picker("Vorlage wählen:", selection: $module.sizePreset) {
                        ForEach(WebSizePreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Divider()
                    
                    // Sliders for custom fine-tuning
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Breite:")
                            Spacer()
                            Text("\(Int(module.panelWidth)) pt").monospacedDigit()
                        }
                        Slider(value: $module.panelWidth, in: 280...1200, step: 10) { _ in
                            module.sizePreset = .custom
                        }
                        
                        HStack {
                            Text("Höhe:")
                            Spacer()
                            Text("\(Int(module.panelHeight)) pt").monospacedDigit()
                        }
                        Slider(value: $module.panelHeight, in: 300...1000, step: 10) { _ in
                            module.sizePreset = .custom
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Smartphone / User Agent Modus
                VStack(alignment: .leading, spacing: 14) {
                    Text("Darstellungsmodus & User-Agent")
                        .font(.headline)
                    
                    Text("Damit Webseiten wie dein Kalender bei kompakten Breiten automatisch die optimale Smartphone-App-Ansicht darstellen:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("User-Agent:", selection: $module.userAgentMode) {
                        ForEach(WebUserAgentMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    
                    Text(userAgentExplanation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Menüleisten-Symbol & Optionen
                VStack(alignment: .leading, spacing: 14) {
                    Text("Menüleisten-Symbol")
                        .font(.headline)
                    
                    Toggle("Eigenes Symbol in der Menüleiste anzeigen", isOn: $module.showsDedicatedStatusItem)
                    
                    HStack(spacing: 12) {
                        Text("Symbol-Icon:")
                            .font(.subheadline)
                        
                        HStack(spacing: 8) {
                            IconChoiceButton(icon: "calendar", current: module.statusIconName) { module.statusIconName = "calendar" }
                            IconChoiceButton(icon: "calendar.badge.clock", current: module.statusIconName) { module.statusIconName = "calendar.badge.clock" }
                            IconChoiceButton(icon: "globe", current: module.statusIconName) { module.statusIconName = "globe" }
                            IconChoiceButton(icon: "safari", current: module.statusIconName) { module.statusIconName = "safari" }
                            IconChoiceButton(icon: "note.text", current: module.statusIconName) { module.statusIconName = "note.text" }
                            IconChoiceButton(icon: "bubble.left.and.bubble.right", current: module.statusIconName) { module.statusIconName = "bubble.left.and.bubble.right" }
                            IconChoiceButton(icon: "checklist", current: module.statusIconName) { module.statusIconName = "checklist" }
                        }
                    }
                    
                    Divider()
                    
                    Toggle("Adressleiste standardmäßig im Fenster einblenden", isOn: $module.showsAddressBar)
                    Toggle("Fenster angeheftet halten (bleibt offen beim Klick auf andere Apps)", isOn: $module.isPinned)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Cache & Login Daten
                VStack(alignment: .leading, spacing: 10) {
                    Text("Webseite-Daten & Cache")
                        .font(.headline)
                    
                    Text("Login-Cookies und lokale Sitzungen (z.B. für Proton Calendar) werden sicher im macOS WebKit-Speicher gesichert.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Cache & Website-Daten löschen") {
                        clearWebsiteData()
                    }
                    .foregroundColor(.red)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(20)
        }
    }
    
    private var userAgentExplanation: String {
        switch module.userAgentMode {
        case .auto:
            return "💡 Bei Fenstern bis 480pt Breite wird automatisch der iPhone-Header gesendet, damit responsive Web-Apps direkt die Smartphone-Ansicht laden."
        case .mobile:
            return "📱 Sendet immer den iPhone Safari User-Agent, wodurch alle Seiten als Touch-/Mobile-Web-App gerendert werden."
        case .desktop:
            return "💻 Sendet den regulären macOS Safari User-Agent."
        }
    }
    
    private func applyURL() {
        var str = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        urlInput = str
        module.targetURL = str
    }
    
    private func selectURL(_ url: String, icon: String) {
        urlInput = url
        module.targetURL = url
        module.statusIconName = icon
    }
    
    private func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
            module.controller.reload()
        }
    }
}

struct QuickURLButton: View {
    let title: String
    let icon: String
    let url: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
        }
        .buttonStyle(.plain)
    }
}

struct IconChoiceButton: View {
    let icon: String
    let current: String
    let action: () -> Void
    
    var isSelected: Bool { icon == current }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                )
        }
        .buttonStyle(.plain)
    }
}
