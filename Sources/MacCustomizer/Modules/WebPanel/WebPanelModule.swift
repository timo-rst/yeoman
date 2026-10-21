import SwiftUI
import AppKit
import WebKit

public enum WebUserAgentMode: String, CaseIterable, Identifiable {
    case auto = "Automatisch (nach Größe)"
    case mobile = "Immer Mobil (iPhone)"
    case desktop = "Immer Desktop"
    
    public var id: String { rawValue }
}

public enum WebSizePreset: String, CaseIterable, Identifiable {
    case widget = "320 × 400 (Widget)"
    case iphoneSE = "320 × 568 (iPhone SE)"
    case nexus = "360 × 640 (Mobil Standard)"
    case iphone8 = "375 × 667 (iPhone 8)"
    case iphone14 = "390 × 844 (iPhone 14)"
    case iphoneMax = "430 × 932 (iPhone Pro Max)"
    case ipadMini = "768 × 1024 (iPad mini)"
    case custom = "Benutzerdefiniert"
    
    public var id: String { rawValue }
    
    public var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .widget: return (320, 400)
        case .iphoneSE: return (320, 568)
        case .nexus: return (360, 640)
        case .iphone8: return (375, 667)
        case .iphone14: return (390, 844)
        case .iphoneMax: return (430, 932)
        case .ipadMini: return (768, 1024)
        case .custom: return (380, 550)
        }
    }
}

