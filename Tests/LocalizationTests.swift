import Foundation
import YeomanCore

func runLocalizationTests() {
    let harness = TestHarness.shared
    
    harness.runSuite("Localization Tests") {
        harness.test("AppLanguage covers all required locales") {
            let supported = AppLanguage.allCases.map { $0.rawValue }
            assertTrue(supported.contains("en"), "Must support English")
            assertTrue(supported.contains("de"), "Must support German")
            assertTrue(supported.contains("es"), "Must support Spanish")
            assertTrue(supported.contains("fr"), "Must support French")
        }
        
        harness.test("Essential localization keys exist in German and English") {
            let manager = LocalizationManager(defaults: isolatedDefaults())
            
            let essentialKeys = [
                "menu.settings",
                "menu.quit",
                "menu.check_updates",
                "menu.clipboard_recent",
                "menu.clear_all",
                "general.clipboard_title",
                "general.scroll_reverser_title",
                "general.web_panel_title",
                "general.system_stats_title",
                "updates.title",
                "updates.auto_check"
            ]
            
            for key in essentialKeys {
                let deText = manager.localized(key, for: .german)
                assertTrue(!deText.isEmpty && deText != key, "German translation missing or empty for key: \(key)")
                
                let enText = manager.localized(key, for: .english)
                assertTrue(!enText.isEmpty && enText != key, "English translation missing or empty for key: \(key)")
            }
        }
        
        harness.test("Localization returns key itself if key is missing without crashing") {
            let manager = LocalizationManager(defaults: isolatedDefaults())
            let nonexistentKey = "nonexistent.key.12345"
            let result = manager.localized(nonexistentKey, for: .english)
            assertEqual(result, nonexistentKey, "Missing key should fallback to key identifier")
        }
    }
}
