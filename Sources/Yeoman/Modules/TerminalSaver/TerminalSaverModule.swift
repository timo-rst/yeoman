import SwiftUI
import AppKit

public final class TerminalSaverModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "terminal_saver"
    public var name: String { l10n("terminal_saver.title") }
    public let moduleDescription = "Zeigt nach Inaktivität mehrfarbiges Filigran-ASCII-Art aus GIFs, Bildern, Videos oder Szenen im Terminal."
    public let iconName = "terminal"
    public let category = ModuleCategory.productivity

    @Published public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "terminal_saver_module_is_enabled")
            if isEnabled {
                start()
            } else {
                manager.setEnabled(false)
                stop()
            }
            ModuleManager.shared.objectWillChange.send()
            ModuleManager.shared.recreateAllStatusItems()
        }
    }

    @Published public var showsDedicatedStatusItem: Bool {
        didSet {
            defaults.set(showsDedicatedStatusItem, forKey: "terminal_saver_shows_dedicated_status_item")
            ModuleManager.shared.recreateAllStatusItems()
        }
    }

    let manager: TerminalSaverManager
    private let defaults: UserDefaults
    private var statusItem: NSStatusItem?

    public override convenience init() {
        self.init(manager: .shared, defaults: .standard)
    }

    public init(manager: TerminalSaverManager, defaults: UserDefaults) {
        self.manager = manager
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: "terminal_saver_module_is_enabled") as? Bool ?? manager.config.isEnabled
        self.showsDedicatedStatusItem = defaults.bool(forKey: "terminal_saver_shows_dedicated_status_item")
        super.init()
        manager.setEnabled(isEnabled)
    }

    public func start() {
        guard isEnabled else { return }
        manager.setEnabled(true)
        updateStatusItemVisibility()
    }

    public func stop() {
        manager.flushConfiguration()
        removeStatusItem()
    }

    public func updateStatusItemVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isEnabled && self.showsDedicatedStatusItem {
                self.setupStatusItem()
            } else {
                self.removeStatusItem()
            }
        }
    }

    public func setupStatusItem() {
        guard statusItem == nil else { return }
        guard isEnabled && showsDedicatedStatusItem else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "terminal", accessibilityDescription: name)
            img?.isTemplate = true
            button.image = img
            button.toolTip = name
        }

        let menu = NSMenu()
        let titleItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let timeoutMinutes = manager.config.idleTimeoutSeconds
        let infoItem = NSMenuItem(
            title: String(format: l10n("terminal_saver.timeout_format"), timeoutMinutes),
            action: nil,
            keyEquivalent: ""
        )
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        let copyItem = NSMenuItem(title: l10n("terminal_saver.copy_test_command"), action: #selector(copyTestAction), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let settingsItem = NSMenuItem(title: l10n("menu.settings"), action: #selector(openSettingsAction), keyEquivalent: ",")
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

    @objc private func copyTestAction() {
        manager.copyPreviewTestCommand()
    }

    @objc private func openSettingsAction() {
        StatusItemController.shared.openSettingsWindow()
    }

    public func settingsView() -> AnyView {
        AnyView(TerminalSaverSettingsView(module: self))
    }
}
