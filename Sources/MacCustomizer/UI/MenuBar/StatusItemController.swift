import AppKit
import SwiftUI

public final class StatusItemController: NSObject, NSMenuDelegate {
    public static let shared = StatusItemController()
    
    private var statusItem: NSStatusItem?
    private var clipboardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    
    public override init() {
        super.init()
    }
    
    public var showsMainStatusItem: Bool {
        get { UserDefaults.standard.object(forKey: "showMainStatusItem") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showMainStatusItem")
            ModuleManager.shared.recreateAllStatusItems()
        }
    }
    
    public func setup() {
        guard showsMainStatusItem else { return }
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "MacCustomizer")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "MacCustomizer"
        }
        
        updateMenu()
    }
    
    public func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    public func recreateStatusItem() {
        removeStatusItem()
        if showsMainStatusItem {
            setup()
        }
    }
    
    public func updateStatusItemVisibility() {
        if showsMainStatusItem {
            if statusItem == nil {
                setup()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }
    
    public func updateMenu() {
        let menu = NSMenu()
        menu.delegate = self
        
        // Header
        let titleItem = NSMenuItem(title: "MacCustomizer", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Menu Bar Spacing Submenu ---
        let spacingItem = NSMenuItem(title: "Menüleisten-Abstand", action: nil, keyEquivalent: "")
        let spacingSubmenu = NSMenu()
        
        let currentSpacing = MenuBarSpacingManager.shared.currentSpacing
        
        let ultraItem = NSMenuItem(title: "Ultra-Kompakt (4 pt)", action: #selector(setSpacingUltra), keyEquivalent: "")
        ultraItem.target = self
        ultraItem.state = currentSpacing == 4 ? .on : .off
        spacingSubmenu.addItem(ultraItem)
        
        let compactItem = NSMenuItem(title: "Kompakt (8 pt)", action: #selector(setSpacingCompact), keyEquivalent: "")
        compactItem.target = self
        compactItem.state = currentSpacing == 8 ? .on : .off
        spacingSubmenu.addItem(compactItem)
        
        let standardItem = NSMenuItem(title: "Standard (16 pt)", action: #selector(setSpacingStandard), keyEquivalent: "")
        standardItem.target = self
        standardItem.state = currentSpacing == 16 ? .on : .off
        spacingSubmenu.addItem(standardItem)
        
        spacingSubmenu.addItem(NSMenuItem.separator())
        let restartItem = NSMenuItem(title: "Menüleiste aktualisieren", action: #selector(restartControlCenter), keyEquivalent: "")
        restartItem.target = self
        spacingSubmenu.addItem(restartItem)
        
        spacingItem.submenu = spacingSubmenu
        menu.addItem(spacingItem)
        
        // --- Clipboard Submenu ---
        let clipItem = NSMenuItem(title: "Zwischenablage (Verlauf)", action: nil, keyEquivalent: "")
        let clipSubmenu = NSMenu()
        
        let recentItems = ClipboardHistoryStore.shared.items.prefix(8)
        if recentItems.isEmpty {
            let emptyItem = NSMenuItem(title: "Keine Einträge vorhanden", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            clipSubmenu.addItem(emptyItem)
        } else {
            for item in recentItems {
                let title = (item.isPinned ? "📌 " : "") + item.preview
                let menuItem = NSMenuItem(title: title, action: #selector(copyClipboardItem(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item.content
                clipSubmenu.addItem(menuItem)
            }
        }
        
        clipSubmenu.addItem(NSMenuItem.separator())
        let openClipItem = NSMenuItem(title: "Verlauf durchsuchen...", action: #selector(openClipboardWindow), keyEquivalent: "v")
        openClipItem.keyEquivalentModifierMask = [.command, .shift]
        openClipItem.target = self
        clipSubmenu.addItem(openClipItem)
        
        clipItem.submenu = clipSubmenu
        menu.addItem(clipItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Multi-Monitor Info item
        let displayCount = DisplayManager.shared.displays.count
        let monitorItem = NSMenuItem(title: "\(displayCount) Monitor(e) verbunden", action: nil, keyEquivalent: "")
        monitorItem.isEnabled = false
        menu.addItem(monitorItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings & Quit
        let settingsItem = NSMenuItem(title: "Einstellungen...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let updateItem = NSMenuItem(title: "Nach Updates suchen...", action: #selector(checkForUpdatesMenuAction), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "MacCustomizer beenden", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func checkForUpdatesMenuAction() {
        openSettingsWindow()
        UpdateManager.shared.checkForUpdates(silent: false)
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }
    
    @objc private func setSpacingUltra() {
        MenuBarSpacingManager.shared.applyPreset(.ultraCompact)
    }
    
    @objc private func setSpacingCompact() {
        MenuBarSpacingManager.shared.applyPreset(.compact)
    }
    
    @objc private func setSpacingStandard() {
        MenuBarSpacingManager.shared.applyPreset(.standard)
    }
    
    @objc private func restartControlCenter() {
        MenuBarSpacingManager.shared.restartControlCenter()
    }
    
    @objc private func copyClipboardItem(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            ClipboardMonitor.shared.copyToClipboard(text)
        }
    }
    
    @objc public func openClipboardWindow() {
        if clipboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Zwischenablage Verlauf"
            window.contentView = NSHostingView(rootView: ClipboardView())
            window.center()
            window.isReleasedWhenClosed = false
            self.clipboardWindow = window
        }
        clipboardWindow?.orderFrontRegardless()
        clipboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc public func openSettingsWindow() {
        let standardWidth: CGFloat = 1040
        let standardHeight: CGFloat = 720
        let minWidth: CGFloat = 980
        let minHeight: CGFloat = 660
        
        let showDock = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        let targetLevel: NSWindow.Level = showDock ? .normal : .floating
        
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: standardWidth, height: standardHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MacCustomizer Einstellungen"
            window.minSize = NSSize(width: minWidth, height: minHeight)
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            window.level = targetLevel
            self.settingsWindow = window
        } else if let window = settingsWindow {
            window.level = targetLevel
            window.minSize = NSSize(width: minWidth, height: minHeight)
            if window.frame.width < minWidth || window.frame.height < minHeight {
                var frame = window.frame
                frame.size.width = max(frame.size.width, standardWidth)
                frame.size.height = max(frame.size.height, standardHeight)
                window.setFrame(frame, display: true, animate: true)
            }
        }
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    public func setDockIconVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        let targetLevel: NSWindow.Level = visible ? .normal : .floating
        
        if let window = settingsWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) {
            window.level = targetLevel
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
        
        NSApp.setActivationPolicy(policy)
        
        let bringToFront = { [weak self] in
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            if let window = self?.settingsWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) {
                window.level = targetLevel
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
        
        // Changing activation policy causes WindowServer to yield focus to background apps.
        // Re-assert focus and bring window front across multiple ticks until WindowServer stabilizes.
        DispatchQueue.main.async(execute: bringToFront)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: bringToFront)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: bringToFront)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: bringToFront)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
