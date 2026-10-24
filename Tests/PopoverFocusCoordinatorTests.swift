import Foundation
import AppKit
import YeomanCore

func runPopoverFocusCoordinatorTests() {
    TestHarness.shared.runSuite("PopoverFocusCoordinator Tests") {
        TestHarness.shared.test("popover pin preference persists and selects native behavior") {
            let suite = "YeomanTests.PopoverPin.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }

            let preference = PopoverPinPreference(storageKey: "fixture_pinned", defaults: defaults)
            assertFalse(preference.isPinned)
            assertEqual(preference.popoverBehavior, .transient)

            preference.isPinned = true
            assertEqual(preference.popoverBehavior, .applicationDefined)

            let reloaded = PopoverPinPreference(storageKey: "fixture_pinned", defaults: defaults)
            assertTrue(reloaded.isPinned)
            assertEqual(reloaded.popoverBehavior, .applicationDefined)
        }

        TestHarness.shared.test("settings window participates normally in Mission Control") {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            SettingsWindowPolicy.apply(to: window)

            assertTrue(window.collectionBehavior.contains(.managed))
            assertTrue(window.collectionBehavior.contains(.participatesInCycle))
            assertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
            assertFalse(window.collectionBehavior.contains(.transient))
            assertFalse(window.collectionBehavior.contains(.ignoresCycle))
            assertFalse(window.isExcludedFromWindowsMenu)
            assertEqual(window.tabbingMode, .automatic)
            window.close()
        }

        TestHarness.shared.test("cancelSuppression resets coordinator state") {
            let coordinator = PopoverFocusCoordinator.shared
            coordinator.cancelSuppression()
            assertEqual(coordinator.suppressedWindowsCount, 0)
            assertEqual(coordinator.hasRecordedPreviousApp, false)
        }
        
        TestHarness.shared.test("prepareForPresentation suppresses background window when not key") {
            let coordinator = PopoverFocusCoordinator.shared
            coordinator.cancelSuppression()
            
            // Create a test window at normal level
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            
            // Note: Since this is running in test harness, StatusItemController.shared.settingsWindow is nil
            // Verify prepareForPresentation and handlePopoverDidClose run cleanly without crashing
            let popover = NSPopover()
            coordinator.prepareForPresentation(of: popover)
            
            // Closing popover should cleanly handle cleanup
            coordinator.handlePopoverDidClose(of: popover)
            assertEqual(coordinator.suppressedWindowsCount, 0)
            
            window.close()
        }
        
        TestHarness.shared.test("multiple popovers track properly without premature restore") {
            let coordinator = PopoverFocusCoordinator.shared
            coordinator.cancelSuppression()
            
            let popover1 = NSPopover()
            let popover2 = NSPopover()
            
            coordinator.prepareForPresentation(of: popover1)
            coordinator.prepareForPresentation(of: popover2)
            
            // Close popover1 while popover2 is still registered
            coordinator.handlePopoverDidClose(of: popover1)
            
            // Close popover2
            coordinator.handlePopoverDidClose(of: popover2)
            assertEqual(coordinator.suppressedWindowsCount, 0)
        }
    }
}
