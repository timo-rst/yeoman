import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "Allgemein"
    case menuBar = "Menüleiste"
    case scrollReverser = "Scroll-Richtung"
    case webPanel = "Web-Widgets"
    case clipboard = "Zwischenablage"
    case systemStats = "System-Monitor"
    case about = "Über MacCustomizer"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .scrollReverser: return "computermouse"
        case .webPanel: return "globe"
        case .clipboard: return "doc.on.clipboard"
        case .systemStats: return "gauge.with.needle"
        case .about: return "info.circle"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var moduleManager = ModuleManager.shared
    @State private var selectedTab: SettingsTab? = .menuBar
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                HStack(spacing: 8) {
                    Image(systemName: tab.iconName)
                        .frame(width: 18)
                        .foregroundColor(.accentColor)
                    Text(tab.rawValue)
                    Spacer()
                    
                    if tab == .menuBar && moduleManager.menuBarModule.isEnabled {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    } else if tab == .scrollReverser && moduleManager.scrollReverserModule.isEnabled {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    } else if tab == .webPanel && moduleManager.webPanelModule.isEnabled {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    } else if tab == .clipboard && moduleManager.clipboardModule.isEnabled {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    } else if tab == .systemStats && moduleManager.systemStatsModule.isEnabled {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    }
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            switch selectedTab ?? .menuBar {
            case .general:
                GeneralSettingsView()
            case .menuBar:
                moduleManager.menuBarModule.settingsView()
            case .scrollReverser:
                moduleManager.scrollReverserModule.settingsView()
            case .webPanel:
                moduleManager.webPanelModule.settingsView()
            case .clipboard:
                moduleManager.clipboardModule.settingsView()
            case .systemStats:
                moduleManager.systemStatsModule.settingsView()
            case .about:
                AboutView()
            }
        }
        .frame(minWidth: 880, minHeight: 600)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showMainStatusItem") private var showMainStatusItem = true
    
    @ObservedObject private var mm = ModuleManager.shared
    @ObservedObject private var webPanel = ModuleManager.shared.webPanelModule
    @ObservedObject private var clipboard = ModuleManager.shared.clipboardModule
    @ObservedObject private var stats = ModuleManager.shared.systemStatsModule
    @ObservedObject private var scrollReverser = ModuleManager.shared.scrollReverserModule
    @ObservedObject private var menuBar = ModuleManager.shared.menuBarModule
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allgemeine Einstellungen")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Grundkonfiguration für Startverhalten und Systemintegration.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 14) {
                    Text("Start & Darstellung")
                        .font(.headline)
                    
                    Toggle("Beim Mac-Start automatisch öffnen (Launch at Login)", isOn: $launchAtLogin)
                    
                    Toggle("Dock-Symbol anzeigen", isOn: Binding(
                        get: { showDockIcon },
                        set: {
                            showDockIcon = $0
                            NSApp.setActivationPolicy($0 ? .regular : .accessory)
                        }
                    ))
                    
                    Toggle("Haupt-Icon (MacCustomizer Launcher) in der Menüleiste anzeigen", isOn: Binding(
                        get: { showMainStatusItem },
                        set: {
                            showMainStatusItem = $0
                            StatusItemController.shared.showsMainStatusItem = $0
                        }
                    ))
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                VStack(alignment: .leading, spacing: 14) {
                    Text("Aktive Module & Menüleisten-Symbole")
                        .font(.headline)
                    
                    // 1. Menüleisten-Optimizer
                    ModuleToggleRow(
                        title: "Menüleisten-Optimizer",
                        subtitle: "Icon-Abstand und Multi-Display-Management",
                        icon: "menubar.rectangle",
                        isOn: Binding(
                            get: { menuBar.isEnabled },
                            set: { mm.toggleModule(id: menuBar.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { menuBar.showsDedicatedStatusItem },
                            set: { menuBar.showsDedicatedStatusItem = $0 }
                        )
                    )
                    
                    Divider()
                    
                    // 2. Scroll Reverser
                    ModuleToggleRow(
                        title: "Scroll-Richtung (Maus)",
                        subtitle: "Kehrt die Scrollrichtung der Maus um, während das Trackpad unverändert bleibt",
                        icon: "computermouse",
                        isOn: Binding(
                            get: { scrollReverser.isEnabled },
                            set: { mm.toggleModule(id: scrollReverser.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { scrollReverser.showsDedicatedStatusItem },
                            set: { scrollReverser.showsDedicatedStatusItem = $0 }
                        )
                    )
                    
                    Divider()
                    
                    // 3. Web-Widgets
                    ModuleToggleRow(
                        title: "Web-Widgets",
                        subtitle: "Web-Apps (z.B. Kalender oder Notizen) direkt in der Menüleiste öffnen",
                        icon: "globe",
                        isOn: Binding(
                            get: { webPanel.isEnabled },
                            set: { mm.toggleModule(id: webPanel.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { webPanel.showsDedicatedStatusItem },
                            set: { webPanel.showsDedicatedStatusItem = $0 }
                        ),
                        extraContent: {
                            if webPanel.isEnabled && webPanel.showsDedicatedStatusItem && !webPanel.widgets.isEmpty {
                                VStack(spacing: 6) {
                                    ForEach(webPanel.widgets) { widget in
                                        HStack(spacing: 8) {
                                            Spacer().frame(width: 44)
                                            Image(systemName: widget.iconName.isEmpty ? "globe" : widget.iconName)
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                                .frame(width: 14)
                                            Text(widget.title)
                                                .font(.caption)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Toggle("", isOn: Binding(
                                                get: { widget.isEnabled },
                                                set: { enabled in
                                                    webPanel.toggleWidget(id: widget.id, isEnabled: enabled)
                                                }
                                            ))
                                            .toggleStyle(.switch)
                                            .scaleEffect(0.75)
                                        }
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 8)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                                    }
                                }
                                .padding(.leading, 8)
                                .padding(.top, 4)
                            }
                        }
                    )
                    
                    Divider()
                    
                    // 4. Clipboard Manager
                    ModuleToggleRow(
                        title: "Zwischenablage-Manager",
                        subtitle: "Verlauf kopierter Texte, Links und Bilder mit Suchfunktion",
                        icon: "doc.on.clipboard",
                        isOn: Binding(
                            get: { clipboard.isEnabled },
                            set: { mm.toggleModule(id: clipboard.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { clipboard.showsDedicatedStatusItem },
                            set: { clipboard.showsDedicatedStatusItem = $0 }
                        )
                    )
                    
                    Divider()
                    
                    // 5. System Stats Monitor
                    ModuleToggleRow(
                        title: "System-Monitor",
                        subtitle: "Live-Auslastung von Prozessor, Arbeitsspeicher und Grafik",
                        icon: "gauge.with.needle",
                        isOn: Binding(
                            get: { stats.isEnabled },
                            set: { mm.toggleModule(id: stats.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { stats.showsDedicatedStatusItem },
                            set: { stats.showsDedicatedStatusItem = $0 }
                        )
                    )
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(20)
        }
    }
}

struct ModuleToggleRow<ExtraContent: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    var showsDedicatedIcon: Binding<Bool>? = nil
    var extraContent: ExtraContent
    
    init(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>,
        showsDedicatedIcon: Binding<Bool>? = nil,
        @ViewBuilder extraContent: () -> ExtraContent = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self._isOn = isOn
        self.showsDedicatedIcon = showsDedicatedIcon
        self.extraContent = extraContent()
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
            }
            
            if isOn, let dedicatedBinding = showsDedicatedIcon {
                HStack {
                    Spacer().frame(width: 40)
                    Image(systemName: "menubar.arrow.up.rectangle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Eigenes Symbol in der Menüleiste:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: dedicatedBinding)
                        .toggleStyle(.switch)
                        .scaleEffect(0.85)
                }
                
                extraContent
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("MacCustomizer")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 0.2.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Die modulare All-in-One Steuerzentrale für deine macOS Anpassungen.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Divider().frame(width: 280)
            
            VStack(spacing: 4) {
                Text("Entwickelt für macOS mit Swift & SwiftUI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Modulares Icon- und Menüleistensystem")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