public final class WebPanelModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "web_panel"
    public let name = "Web-Widget (MenuBarX)"
    public let moduleDescription = "Eigenes Web-Fenster (z.B. Proton Calendar, Notion, ChatGPT) direkt in der Menüleiste mit anpassbarer Fenstergröße & Smartphone-Ansicht."
    public let iconName = "calendar"
    public let category = ModuleCategory.productivity
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "web_panel_is_enabled")
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }
    
    @Published public var showsDedicatedStatusItem: Bool {
        didSet {
            UserDefaults.standard.set(showsDedicatedStatusItem, forKey: "web_panel_shows_status_item")
            updateStatusItemVisibility()
        }
    }
    
    @Published public var targetURL: String {
        didSet {
            UserDefaults.standard.set(targetURL, forKey: "web_panel_target_url")
            controller.loadURL(targetURL)
        }
    }
    
    @Published public var sizePreset: WebSizePreset {
        didSet {
            UserDefaults.standard.set(sizePreset.rawValue, forKey: "web_panel_size_preset")
            if sizePreset != .custom {
                let dims = sizePreset.dimensions
                panelWidth = dims.width
                panelHeight = dims.height
            }
            updatePopoverSize()
        }
    }
    
    @Published public var panelWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(panelWidth), forKey: "web_panel_width")
            updatePopoverSize()
        }
    }
    
    @Published public var panelHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(panelHeight), forKey: "web_panel_height")
            updatePopoverSize()
        }
    }
    
    @Published public var userAgentMode: WebUserAgentMode {
        didSet {
            UserDefaults.standard.set(userAgentMode.rawValue, forKey: "web_panel_user_agent_mode")
            controller.updateUserAgent()
        }
    }
    
    @Published public var statusIconName: String {
        didSet {
            UserDefaults.standard.set(statusIconName, forKey: "web_panel_icon_name")
            updateStatusItemIcon()
        }
    }
    
    @Published public var isPinned: Bool {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: "web_panel_is_pinned")
            popover?.behavior = isPinned ? .applicationDefined : .transient
        }
    }
    
    @Published public var showsAddressBar: Bool {
        didSet {
            UserDefaults.standard.set(showsAddressBar, forKey: "web_panel_shows_address_bar")
        }
    }
    
    public let controller: WebPanelController
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "web_panel_is_enabled") as? Bool ?? true
        self.showsDedicatedStatusItem = UserDefaults.standard.object(forKey: "web_panel_shows_status_item") as? Bool ?? true
        
        let savedURL = UserDefaults.standard.string(forKey: "web_panel_target_url") ?? "https://calendar.proton.me"
        self.targetURL = savedURL
        
        let presetRaw = UserDefaults.standard.string(forKey: "web_panel_size_preset") ?? WebSizePreset.widget.rawValue
        let preset = WebSizePreset(rawValue: presetRaw) ?? .widget
        self.sizePreset = preset
        
        let savedWidth = CGFloat(UserDefaults.standard.double(forKey: "web_panel_width"))
        let savedHeight = CGFloat(UserDefaults.standard.double(forKey: "web_panel_height"))
        self.panelWidth = savedWidth > 0 ? savedWidth : preset.dimensions.width
        self.panelHeight = savedHeight > 0 ? savedHeight : preset.dimensions.height
        
        let uaRaw = UserDefaults.standard.string(forKey: "web_panel_user_agent_mode") ?? WebUserAgentMode.auto.rawValue
        self.userAgentMode = WebUserAgentMode(rawValue: uaRaw) ?? .auto
        
        self.statusIconName = UserDefaults.standard.string(forKey: "web_panel_icon_name") ?? "calendar"
        self.isPinned = UserDefaults.standard.bool(forKey: "web_panel_is_pinned")
        self.showsAddressBar = UserDefaults.standard.object(forKey: "web_panel_shows_address_bar") as? Bool ?? false
        
        self.controller = WebPanelController(initialURL: savedURL)
        
        super.init()
        self.controller.module = self
    }
    
    public func start() {
        guard isEnabled else { return }
        updateStatusItemVisibility()
    }
    
    public func stop() {
        removeStatusItem()
    }
    
    public func updateStatusItemVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isEnabled && self.showsDedicatedStatusItem {
                self.setupStatusItem()
            } else {
                self.removeStatusItem()
            }
        }
    }
    
    private func setupStatusItem() {
        guard statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Web-Widget (Klick zum Öffnen)"
            
            updateStatusItemIcon()
        }
        self.statusItem = item
    }
    
    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: statusIconName, accessibilityDescription: "Web Widget")
        image?.isTemplate = true
        button.image = image
    }
    
    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(for: sender)
        } else {
            togglePopover(sender)
        }
    }
    
    public func togglePopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            let p = NSPopover()
            p.contentSize = NSSize(width: panelWidth, height: panelHeight)
            p.behavior = isPinned ? .applicationDefined : .transient
            p.animates = true
            p.contentViewController = NSHostingController(rootView: WebPanelView(module: self))
            self.popover = p
        }
        
        guard let p = popover else { return }
        if p.isShown {
            p.performClose(sender)
        } else {
            updatePopoverSize()
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            p.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    public func updatePopoverSize() {
        popover?.contentSize = NSSize(width: panelWidth, height: panelHeight)
    }
    
    private func showContextMenu(for sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Web-Fenster öffnen", action: #selector(openPopoverAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Neu laden", action: #selector(reloadAction), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Im Standardbrowser öffnen", action: #selector(openInBrowserAction), keyEquivalent: "b"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: isPinned ? "Fenster lösen" : "Fenster anheften (Pin)", action: #selector(togglePinAction), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Einstellungen...", action: #selector(openSettingsAction), keyEquivalent: ","))
        
        for item in menu.items {
            item.target = self
        }
        
        statusItem?.menu = menu
        sender.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func openPopoverAction() {
        if let button = statusItem?.button {
            togglePopover(button)
        }
    }
    
    @objc private func reloadAction() {
        controller.reload()
    }
    
    @objc private func openInBrowserAction() {
        if let url = URL(string: controller.currentURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func togglePinAction() {
        isPinned.toggle()
    }
    
    @objc private func openSettingsAction() {
        StatusItemController.shared.openSettingsWindow()
    }
    
    public func settingsView() -> AnyView {
        AnyView(WebPanelSettingsView(module: self))
    }
}
