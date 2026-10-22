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
    @ObservedObject private var menuBar = ModuleManager.shared.menuBarModule
    @ObservedObject private var clipboard = ModuleManager.shared.clipboardModule
    @State private var selectedTab: SettingsTab = .general
    @State private var isMenuBarExpanded: Bool = false
    @State private var isClipboardExpanded: Bool = false
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Static sidebar that stays open without jumping toggle buttons
            VStack(spacing: 0) {
                List(selection: $selectedTab) {
                    // 1. General
                    SidebarStandardRow(icon: "gearshape", title: l10n.localized("tab.general"), isSelected: selectedTab == .general)
                        .tag(SettingsTab.general)
                    
                    // 2. Menüleiste Group
                    SidebarParentRow(
                        icon: "menubar.rectangle",
                        title: l10n.localized("tab.menuBar"),
                        isExpanded: isMenuBarExpanded,
                        isSelected: selectedTab == .menuBar,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isMenuBarExpanded.toggle()
                            }
                        }
                    )
                    .tag(SettingsTab.menuBar)
                    
                    if isMenuBarExpanded {
                        SidebarSubItemRow(
                            icon: "list.bullet.rectangle",
                            title: l10n.localized("menubar.tab_items"),
                            isActive: menuBar.activeSubTab == .items
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                menuBar.activeSubTab = .items
                            }
                        }
                        
                        SidebarSubItemRow(
                            icon: "arrow.left.and.line.vertical.and.arrow.right",
                            title: l10n.localized("menubar.tab_spacing"),
                            isActive: menuBar.activeSubTab == .spacing
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                menuBar.activeSubTab = .spacing
                            }
                        }
                    }
                    
                    // 3. Scroll Reverser
                    SidebarStandardRow(icon: "computermouse", title: l10n.localized("tab.scrollReverser"), isSelected: selectedTab == .scrollReverser)
                        .tag(SettingsTab.scrollReverser)
                    
                    // 4. Web Panel
                    SidebarStandardRow(icon: "globe", title: l10n.localized("tab.webPanel"), isSelected: selectedTab == .webPanel)
                        .tag(SettingsTab.webPanel)
                    
                    // 5. Clipboard Group
                    SidebarParentRow(
                        icon: "doc.on.clipboard",
                        title: l10n.localized("tab.clipboard"),
                        isExpanded: isClipboardExpanded,
                        isSelected: selectedTab == .clipboard,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isClipboardExpanded.toggle()
                            }
                        }
                    )
                    .tag(SettingsTab.clipboard)
                    
                    if isClipboardExpanded {
                        SidebarSubItemRow(
                            icon: "clock.arrow.circlepath",
                            title: l10n.localized("clipboard.subtab_history"),
                            isActive: clipboard.activeSubTab == .history
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                clipboard.activeSubTab = .history
                            }
                        }
                        
                        SidebarSubItemRow(
                            icon: "slider.horizontal.3",
                            title: l10n.localized("clipboard.subtab_options"),
                            isActive: clipboard.activeSubTab == .options
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                clipboard.activeSubTab = .options
                            }
                        }
                    }
                    
                    // 6. System Stats
                    SidebarStandardRow(icon: "gauge.with.needle", title: l10n.localized("tab.systemStats"), isSelected: selectedTab == .systemStats)
                        .tag(SettingsTab.systemStats)
                    
                    // 7. About
                    SidebarStandardRow(icon: "info.circle", title: l10n.localized("tab.about"), isSelected: selectedTab == .about)
                        .tag(SettingsTab.about)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 230)
            
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
        .onChange(of: selectedTab) { _, newTab in
            withAnimation(.easeInOut(duration: 0.18)) {
                if newTab == .menuBar {
                    isMenuBarExpanded = true
                    isClipboardExpanded = false
                } else if newTab == .clipboard {
                    isClipboardExpanded = true
                    isMenuBarExpanded = false
                } else {
                    isMenuBarExpanded = false
                    isClipboardExpanded = false
                }
            }
        }
    }
}

struct SidebarStandardRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundColor(isSelected ? .white : .accentColor)
            Text(title)
                .foregroundColor(isSelected ? .white : .primary)
        }
    }
}

struct SidebarParentRow: View {
    let icon: String
    let title: String
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpand: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundColor(isSelected ? .white : .accentColor)
            
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
            
            Spacer()
            
            Button(action: onToggleExpand) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary.opacity(0.8))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct SidebarSubItemRow: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                    .frame(width: 16)
                    .foregroundColor(isActive ? .accentColor : (isHovered ? .primary : .secondary))
                
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? .primary : (isHovered ? .primary : .secondary))
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(colorScheme == .dark ? 0.35 : 0.22) : Color.clear, lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { isHovered = $0 }
        .padding(.leading, 18)
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
    @ObservedObject private var faviconManager = WebFaviconManager.shared
    @ObservedObject private var statusController = StatusItemController.shared
    
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
                            .disabled(statusController.isChangingDockPolicy)
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
                    
                    // Language Selection Card
                    LanguageSettingsCard()
                    
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
                            extraContent: {
                                if webPanel.isEnabled && !webPanel.widgets.isEmpty {
                                    VStack(spacing: 6) {
                                        ForEach(webPanel.widgets) { widget in
                                            HStack(spacing: 8) {
                                                // Preferred Favicon with Fallback to SF Symbol
                                                Group {
                                                    if let icon = faviconManager.previewIcon(for: widget.url, widgetId: widget.id, selectedFaviconURL: widget.selectedFaviconURL, removeWhite: widget.removeWhiteBackground) {
                                                        Image(nsImage: icon)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fit)
                                                            .frame(width: 15, height: 15)
                                                            .clipShape(RoundedRectangle(cornerRadius: 3.5))
                                                    } else {
                                                        Image(systemName: widget.iconName.isEmpty ? "globe" : widget.iconName)
                                                            .font(.caption)
                                                            .foregroundColor(.accentColor)
                                                            .frame(width: 15, height: 15)
                                                    }
                                                }
                                                .frame(width: 16, height: 16)
                                                
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
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 10)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                                            .onAppear {
                                                if !widget.url.isEmpty && faviconManager.options(for: widget.url).isEmpty {
                                                    faviconManager.discoverFavicons(for: widget.url, widgetId: widget.id)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.leading, 40)
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
            
            if isOn {
                if let dedicatedBinding = showsDedicatedIcon {
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
                    FlatFlagView(language: l10n.selectedLanguage, size: CGSize(width: 14, height: 10))
                    Text(l10n.selectedLanguage.nativeName)
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
            
            // Languages Grid (4 Supported Languages)
            HStack(spacing: 10) {
                ForEach(AppLanguage.allCases) { lang in
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
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                            .padding(.top, 10)
                    } else {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 56))
                            .foregroundColor(.accentColor)
                            .padding(.top, 10)
                    }
                    
                    Text("Yeoman")
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
                    Text("Copyright © 2026 trst. All rights reserved.")
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
