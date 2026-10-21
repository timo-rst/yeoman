import SwiftUI
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure as accessory application (menu bar utility without Dock icon clutter)
        let showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        
        // Initialize DisplayManager and ModuleManager
        _ = DisplayManager.shared
        ModuleManager.shared.startAllEnabled()
        
        // Create Status Item in Menu Bar
        StatusItemController.shared.setup()
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        ModuleManager.shared.stopAll()
    }
}

@main
struct MacCustomizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
