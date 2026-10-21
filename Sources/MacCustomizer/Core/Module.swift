import SwiftUI

public enum ModuleCategory: String, CaseIterable, Codable {
    case menuBar = "Menu Bar"
    case clipboard = "Clipboard"
    case system = "System"
    case windowManagement = "Window Management"
    case productivity = "Productivity"
}

public protocol CustomizerModule: AnyObject {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var iconName: String { get }
    var category: ModuleCategory { get }
    var isEnabled: Bool { get set }
    
    func start()
    func stop()
    
    @ViewBuilder
    func settingsView() -> AnyView
}
