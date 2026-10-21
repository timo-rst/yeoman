import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "Allgemein"
    case menuBar = "Menüleiste"
    case webPanel = "Web-Widget (MenuBarX)"
    case clipboard = "Zwischenablage (Clippy)"
    case systemStats = "System-Stats & Tasks"
    case about = "Über MacCustomizer"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .webPanel: return "calendar"
        case .clipboard: return "doc.on.clipboard"
        case .systemStats: return "gauge.with.needle"
        case .about: return "info.circle"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var moduleManager = ModuleManager.shared
    @State private var selectedTab: SettingsTab = .menuBar
    
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
            switch selectedTab {
            case .general:
                GeneralSettingsView()
            case .menuBar:
                moduleManager.menuBarModule.settingsView()
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
                    
                    ModuleToggleRow(
                        title: "Menüleisten-Optimizer",
                        subtitle: "Icon-Abstand und Multi-Display-Management",
                        icon: "menubar.rectangle",
                        isOn: Binding(
                            get: { ModuleManager.shared.menuBarModule.isEnabled },
                            set: { ModuleManager.shared.toggleModule(id: ModuleManager.shared.menuBarModule.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { ModuleManager.shared.menuBarModule.showsDedicatedStatusItem },
                            set: { ModuleManager.shared.menuBarModule.showsDedicatedStatusItem = $0 }
                        )
                    )
                    
                    Divider()
                    
                    ModuleToggleRow(
                        title: "Web-Widget (MenuBarX)",
                        subtitle: "Eingebettete Web-App (z.B. Proton Calendar, Notion, ChatGPT)",
                        icon: "calendar",
                        isOn: Binding(
                            get: { ModuleManager.shared.webPanelModule.isEnabled },
                            set: { ModuleManager.shared.toggleModule(id: ModuleManager.shared.webPanelModule.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { ModuleManager.shared.webPanelModule.showsDedicatedStatusItem },
                            set: { ModuleManager.shared.webPanelModule.showsDedicatedStatusItem = $0 }
                        )
                    )
                    
                    Divider()
                    
                    ModuleToggleRow(
                        title: "Clipboard Manager (Clippy)",
                        subtitle: "Zwischenablage-Historie mit Suche und Filter",
                        icon: "doc.on.clipboard",
                        isOn: Binding(
                            get: { ModuleManager.shared.clipboardModule.isEnabled },
                            set: { ModuleManager.shared.toggleModule(id: ModuleManager.shared.clipboardModule.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { ModuleManager.shared.clipboardModule.showsDedicatedStatusItem },
                            set: { ModuleManager.shared.clipboardModule.showsDedicatedStatusItem = $0 }
                        )
                    )
                    
                    Divider()
                    
                    ModuleToggleRow(
                        title: "System Stats Monitor",
                        subtitle: "CPU-, GPU- und RAM-Graphen",
                        icon: "gauge.with.needle",
                        isOn: Binding(
                            get: { ModuleManager.shared.systemStatsModule.isEnabled },
                            set: { ModuleManager.shared.toggleModule(id: ModuleManager.shared.systemStatsModule.id, enabled: $0) }
                        ),
                        showsDedicatedIcon: Binding(
                            get: { ModuleManager.shared.systemStatsModule.showsDedicatedStatusItem },
                            set: { ModuleManager.shared.systemStatsModule.showsDedicatedStatusItem = $0 }
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

struct ModuleToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    var showsDedicatedIcon: Binding<Bool>? = nil
    
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
