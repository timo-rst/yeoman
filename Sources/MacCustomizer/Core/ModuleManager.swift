import SwiftUI
import Combine

public final class ModuleManager: ObservableObject {
    public static let shared = ModuleManager()
    
    @Published public private(set) var modules: [any CustomizerModule] = []
    
    public let menuBarModule = MenuBarModule()
    public let webPanelModule = WebPanelModule()
    public let clipboardModule = ClipboardModule()
    public let systemStatsModule = SystemStatsModule()
    
    public init() {
        registerModules()
    }
    
    private func registerModules() {
        self.modules = [
            menuBarModule,
            webPanelModule,
            clipboardModule,
            systemStatsModule
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
        }
    }
    
    public func ensureAllStatusItemsVisible() {
        systemStatsModule.ensureStatusItemVisible()
        clipboardModule.updateStatusItemVisibility()
        menuBarModule.updateStatusItemVisibility()
        webPanelModule.updateStatusItemVisibility()
        StatusItemController.shared.updateStatusItemVisibility()
    }
}
