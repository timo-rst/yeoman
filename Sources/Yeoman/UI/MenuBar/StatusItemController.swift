import AppKit
import SwiftUI

public final class StatusItemController: NSObject, ObservableObject, NSMenuDelegate, NSWindowDelegate {
    public static let shared = StatusItemController()
    
    @Published public var isChangingDockPolicy: Bool = false
    private var pendingDockPolicy: NSApplication.ActivationPolicy?
    
    private var statusItem: NSStatusItem?
    private var clipboardWindow: NSWindow?
    public private(set) var settingsWindow: NSWindow?
    
    private var previousAppForMenu: NSRunningApplication?
    private var previousAppForClipboardWindow: NSRunningApplication?
    private var temporarilyHiddenSettingsForClipboard: Bool = false
    
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
            let image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Yeoman")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Yeoman"
        }
        
        NotificationCenter.default.removeObserver(self, name: .appLanguageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: .appLanguageDidChange, object: nil)
        
        updateMenu()
    }
    
    @objc private func handleLanguageChange() {
        updateMenu()
        settingsWindow?.title = l10n("window.settings_title")
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
        let titleItem = NSMenuItem(title: "Yeoman", action: nil, keyEquivalent: "")
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
        let clipItem = NSMenuItem(title: l10n("menu.clipboard_recent"), action: nil, keyEquivalent: "")
        let clipSubmenu = NSMenu()
        
        let recentItems = ClipboardHistoryStore.shared.items.prefix(8)
        if recentItems.isEmpty {
            let emptyItem = NSMenuItem(title: l10n("menu.empty"), action: nil, keyEquivalent: "")
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
        let openClipItem = NSMenuItem(title: l10n("menu.clipboard_search"), action: #selector(openClipboardWindow), keyEquivalent: "v")
        openClipItem.keyEquivalentModifierMask = [.command, .shift]
        openClipItem.target = self
        clipSubmenu.addItem(openClipItem)
        
        clipItem.submenu = clipSubmenu
        menu.addItem(clipItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings & Quit
        let settingsItem = NSMenuItem(title: l10n("menu.settings"), action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let updateItem = NSMenuItem(title: l10n("menu.check_updates"), action: #selector(checkForUpdatesMenuAction), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: l10n("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func checkForUpdatesMenuAction() {
        openSettingsWindow()
        UpdateManager.shared.checkForUpdates(silent: false)
    }
    
    @objc public func menuWillOpen(_ menu: NSMenu) {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousAppForMenu = front
        }
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
            if let prev = previousAppForMenu,
               prev.bundleIdentifier != Bundle.main.bundleIdentifier,
               !prev.isTerminated {
                activateApp(prev)
            } else {
                NSApp.deactivate()
            }
            previousAppForMenu = nil
        }
    }
    
    @objc public func openClipboardWindow() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousAppForClipboardWindow = front
        }
        
        if let settings = settingsWindow,
           settings.isVisible,
           !settings.isKeyWindow {
            self.temporarilyHiddenSettingsForClipboard = true
            settings.orderOut(nil)
        } else {
            self.temporarilyHiddenSettingsForClipboard = false
        }
        
        if clipboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = l10n("tab.clipboard")
            window.contentView = NSHostingView(rootView: ClipboardView(onCopy: { [weak self] in
                self?.closeClipboardWindowAndRestoreFocus()
            }))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.clipboardWindow = window
        } else {
            clipboardWindow?.contentView = NSHostingView(rootView: ClipboardView(onCopy: { [weak self] in
                self?.closeClipboardWindowAndRestoreFocus()
            }))
        }
        clipboardWindow?.orderFrontRegardless()
        clipboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func closeClipboardWindowAndRestoreFocus() {
        clipboardWindow?.orderOut(nil)
        restoreFocusFromClipboardWindow()
    }
    
    public func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow == clipboardWindow {
            restoreFocusFromClipboardWindow()
        }
    }
    
    private func restoreFocusFromClipboardWindow() {
        guard previousAppForClipboardWindow != nil || temporarilyHiddenSettingsForClipboard else { return }
        
        let appToRestore = self.previousAppForClipboardWindow
        let shouldRestoreSettings = self.temporarilyHiddenSettingsForClipboard
        self.previousAppForClipboardWindow = nil
        self.temporarilyHiddenSettingsForClipboard = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let app = appToRestore,
               app.bundleIdentifier != Bundle.main.bundleIdentifier,
               !app.isTerminated {
                self.activateApp(app)
            } else {
                NSApp.deactivate()
            }
            
            if shouldRestoreSettings, let settings = self.settingsWindow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    settings.orderBack(nil)
                }
            }
        }
    }
    
    private func activateApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
    
    @objc public func openSettingsWindow() {
        let standardWidth: CGFloat = 1040
        let standardHeight: CGFloat = 720
        let minWidth: CGFloat = 980
        let minHeight: CGFloat = 660
        
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: standardWidth, height: standardHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = l10n("window.settings_title")
            window.minSize = NSSize(width: minWidth, height: minHeight)
            window.collectionBehavior = [.fullScreenPrimary]
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .normal
            self.settingsWindow = window
        } else if let window = settingsWindow {
            window.title = l10n("window.settings_title")
            window.level = .normal
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
        let desiredPolicy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        
        // If a transition is already in flight, queue the desired state instead of spamming WindowServer/Dock
        if isChangingDockPolicy {
            pendingDockPolicy = desiredPolicy
            return
        }
        
        guard NSApp.activationPolicy() != desiredPolicy else {
            pendingDockPolicy = nil
            return
        }
        
        applyDockPolicy(desiredPolicy)
    }
    
    private func applyDockPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else {
            isChangingDockPolicy = false
            pendingDockPolicy = nil
            return
        }
        
        isChangingDockPolicy = true
        pendingDockPolicy = nil
        
        let targetWindow = settingsWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible })
        
        // Temporarily elevate to .floating during the transition so WindowServer
        // doesn't push the window behind background apps while toggling the dock icon
        targetWindow?.level = .floating
        targetWindow?.orderFrontRegardless()
        targetWindow?.makeKeyAndOrderFront(nil)
        
        NSApp.setActivationPolicy(policy)
        
        let bringToFront = { [weak self] in
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            if let window = self?.settingsWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) {
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
        
        // Changing activation policy causes WindowServer to yield focus to background apps.
        // Re-assert focus and bring window front across multiple ticks until WindowServer stabilizes.
        DispatchQueue.main.async(execute: bringToFront)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: bringToFront)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: bringToFront)
        
        // Allow WindowServer and Dock.app sufficient time (400ms) to complete tile animation & state sync
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) { [weak self] in
            guard let self = self else { return }
            
            if let window = self.settingsWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) {
                window.level = .normal
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
            
            self.isChangingDockPolicy = false
            
            // If the user toggled while the transition was running, apply the final requested state cleanly
            if let nextPolicy = self.pendingDockPolicy {
                self.pendingDockPolicy = nil
                if NSApp.activationPolicy() != nextPolicy {
                    self.applyDockPolicy(nextPolicy)
                }
            }
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
