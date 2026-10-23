import SwiftUI
import AppKit
import YeomanCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationWillFinishLaunching(_ notification: Notification) {
        guard SingleInstanceGuard.acquireOrActivateExisting() else {
            NSApp.terminate(nil)
            exit(0)
        }
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleReopenNotification),
            name: SingleInstanceGuard.reopenNotificationName,
            object: nil
        )
    }
    
    @objc private func handleReopenNotification() {
        DispatchQueue.main.async {
            StatusItemController.shared.openSettingsWindow()
        }
    }
    
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
        DistributedNotificationCenter.default().removeObserver(self)
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
