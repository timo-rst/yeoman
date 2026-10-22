import Foundation
import YeomanCore

func runModuleManagerTests() {
    let harness = TestHarness.shared
    
    harness.runSuite("ModuleManager Tests") {
        harness.test("ModuleManager registers all 5 core modules") {
            let manager = ModuleManager.shared
            let moduleIds = manager.modules.map { $0.id }
            
            assertTrue(moduleIds.contains("menu_bar_optimizer"), "MenuBar module must be registered")
            assertTrue(moduleIds.contains("web_panel"), "WebPanel module must be registered")
            assertTrue(moduleIds.contains("clipboard_manager"), "Clipboard module must be registered")
            assertTrue(moduleIds.contains("system_stats"), "SystemStats module must be registered")
            assertTrue(moduleIds.contains("scroll_reverser"), "ScrollReverser module must be registered")
        }
        
        harness.test("Modules have valid non-empty metadata") {
            let manager = ModuleManager.shared
            for module in manager.modules {
                assertTrue(!module.id.isEmpty, "Module id should not be empty")
                assertTrue(!module.name.isEmpty, "Module name should not be empty")
                assertTrue(!module.moduleDescription.isEmpty, "Module description should not be empty")
                assertTrue(!module.iconName.isEmpty, "Module icon should not be empty")
            }
        }
    }
}
