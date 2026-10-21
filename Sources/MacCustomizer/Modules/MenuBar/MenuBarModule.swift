import SwiftUI
import AppKit

public final class MenuBarModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "menu_bar_optimizer"
    public let name = "Menüleisten-Optimizer"
    public let moduleDescription = "Kompaktere Symbole (wie Ice), anpassbarer Abstand und Multi-Monitor-Unterstützung."
    public let iconName = "menubar.rectangle"
    public let category = ModuleCategory.menuBar
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "menu_bar_is_enabled")
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }
    
    @Published public var showsDedicatedStatusItem: Bool {
        didSet {
            UserDefaults.standard.set(showsDedicatedStatusItem, forKey: "menu_bar_shows_dedicated_status_item")
            ModuleManager.shared.recreateAllStatusItems()
        }
    }
    
    private var statusItem: NSStatusItem?
    
    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "menu_bar_is_enabled") as? Bool ?? true
        self.showsDedicatedStatusItem = UserDefaults.standard.object(forKey: "menu_bar_shows_dedicated_status_item") as? Bool ?? false
        super.init()
    }
    
    public func start() {
        guard isEnabled else { return }
        _ = MenuBarSpacingManager.shared
        _ = DisplayManager.shared
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
    
    public func recreateStatusItem() {
        removeStatusItem()
        if isEnabled && showsDedicatedStatusItem {
            setupStatusItem()
        }
    }
    
    public func setupStatusItem() {
        guard statusItem == nil else { return }
        guard isEnabled && showsDedicatedStatusItem else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "arrow.left.and.line.vertical.and.arrow.right", accessibilityDescription: "Menüleisten-Abstand")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Menüleisten-Abstand (Presets)"
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Menüleisten-Abstand", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let ultra = NSMenuItem(title: "Ultra-Kompakt (4 pt)", action: #selector(setUltra), keyEquivalent: "")
        ultra.target = self
        menu.addItem(ultra)
        
        let compact = NSMenuItem(title: "Kompakt (8 pt - Ice)", action: #selector(setCompact), keyEquivalent: "")
        compact.target = self
        menu.addItem(compact)
        
        let standard = NSMenuItem(title: "Standard (16 pt)", action: #selector(setStandard), keyEquivalent: "")
        standard.target = self
        menu.addItem(standard)
        
        menu.addItem(NSMenuItem.separator())
        let restart = NSMenuItem(title: "ControlCenter neu starten", action: #selector(restartCC), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)
        
        item.menu = menu
        self.statusItem = item
    }
    
    public func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    @objc private func setUltra() { MenuBarSpacingManager.shared.applyPreset(.ultraCompact) }
    @objc private func setCompact() { MenuBarSpacingManager.shared.applyPreset(.compact) }
    @objc private func setStandard() { MenuBarSpacingManager.shared.applyPreset(.standard) }
    @objc private func restartCC() { MenuBarSpacingManager.shared.restartControlCenter() }
    
    public func settingsView() -> AnyView {
        AnyView(MenuBarSettingsView(module: self))
    }
}
