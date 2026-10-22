import SwiftUI
import Combine

public final class ModuleManager: ObservableObject {
    public static let shared = ModuleManager()
    
    @Published public private(set) var modules: [any CustomizerModule] = []
    
    public lazy var menuBarModule = MenuBarModule()
    public lazy var webPanelModule = WebPanelModule()
    public lazy var clipboardModule = ClipboardModule()
    public lazy var systemStatsModule = SystemStatsModule()
    public lazy var scrollReverserModule = ScrollReverserModule()
    
    public init(modules: [any CustomizerModule]? = nil) {
        if let modules { self.modules = modules }
        else { registerModules() }
    }
    
    private func registerModules() {
        self.modules = [
            menuBarModule,
            webPanelModule,
            clipboardModule,
            systemStatsModule,
            scrollReverserModule
        ]
    }
    
    public func startAllEnabled() {
        for module in modules where module.isEnabled {
            module.start()
        }
    }
    
    public func stopAll() {
        for module in modules {
            module.stop()
        }
    }
    
    public func toggleModule(id: String, enabled: Bool) {
        if let module = modules.first(where: { $0.id == id }) {
            module.isEnabled = enabled
            if enabled {
                module.start()
            } else {
                module.stop()
            }
            objectWillChange.send()
            recreateAllStatusItems()
        }
    }
    
    public func ensureAllStatusItemsVisible() {
        systemStatsModule.ensureStatusItemVisible()
        clipboardModule.updateStatusItemVisibility()
        menuBarModule.updateStatusItemVisibility()
        webPanelModule.updateStatusItemVisibility()
        scrollReverserModule.updateStatusItemVisibility()
        StatusItemController.shared.updateStatusItemVisibility()
    }
    
    public func recreateAllStatusItems() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 1. Remove all status items from menu bar
            self.systemStatsModule.removeStatusItem()
            self.scrollReverserModule.removeStatusItem()
            self.clipboardModule.removeStatusItem()
            self.webPanelModule.removeAllStatusItems()
            self.menuBarModule.removeStatusItem()
            StatusItemController.shared.removeStatusItem()
            
            // 2. Recreate from right to left (macOS inserts each new status item to the left of existing ones)
            // Far right: System Stats (CPU, RAM, GPU)
            self.systemStatsModule.setupStatusItem()
            // Next: Scroll Reverser
            self.scrollReverserModule.setupStatusItem()
            // Next: Clipboard
            self.clipboardModule.setupStatusItem()
            // Next: Web Widgets
            self.webPanelModule.recreateStatusItems()
            // Next: Menu Bar spacing quick-picker (if enabled)
            self.menuBarModule.setupStatusItem()
            // Leftmost: Main Yeoman launcher
            StatusItemController.shared.setup()
        }
    }
}
