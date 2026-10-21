import SwiftUI

public final class MenuBarModule: CustomizerModule, ObservableObject {
    public let id = "menu_bar_optimizer"
    public let name = "Menüleisten-Optimizer"
    public let description = "Kompaktere Symbole (wie Ice), anpassbarer Abstand und Multi-Monitor-Unterstützung."
    public let iconName = "menubar.rectangle"
    public let category = ModuleCategory.menuBar
    
    @Published public var isEnabled: Bool = true
    
    public init() {}
    
    public func start() {
        // Initialize preferences and ensure observer is active
        _ = MenuBarSpacingManager.shared
        _ = DisplayManager.shared
    }
    
    public func stop() {
        // Module stopped
    }
    
    public func settingsView() -> AnyView {
        AnyView(MenuBarSettingsView())
    }
}
