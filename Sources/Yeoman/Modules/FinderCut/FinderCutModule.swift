import SwiftUI
import AppKit
import Combine

public final class FinderCutModule: NSObject, CustomizerModule, ObservableObject {
    public let id = "finder_cut"
    public let name = "Finder Ausschneiden (⌘X)"
    public let moduleDescription = "Ermöglicht echtes Ausschneiden (⌘X) und Einfügen (⌘V) von Dateien im Finder."
    public let iconName = "scissors"
    public let category = ModuleCategory.productivity

    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "finder_cut_module_is_enabled")
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
            UserDefaults.standard.set(showsDedicatedStatusItem, forKey: "finder_cut_shows_dedicated_status_item")
            ModuleManager.shared.recreateAllStatusItems()
        }
    }

    private var statusItem: NSStatusItem?
    private var cutStateCancellable: AnyCancellable?

    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "finder_cut_module_is_enabled") as? Bool ?? true
        self.showsDedicatedStatusItem = UserDefaults.standard.object(forKey: "finder_cut_shows_dedicated_status_item") as? Bool ?? false
        super.init()

        cutStateCancellable = FinderCutManager.shared.$isCutPending
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItemMenuIfNeeded()
            }
    }

    public func start() {
        guard isEnabled else { return }
        FinderCutManager.shared.start()
        updateStatusItemVisibility()
    }

    public func stop() {
        FinderCutManager.shared.stop()
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
            let img = NSImage(systemSymbolName: "scissors", accessibilityDescription: l10n("finder_cut.title"))
            img?.isTemplate = true
            button.image = img
            button.toolTip = l10n("finder_cut.title")
        }

        self.statusItem = item
        rebuildStatusItemMenu()
    }

    public func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func refreshStatusItemMenuIfNeeded() {
        guard statusItem != nil else { return }
        rebuildStatusItemMenu()
    }

    private func rebuildStatusItemMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: l10n("finder_cut.title"), action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let manager = FinderCutManager.shared
        if manager.isCutPending {
            let pendingTitle = manager.cutItemCount > 0
                ? String(format: l10n("finder_cut.pending_count_format"), manager.cutItemCount)
                : l10n("finder_cut.pending_active")
            let pendingItem = NSMenuItem(title: pendingTitle, action: nil, keyEquivalent: "")
            pendingItem.isEnabled = false
            menu.addItem(pendingItem)

            let cancelItem = NSMenuItem(title: l10n("finder_cut.cancel_pending"), action: #selector(cancelPendingCutAction), keyEquivalent: "")
            cancelItem.target = self
            menu.addItem(cancelItem)
        } else {
            let statusTitle = manager.isRunning ? l10n("finder_cut.status_active") : l10n("finder_cut.status_paused")
            let statusItemRow = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            statusItemRow.isEnabled = false
            menu.addItem(statusItemRow)
        }

        menu.addItem(NSMenuItem.separator())

        let soundItem = NSMenuItem(title: l10n("finder_cut.play_sound"), action: #selector(toggleSoundAction), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = manager.playFeedbackSound ? .on : .off
        menu.addItem(soundItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: l10n("menu.settings"), action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        item.menu = menu
    }

    @objc private func cancelPendingCutAction() {
        FinderCutManager.shared.cancelPendingCut()
    }

    @objc private func toggleSoundAction() {
        FinderCutManager.shared.playFeedbackSound.toggle()
        rebuildStatusItemMenu()
    }

    @objc private func openSettingsAction() {
        StatusItemController.shared.openSettingsWindow()
    }

    public func settingsView() -> AnyView {
        AnyView(FinderCutSettingsView(module: self))
    }
}
