import SwiftUI
import AppKit

public final class ClipboardModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "clipboard_manager"
    public let name = "Zwischenablage"
    public let moduleDescription = "Lückenloser Verlauf der Zwischenablage mit Schnellsuche, Favoriten und Passwortschutz."
    public let iconName = "doc.on.clipboard"
    public let category = ModuleCategory.clipboard
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "clipboard_is_enabled")
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
            UserDefaults.standard.set(showsDedicatedStatusItem, forKey: "clipboard_shows_dedicated_status_item")
            ModuleManager.shared.recreateAllStatusItems()
        }
    }
    
    @Published public var activeSubTab: ClipboardSubTab = .history
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "clipboard_is_enabled") as? Bool ?? true
        // Default to true so Clipboard has its own menu bar icon by default
        self.showsDedicatedStatusItem = UserDefaults.standard.object(forKey: "clipboard_shows_dedicated_status_item") as? Bool ?? true
        super.init()
    }
    
    public func start() {
        guard isEnabled else { return }
        ClipboardMonitor.shared.start()
        updateStatusItemVisibility()
    }
    
    public func stop() {
        ClipboardMonitor.shared.stop()
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
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Zwischenablage")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Zwischenablage-Verlauf (Klick zum Öffnen)"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }
    
    public func removeStatusItem() {
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
    
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            let p = NSPopover()
            p.contentSize = NSSize(width: 380, height: 480)
            p.behavior = .transient
            p.animates = true
            p.contentViewController = NSHostingController(rootView: ClipboardView(onCopy: { [weak self] in
                self?.popover?.performClose(nil)
            }))
            self.popover = p
        }
        
        guard let p = popover else { return }
        if p.isShown {
            p.performClose(sender)
        } else {
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            p.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func showContextMenu(for sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Zwischenablage", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Nicht angepinnte leeren", action: #selector(clearUnpinnedAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Alle leeren", action: #selector(clearAllAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Einstellungen...", action: #selector(openSettingsAction), keyEquivalent: ","))
        
        for item in menu.items {
            item.target = self
        }
        
        statusItem?.menu = menu
        sender.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func clearUnpinnedAction() {
        ClipboardHistoryStore.shared.clearUnpinned()
    }
    
    @objc private func clearAllAction() {
        ClipboardHistoryStore.shared.clearAll()
    }
    
    @objc private func openSettingsAction() {
        StatusItemController.shared.openSettingsWindow()
    }
    
    public func settingsView() -> AnyView {
        AnyView(ClipboardSettingsView(module: self))
    }
}
