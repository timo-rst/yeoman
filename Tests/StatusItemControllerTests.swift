import AppKit
import Foundation
import YeomanCore

func runStatusItemControllerTests() {
    TestHarness.shared.runSuite("StatusItemController Tests") {
        TestHarness.shared.test("general menu bar menu contains only core Yeoman actions and no module submenus") {
            let controller = StatusItemController()
            let menu = controller.buildMainMenu()

            assertTrue(menu.items.allSatisfy { $0.submenu == nil })

            let nonSeparatorTitles = menu.items
                .filter { !$0.isSeparatorItem }
                .map(\.title)
            assertEqual(
                nonSeparatorTitles,
                ["Yeoman", l10n("menu.settings"), l10n("menu.check_updates"), l10n("menu.quit")]
            )

            assertFalse(nonSeparatorTitles.contains("Menüleisten-Abstand"))
            assertFalse(nonSeparatorTitles.contains(l10n("menu.clipboard_recent")))

            let actionItems = menu.items.filter { !$0.isSeparatorItem }
            assertFalse(actionItems[0].isEnabled)
            assertEqual(actionItems[1].keyEquivalent, ",")
            assertTrue(actionItems[1].action == #selector(StatusItemController.openSettingsWindow))
            assertEqual(actionItems[3].keyEquivalent, "q")
        }
    }
}
