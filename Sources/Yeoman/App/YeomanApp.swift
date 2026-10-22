import SwiftUI
import AppKit
import YeomanCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        
        // Initialize ModuleManager
        ModuleManager.shared.startAllEnabled()
        ModuleManager.shared.recreateAllStatusItems()
        
        // Show main window on launch
        DispatchQueue.main.async {
            StatusItemController.shared.openSettingsWindow()
            UpdateManager.shared.startAutoCheckIfEnabled()
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItemController.shared.openSettingsWindow()
        return true
    }
    
    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        ModuleManager.shared.stopAll()
    }
}

@main
struct YeomanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
