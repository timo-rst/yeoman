import SwiftUI
import AppKit

public final class ClipboardModule: CustomizerModule, ObservableObject {
    public let id = "clipboard_manager"
    public let name = "Clipboard Manager (Clippy)"
    public let description = "Lückenloser Verlauf der Zwischenablage mit Schnellsuche, Favoriten und Passwortschutz."
    public let iconName = "doc.on.clipboard"
    public let category = ModuleCategory.clipboard
    
    @Published public var isEnabled: Bool = true
    
    public init() {}
    
    public func start() {
        ClipboardMonitor.shared.start()
    }
    
    public func stop() {
        ClipboardMonitor.shared.stop()
    }
    
    public func settingsView() -> AnyView {
        AnyView(ClipboardSettingsView())
    }
}
