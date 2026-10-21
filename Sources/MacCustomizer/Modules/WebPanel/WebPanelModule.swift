import SwiftUI
import AppKit
import WebKit

public enum WebUserAgentMode: String, CaseIterable, Identifiable, Codable {
    case auto = "Automatisch (nach Größe)"
    case mobile = "Immer Mobil (iPhone)"
    case desktop = "Immer Desktop"
    
    public var id: String { rawValue }
}

public enum WebSizePreset: String, CaseIterable, Identifiable, Codable {
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

public struct WebWidgetItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var url: String
    public var iconName: String
    public var useFavicon: Bool
    public var sizePreset: WebSizePreset
    public var customWidth: CGFloat
    public var customHeight: CGFloat
    public var userAgentMode: WebUserAgentMode
    public var zoomScale: Double
    public var isEnabled: Bool
    public var isPinned: Bool
    public var showsAddressBar: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, title, url, iconName, useFavicon, sizePreset, customWidth, customHeight, userAgentMode, zoomScale, isEnabled, isPinned, showsAddressBar
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        url: String,
        iconName: String = "calendar",
        useFavicon: Bool = true,
        sizePreset: WebSizePreset = .widget,
        customWidth: CGFloat = 320,
        customHeight: CGFloat = 400,
        userAgentMode: WebUserAgentMode = .auto,
        zoomScale: Double = 1.0,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        showsAddressBar: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.iconName = iconName
        self.useFavicon = useFavicon
        self.sizePreset = sizePreset
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.userAgentMode = userAgentMode
        self.zoomScale = zoomScale
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.showsAddressBar = showsAddressBar
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.url = try container.decode(String.self, forKey: .url)
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "calendar"
        self.useFavicon = try container.decodeIfPresent(Bool.self, forKey: .useFavicon) ?? true
        self.sizePreset = try container.decodeIfPresent(WebSizePreset.self, forKey: .sizePreset) ?? .widget
        self.customWidth = try container.decodeIfPresent(CGFloat.self, forKey: .customWidth) ?? 320
        self.customHeight = try container.decodeIfPresent(CGFloat.self, forKey: .customHeight) ?? 400
        self.userAgentMode = try container.decodeIfPresent(WebUserAgentMode.self, forKey: .userAgentMode) ?? .auto
        self.zoomScale = try container.decodeIfPresent(Double.self, forKey: .zoomScale) ?? 1.0
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.showsAddressBar = try container.decodeIfPresent(Bool.self, forKey: .showsAddressBar) ?? false
    }
    
    public var effectiveWidth: CGFloat {
        if sizePreset == .custom { return customWidth }
        return sizePreset.dimensions.width
    }
    
    public var effectiveHeight: CGFloat {
        if sizePreset == .custom { return customHeight }
        return sizePreset.dimensions.height
    }
}

