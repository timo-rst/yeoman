import SwiftUI
import AppKit

public final class ScrollReverserModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "scroll_reverser"
    public let name = "Scroll-Richtung"
    public let moduleDescription = "Trennt die Scrollrichtung von Maus und Trackpad für natürliches Scrollen auf beiden Geräten."
    public let iconName = "computermouse"
    public let category = ModuleCategory.system
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "sr_module_is_enabled")
            if isEnabled {
                start()
            } else {
                stop()
            }
            ModuleManager.shared.objectWillChange.send()
            ModuleManager.shared.recreateAllStatusItems()
        }
    }
    
    @Published public var showsDedicatedStatusItem: Bool {
        didSet {
            UserDefaults.standard.set(showsDedicatedStatusItem, forKey: "sr_shows_dedicated_status_item")
            ModuleManager.shared.recreateAllStatusItems()
        }
    }
    
    private var statusItem: NSStatusItem?
    
    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "sr_module_is_enabled") as? Bool ?? true
        self.showsDedicatedStatusItem = UserDefaults.standard.object(forKey: "sr_shows_dedicated_status_item") as? Bool ?? false
        super.init()
    }
    
    public func start() {
        guard isEnabled else { return }
        ScrollReverserManager.shared.start()
        updateStatusItemVisibility()
    }
    
    public func stop() {
        ScrollReverserManager.shared.stop()
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
            let img = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Scroll-Richtung")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "Scroll-Richtung (Klick für Optionen)"
        }
        
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Scroll-Richtung", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        let mouseToggle = NSMenuItem(title: "Maus vertikal umkehren", action: #selector(toggleMouseV), keyEquivalent: "")
        mouseToggle.target = self
        mouseToggle.state = ScrollReverserManager.shared.reverseMouseVertical ? .on : .off
        menu.addItem(mouseToggle)
        
        let trackpadToggle = NSMenuItem(title: "Trackpad vertikal umkehren", action: #selector(toggleTrackpadV), keyEquivalent: "")
        trackpadToggle.target = self
        trackpadToggle.state = ScrollReverserManager.shared.reverseTrackpadVertical ? .on : .off
        menu.addItem(trackpadToggle)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Einstellungen öffnen...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        item.menu = menu
        self.statusItem = item
    }
    
    public func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    @objc private func toggleMouseV() {
        ScrollReverserManager.shared.reverseMouseVertical.toggle()
        updateStatusItemVisibility()
    }
    
    @objc private func toggleTrackpadV() {
        ScrollReverserManager.shared.reverseTrackpadVertical.toggle()
        updateStatusItemVisibility()
    }
    
    @objc private func openSettings() {
        StatusItemController.shared.openSettingsWindow()
    }
    
    public func settingsView() -> AnyView {
        AnyView(ScrollReverserSettingsView(module: self))
    }
}
