import SwiftUI
import AppKit
import Combine

public final class ClipboardModule: NSObject, CustomizerModule, ObservableObject, NSPopoverDelegate {
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
    
    public var showsDedicatedStatusItem: Bool {
        get { isEnabled }
        set { isEnabled = newValue }
    }
    
    @Published public var activeSubTab: ClipboardSubTab = .history
    public let popoverPin = PopoverPinPreference(storageKey: "clipboard_popover_pinned")
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var pinCancellable: AnyCancellable?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var isClosingPopover = false
    
    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "clipboard_is_enabled") as? Bool ?? true
        super.init()
        pinCancellable = popoverPin.$isPinned
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.popover?.behavior = self.popoverPin.popoverBehavior
            }
    }

    deinit {
        removeDismissMonitors()
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
            closePopoverAndRestoreFocus()
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
            p.behavior = popoverPin.popoverBehavior
            p.animates = true
            p.delegate = self
            p.contentViewController = NSHostingController(
                rootView: ClipboardView(
                    onCopy: { [weak self] in
                        guard let self, !self.popoverPin.isPinned else { return }
                        self.closePopoverAndRestoreFocus()
                    },
                    onDismissPopover: { [weak self] in
                        self?.closePopoverAndRestoreFocus()
                    },
                    pinPreference: popoverPin
                )
            )
            self.popover = p
        }
        
        guard let p = popover else { return }
        if p.isShown {
            closePopoverAndRestoreFocus()
        } else {
            isClosingPopover = false
            PopoverFocusCoordinator.shared.prepareForPresentation(of: p)
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            p.contentViewController?.view.window?.makeKey()
            installDismissMonitors()
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func closePopoverAndRestoreFocus() {
        guard !isClosingPopover else { return }
        isClosingPopover = true
        removeDismissMonitors()
        ClipboardImagePreviewController.shared.closePreviewOnly(restoreParentFocus: false)
        if let p = popover, p.isShown {
            p.performClose(nil)
        } else {
            isClosingPopover = false
        }
    }

    public func popoverShouldClose(_ popover: NSPopover) -> Bool {
        // While the non-modal image preview panel is visible, outside-click/resign
        // monitors and explicit close actions govern dismissal so clicks inside the
        // preview panel do not trigger AppKit's transient close.
        !ClipboardImagePreviewController.shared.isShown
    }
    
    public func popoverDidClose(_ notification: Notification) {
        isClosingPopover = false
        removeDismissMonitors()
        ClipboardImagePreviewController.shared.closePreviewOnly(restoreParentFocus: false)
        PopoverFocusCoordinator.shared.handlePopoverDidClose(of: popover)
        guard let closedPopover = notification.object as? NSPopover else { return }
        closedPopover.contentViewController = nil
        closedPopover.delegate = nil
        if popover === closedPopover {
            popover = nil
        }
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleOutsideMouseDown(event: event, isGlobal: false)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleOutsideMouseDown(event: event, isGlobal: true)
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  !self.popoverPin.isPinned,
                  let popover = self.popover,
                  popover.isShown else { return }
            self.closePopoverAndRestoreFocus()
        }
    }

    private func removeDismissMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
    }

    private func handleOutsideMouseDown(event: NSEvent, isGlobal: Bool) {
        guard let popover, popover.isShown, !isClosingPopover else { return }

        if !isGlobal {
            if let buttonWindow = statusItem?.button?.window, event.window === buttonWindow {
                return
            }
            if let eventWindow = event.window,
               String(describing: type(of: eventWindow)).contains("Menu") {
                return
            }
        }

        let mouseLocation = NSEvent.mouseLocation
        let previewWindow = ClipboardImagePreviewController.shared.panelWindow
        let isPreviewShown = ClipboardImagePreviewController.shared.isShown
        let popoverWindow = popover.contentViewController?.view.window

        let clickedInsidePreview: Bool
        if !isGlobal, isPreviewShown, let previewWindow {
            clickedInsidePreview = (event.window === previewWindow) || previewWindow.frame.contains(mouseLocation)
        } else {
            clickedInsidePreview = false
        }

        let clickedInsidePopover: Bool
        if !isGlobal, let popoverWindow {
            clickedInsidePopover = (event.window === popoverWindow) || popoverWindow.frame.contains(mouseLocation)
        } else {
            clickedInsidePopover = false
        }

        let action = ClipboardPreviewDismissalPolicy.actionForOutsideEvent(
            isPinned: popoverPin.isPinned,
            isPreviewShown: isPreviewShown,
            isPopoverShown: popover.isShown,
            clickedInsidePreview: clickedInsidePreview,
            clickedInsidePopover: clickedInsidePopover
        )

        if action == .closePreviewAndPopover {
            closePopoverAndRestoreFocus()
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