public final class WebPanelModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "web_panel"
    public let name = "Web-Widgets (iFrames)"
    public let moduleDescription = "Verwalte deine Web-Widgets & iFrames (wie in MenuBarX). Erstelle, bearbeite und lösche mehrere Web-Apps mit anpassbaren Größen und Smartphone-Vorschau."
    public let iconName = "globe"
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
            syncAllInstances()
        }
    }
    
    @Published public var widgets: [WebWidgetItem] = [] {
        didSet {
            saveWidgets()
            syncAllInstances()
        }
    }
    
    private var instanceControllers: [UUID: WebWidgetInstanceController] = [:]
    private let widgetsStorageKey = "web_panel_widgets_list_json"
    
    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "web_panel_is_enabled") as? Bool ?? true
        self.showsDedicatedStatusItem = UserDefaults.standard.object(forKey: "web_panel_shows_status_item") as? Bool ?? true
        super.init()
        
        loadWidgets()
    }
    
    public func start() {
        guard isEnabled else { return }
        syncAllInstances()
    }
    
    public func stop() {
        for controller in instanceControllers.values {
            controller.cleanup()
        }
        instanceControllers.removeAll()
    }
    
    public func updateStatusItemVisibility() {
        syncAllInstances()
    }
    
    // MARK: - CRUD Operations
    
    public func addWidget(_ item: WebWidgetItem) {
        widgets.append(item)
    }
    
    public func updateWidget(_ item: WebWidgetItem) {
        if let idx = widgets.firstIndex(where: { $0.id == item.id }) {
            widgets[idx] = item
            if let controller = instanceControllers[item.id] {
                controller.update(with: item)
            }
        }
    }
    
    public func deleteWidget(id: UUID) {
        if let controller = instanceControllers.removeValue(forKey: id) {
            controller.cleanup()
        }
        widgets.removeAll(where: { $0.id == id })
    }
    
    public func toggleWidget(id: UUID, isEnabled: Bool) {
        if let idx = widgets.firstIndex(where: { $0.id == id }) {
            widgets[idx].isEnabled = isEnabled
        }
    }
    
    // MARK: - Instance Synchronization
    
    private func syncAllInstances() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let activeIds = Set(self.widgets.map { $0.id })
            
            // Remove controllers for deleted widgets
            for (id, controller) in self.instanceControllers where !activeIds.contains(id) {
                controller.cleanup()
                self.instanceControllers.removeValue(forKey: id)
            }
            
            // Setup or update controllers
            for widget in self.widgets {
                if self.isEnabled && self.showsDedicatedStatusItem && widget.isEnabled {
                    if let existing = self.instanceControllers[widget.id] {
                        existing.update(with: widget)
                    } else {
                        let newController = WebWidgetInstanceController(item: widget, module: self)
                        newController.setup()
                        self.instanceControllers[widget.id] = newController
                    }
                } else {
                    if let existing = self.instanceControllers[widget.id] {
                        existing.cleanup()
                        self.instanceControllers.removeValue(forKey: widget.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveWidgets() {
        if let data = try? JSONEncoder().encode(widgets) {
            UserDefaults.standard.set(data, forKey: widgetsStorageKey)
        }
    }
    
    private func loadWidgets() {
        if let data = UserDefaults.standard.data(forKey: widgetsStorageKey),
           let loaded = try? JSONDecoder().decode([WebWidgetItem].self, from: data),
           !loaded.isEmpty {
            self.widgets = loaded
        } else {
            // Default first item: Proton Calendar (matching user's setup!)
            self.widgets = [
                WebWidgetItem(
                    title: "Proton Kalender",
                    url: "https://calendar.proton.me",
                    iconName: "calendar",
                    sizePreset: .widget,
                    customWidth: 320,
                    customHeight: 400,
                    userAgentMode: .auto,
                    isEnabled: true
                )
            ]
            saveWidgets()
        }
    }
    
    public func openWidgetPopover(id: UUID) {
        instanceControllers[id]?.openPopover()
    }
    
    public func settingsView() -> AnyView {
        AnyView(WebPanelSettingsView(module: self))
    }
}

// MARK: - Individual Instance Controller

public final class WebWidgetInstanceController: NSObject, ObservableObject {
    @Published public var item: WebWidgetItem
    public let webController: WebPanelController
    weak var module: WebPanelModule?
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    public init(item: WebWidgetItem, module: WebPanelModule) {
        self.item = item
        self.module = module
        self.webController = WebPanelController(
            initialURL: item.url,
            userAgentMode: item.userAgentMode,
            targetWidth: item.effectiveWidth,
            zoomScale: item.zoomScale
        )
        super.init()
        self.webController.associatedItem = item
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFaviconUpdate(_:)),
            name: .webFaviconDidUpdate,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleFaviconUpdate(_ notification: Notification) {
        if let targetId = notification.userInfo?["widgetId"] as? UUID, targetId == item.id {
            DispatchQueue.main.async { [weak self] in
                self?.updateStatusItemIcon()
            }
        } else if let targetUrl = notification.userInfo?["url"] as? String, targetUrl == item.url {
            DispatchQueue.main.async { [weak self] in
                self?.updateStatusItemIcon()
            }
        }
    }
    
    public func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        
        if item.useFavicon, let webIcon = WebFaviconManager.shared.menuBarIcon(for: item) {
            button.image = webIcon
        } else {
            let img = NSImage(systemSymbolName: item.iconName, accessibilityDescription: item.title)
            img?.isTemplate = true
            button.image = img
        }
    }
    
    public func setup() {
        guard statusItem == nil else { return }
        let sItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = sItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "\(item.title) (Klick zum Öffnen)"
        }
        self.statusItem = sItem
        updateStatusItemIcon()
        
        if item.useFavicon {
            WebFaviconManager.shared.fetchFavicon(for: item.url, widgetId: item.id) { [weak self] _ in
                self?.updateStatusItemIcon()
            }
        }
    }
    
    public func update(with newItem: WebWidgetItem) {
        let oldUrl = self.item.url
        let oldUseFavicon = self.item.useFavicon
        let oldIconName = self.item.iconName
        
        self.item = newItem
        webController.associatedItem = newItem
        webController.updateConfig(
            userAgentMode: newItem.userAgentMode,
            targetWidth: newItem.effectiveWidth,
            zoomScale: newItem.zoomScale,
            newURL: newItem.url
        )
        
        if let button = statusItem?.button {
            button.toolTip = "\(newItem.title) (Klick zum Öffnen)"
        }
        updateStatusItemIcon()
        
        if (newItem.url != oldUrl || newItem.useFavicon != oldUseFavicon || newItem.iconName != oldIconName) && newItem.useFavicon {
            WebFaviconManager.shared.fetchFavicon(for: newItem.url, widgetId: newItem.id) { [weak self] _ in
                self?.updateStatusItemIcon()
            }
        }
        
        let newSize = NSSize(width: newItem.effectiveWidth, height: newItem.effectiveHeight)
        popover?.contentSize = newSize
        popover?.behavior = newItem.isPinned ? .applicationDefined : .transient
    }
    
    public func cleanup() {
        NotificationCenter.default.removeObserver(self)
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        if let p = popover, p.isShown {
            p.performClose(nil)
        }
        popover = nil
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(for: sender)
        } else {
            togglePopover(sender)
        }
    }
    
    public func openPopover() {
        if let button = statusItem?.button {
            togglePopover(button)
        }
    }
    
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            let p = NSPopover()
            p.contentSize = NSSize(width: item.effectiveWidth, height: item.effectiveHeight)
            p.behavior = item.isPinned ? .applicationDefined : .transient
            p.animates = true
            p.contentViewController = NSHostingController(
                rootView: WebPanelView(
                    instance: self,
                    controller: webController,
                    onUpdateItem: { [weak self] updated in
                        self?.module?.updateWidget(updated)
                    }
                )
            )
            self.popover = p
        }
        
        guard let p = popover else { return }
        if p.isShown {
            p.performClose(sender)
        } else {
            p.contentSize = NSSize(width: item.effectiveWidth, height: item.effectiveHeight)
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            p.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func showContextMenu(for sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "\(item.title) öffnen", action: #selector(openPopoverAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Neu laden", action: #selector(reloadAction), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Im Standardbrowser öffnen", action: #selector(openInBrowserAction), keyEquivalent: "b"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: item.isPinned ? "Fenster lösen" : "Fenster anheften (Pin)", action: #selector(togglePinAction), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Einstellungen...", action: #selector(openSettingsAction), keyEquivalent: ","))
        
        for mItem in menu.items {
            mItem.target = self
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
        webController.reload()
    }
    
    @objc private func openInBrowserAction() {
        if let url = URL(string: webController.currentURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func togglePinAction() {
        var updated = item
        updated.isPinned.toggle()
        module?.updateWidget(updated)
    }
    
    @objc private func openSettingsAction() {
        StatusItemController.shared.openSettingsWindow()
    }
}
