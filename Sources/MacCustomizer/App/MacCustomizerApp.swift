import SwiftUI
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        
        // Initialize DisplayManager and ModuleManager
        _ = DisplayManager.shared
        ModuleManager.shared.startAllEnabled()
        
        // Create Status Item in Menu Bar
        StatusItemController.shared.setup()
        
        // Show main window on launch
        DispatchQueue.main.async {
            StatusItemController.shared.openSettingsWindow()
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItemController.shared.openSettingsWindow()
        return true
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
