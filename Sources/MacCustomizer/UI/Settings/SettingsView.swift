import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "general"
    case menuBar = "menuBar"
    case scrollReverser = "scrollReverser"
    case webPanel = "webPanel"
    case clipboard = "clipboard"
    case systemStats = "systemStats"
    case about = "about"
    
    public var id: String { rawValue }
    
    public var localizationKey: String {
        switch self {
        case .general: return "tab.general"
        case .menuBar: return "tab.menuBar"
        case .scrollReverser: return "tab.scrollReverser"
        case .webPanel: return "tab.webPanel"
        case .clipboard: return "tab.clipboard"
        case .systemStats: return "tab.systemStats"
        case .about: return "tab.about"
        }
    }
    
    public var title: String {
        LocalizationManager.shared.localized(localizationKey)
    }
    
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
    @ObservedObject var l10n = LocalizationManager.shared
    @State private var selectedTab: SettingsTab = .general
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Static sidebar that stays open without jumping toggle buttons
            VStack(spacing: 0) {
                List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                    HStack(spacing: 8) {
                        Image(systemName: tab.iconName)
                            .frame(width: 18)
                            .foregroundColor(.accentColor)
                        Text(tab.title)
                    }
                    .tag(tab)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 220)
            
            Divider()
            
            // Detail Area
            Group {
                switch selectedTab {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, idealWidth: 1040, minHeight: 660, idealHeight: 720)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showMainStatusItem") private var showMainStatusItem = true
    
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var mm = ModuleManager.shared
    @ObservedObject private var webPanel = ModuleManager.shared.webPanelModule
    @ObservedObject private var clipboard = ModuleManager.shared.clipboardModule
    @ObservedObject private var stats = ModuleManager.shared.systemStatsModule
    @ObservedObject private var scrollReverser = ModuleManager.shared.scrollReverserModule
    @ObservedObject private var menuBar = ModuleManager.shared.menuBarModule
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.localized("general.title"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(l10n.localized("general.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Startup & Appearance Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n.localized("general.startup_appearance"))
                            .font(.headline)
                        
                        HStack(spacing: 6) {
                            Toggle(l10n.localized("general.launch_at_login"), isOn: $launchAtLogin)
                            InfoTooltip(text: l10n.localized("general.launch_at_login_tooltip"))
                        }
                        
                        HStack(spacing: 6) {
                            Toggle(l10n.localized("general.show_dock_icon"), isOn: Binding(
                                get: { showDockIcon },
                                set: {
                                    showDockIcon = $0
                                    StatusItemController.shared.setDockIconVisible($0)
                                }
                            ))
                            InfoTooltip(text: l10n.localized("general.show_dock_icon_tooltip"))
                        }
                        
                        HStack(spacing: 6) {
                            Toggle(l10n.localized("general.show_main_status_item"), isOn: Binding(
                                get: { showMainStatusItem },
                                set: {
                                    showMainStatusItem = $0
                                    StatusItemController.shared.showsMainStatusItem = $0
                                }
                            ))
                            InfoTooltip(text: l10n.localized("general.show_main_status_item_tooltip"))
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    
                    // Software-Updates
                    UpdateSettingsSection(isDetailedView: false)
                    
                    // Active Modules Section
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n.localized("general.active_modules"))
                            .font(.headline)
                        
                        // 1. Menüleisten-Optimizer
                        ModuleToggleRow(
                            title: l10n.localized("general.menu_bar_opt_title"),
                            subtitle: l10n.localized("general.menu_bar_opt_sub"),
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
                            title: l10n.localized("general.scroll_reverser_title"),
                            subtitle: l10n.localized("general.scroll_reverser_sub"),
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
                            title: l10n.localized("general.web_panel_title"),
                            subtitle: l10n.localized("general.web_panel_sub"),
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
                            title: l10n.localized("general.clipboard_title"),
                            subtitle: l10n.localized("general.clipboard_sub"),
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
                            title: l10n.localized("general.system_stats_title"),
                            subtitle: l10n.localized("general.system_stats_sub"),
                            icon: "gauge.with.needle",
                            isOn: Binding(
                                get: { stats.isEnabled },
                                set: { mm.toggleModule(id: stats.id, enabled: $0) }
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
                
                HStack(spacing: 10) {
                    Text(isOn ? l10n("common.enabled") : l10n("common.disabled"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isOn ? .primary : .secondary)
                    
                    Toggle("", isOn: $isOn)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            
            if isOn, let dedicatedBinding = showsDedicatedIcon {
                HStack {
                    Spacer().frame(width: 40)
                    Image(systemName: "menubar.arrow.up.rectangle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(l10n("general.status_icon_label"))
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

struct LanguageSettingsCard: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var hoveredLang: AppLanguage? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text(l10n.localized("about.language_title"))
                    .font(.headline)
                
                Spacer()
                
                // Status Badge showing current active language
                HStack(spacing: 5) {
                    FlatFlagView(language: l10n.effectiveLanguage, size: CGSize(width: 14, height: 10))
                    Text(l10n.selectedLanguage == .system ? l10n.localized("lang.system") : l10n.selectedLanguage.nativeName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
            
            Divider()
            
            // Subtitle / Info
            Text(l10n.localized("about.language_subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // System Default Option (Top-Tier Card)
            let isSystemSelected = l10n.selectedLanguage == .system
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    l10n.selectedLanguage = .system
                }
            }) {
                HStack(spacing: 12) {
                    FlatFlagView(language: .system, size: CGSize(width: 26, height: 18))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(l10n.localized("lang.system"))
                                .font(.subheadline)
                                .fontWeight(isSystemSelected ? .semibold : .medium)
                                .foregroundColor(.primary)
                            
                            // Badge indicating the detected macOS language
                            Text("macOS: \(l10n.systemLanguage.displayName(in: l10n.effectiveLanguage))")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isSystemSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                                )
                                .foregroundColor(isSystemSelected ? .accentColor : .secondary)
                        }
                        
                        Text(l10n.localized("about.lang_system_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if isSystemSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.accentColor)
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSystemSelected ? Color.accentColor.opacity(0.12) : (hoveredLang == .system ? Color.primary.opacity(0.05) : Color(nsColor: .windowBackgroundColor)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSystemSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSystemSelected ? 1.5 : 1.0)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                hoveredLang = isHovered ? .system : nil
            }
            
            // Bottom Tier: 4 Languages Grid
            let languages: [AppLanguage] = [.german, .english, .spanish, .french]
            HStack(spacing: 10) {
                ForEach(languages) { lang in
                    let isSelected = l10n.selectedLanguage == lang
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            l10n.selectedLanguage = lang
                        }
                    }) {
                        VStack(spacing: 8) {
                            HStack {
                                FlatFlagView(language: lang, size: CGSize(width: 24, height: 16))
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.accentColor)
                                } else {
                                    Text(lang.code)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                            }
                            
                            HStack {
                                Text(lang.displayName(in: lang))
                                    .font(.subheadline)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : (hoveredLang == lang ? Color.primary.opacity(0.05) : Color(nsColor: .windowBackgroundColor)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1.0)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        hoveredLang = isHovered ? lang : nil
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct AboutView: View {
    @ObservedObject var updater = UpdateManager.shared
    @ObservedObject var l10nObj = LocalizationManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Branding Header
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                        .padding(.top, 10)
                    
                    Text("MacCustomizer")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Version \(updater.currentVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(l10n("about.tagline"))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 440)
                }
                
                // Language Selection Card
                LanguageSettingsCard()
                    .frame(maxWidth: 600)
                
                // Updates Section
                UpdateSettingsSection(isDetailedView: true)
                    .frame(maxWidth: 600)
                
                // GitHub & Support Links
                HStack(spacing: 16) {
                    Button(action: {
                        if let url = URL(string: "https://github.com/timo-rst/mac_customizer") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text(l10n("about.github_repo"))
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        if let url = URL(string: "https://github.com/timo-rst/mac_customizer/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "tag")
                            Text(l10n("about.releases_changelog"))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                VStack(spacing: 4) {
                    Text(l10n("about.developed_for"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Copyright © 2026 Timo Richstein. All rights reserved.")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
    }
}
