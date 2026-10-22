import Foundation
import SwiftUI
import YeomanCore

private final class TestModule: CustomizerModule {
    let id = "test-module"
    let name = "Test"
    let moduleDescription = "Isolated registration"
    let iconName = "circle"
    let category = ModuleCategory.productivity
    var isEnabled = false
    var showsDedicatedStatusItem = false
    var starts = 0
    var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func settingsView() -> AnyView { AnyView(EmptyView()) }
}
func runModuleManagerTests() {
    TestHarness.shared.runSuite("Isolated ModuleManager") {
        TestHarness.shared.test("Injected modules do not construct production modules") {
            let module = TestModule()
            let manager = ModuleManager(modules: [module])
            assertEqual(manager.modules.count, 1)
            assertEqual(manager.modules.first?.id, module.id)
            manager.startAllEnabled()
            assertEqual(module.starts, 0)
            module.isEnabled = true
            manager.startAllEnabled()
            assertEqual(module.starts, 1)
            manager.stopAll()
            assertEqual(module.stops, 1)
        }
    }
}
