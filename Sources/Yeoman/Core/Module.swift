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
    var moduleDescription: String { get }
    var iconName: String { get }
    var category: ModuleCategory { get }
    var isEnabled: Bool { get set }
    var showsDedicatedStatusItem: Bool { get set }
    
    func start()
    func stop()
    func updateStatusItemVisibility()
    
    @ViewBuilder
    func settingsView() -> AnyView
}

extension CustomizerModule {
    public func updateStatusItemVisibility() {}
}
