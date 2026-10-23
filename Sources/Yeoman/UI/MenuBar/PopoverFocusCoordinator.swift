import AppKit

/// Coordinates window focus and visibility when presenting menu bar popovers or accessory panels.
/// When Yeoman's main/settings window is open in the background (not key), activating Yeoman
/// would normally cause macOS WindowServer to elevate all normal-level windows in front of the
/// user's active application. This coordinator temporarily hides background windows and restores
/// them seamlessly behind the user's active application once the popover is dismissed.
public final class PopoverFocusCoordinator {
    public static let shared = PopoverFocusCoordinator()
    
    private var previousApp: NSRunningApplication?
    private var temporarilyHiddenWindows: [NSWindow] = []
    private var activePopovers = NSHashTable<NSPopover>.weakObjects()
    private var restoreWorkItem: DispatchWorkItem?
    
    private init() {}
    
    /// Prepares focus and suppresses background windows before presenting a popover.
    public func prepareForPresentation(of popover: NSPopover? = nil) {
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
        
        if let popover = popover {
            activePopovers.add(popover)
        }
        
        // 1. Capture the frontmost application if it's not Yeoman itself
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            if self.previousApp == nil {
                self.previousApp = front
            }
        }
        
        // 2. Identify all normal-level Yeoman windows currently visible in the background
        let candidateWindows = [
            StatusItemController.shared.settingsWindow,
            StatusItemController.shared.clipboardWindow
        ].compactMap { $0 }.filter { window in
            window.isVisible && !window.isKeyWindow && !window.isMiniaturized && window.level == .normal
        }
        
        for window in candidateWindows {
            if !temporarilyHiddenWindows.contains(window) {
                temporarilyHiddenWindows.append(window)
                window.orderOut(nil)
            }
        }
    }
    
    /// Called when a popover closes. Restores focus to the previous app and orders suppressed windows back in.
    public func handlePopoverDidClose(of popover: NSPopover? = nil) {
        if let popover = popover {
            activePopovers.remove(popover)
        }
        
        // If other popovers are still currently shown, defer restoration
        let stillShown = activePopovers.allObjects.filter { $0.isShown }
        guard stillShown.isEmpty else { return }
        
        guard previousApp != nil || !temporarilyHiddenWindows.isEmpty else { return }
        
        let appToRestore = self.previousApp
        let windowsToRestore = self.temporarilyHiddenWindows
        self.previousApp = nil
        self.temporarilyHiddenWindows.removeAll()
        
        restoreWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Check if any popover was re-opened in the meantime
            let currentShown = self.activePopovers.allObjects.filter { $0.isShown }
            guard currentShown.isEmpty else { return }
            
            // 1. Restore application focus
            if let currentFront = NSWorkspace.shared.frontmostApplication,
               currentFront.bundleIdentifier != Bundle.main.bundleIdentifier {
                if #available(macOS 14.0, *) {
                    currentFront.activate()
                } else {
                    currentFront.activate(options: [.activateIgnoringOtherApps])
                }
            } else if let app = appToRestore, !app.isTerminated {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
            } else {
                NSApp.deactivate()
            }
            
            // 2. If windows were temporarily hidden, restore them behind the user's active app
            if !windowsToRestore.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard self.activePopovers.allObjects.filter({ $0.isShown }).isEmpty else { return }
                    for window in windowsToRestore {
                        if !window.isVisible {
                            window.orderBack(nil)
                        }
                    }
                }
            }
        }
        
        restoreWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }
    
    /// Cancels suppression when the user explicitly requests to bring a window (e.g. Settings) to the foreground.
    public func cancelSuppression() {
        temporarilyHiddenWindows.removeAll()
        previousApp = nil
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
    }
    
    /// Internal / test inspection accessors
    public var suppressedWindowsCount: Int {
        temporarilyHiddenWindows.count
    }
    
    public var hasRecordedPreviousApp: Bool {
        previousApp != nil
    }
}
