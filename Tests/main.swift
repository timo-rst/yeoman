import Foundation

print("💂 Yeoman Native Test Suite")
print("===========================")

runUpdateManagerTests()
runClipboardTests()
runWebPanelTests()
runLocalizationTests()
runModuleManagerTests()
runSecurityTests()
runPopoverFocusCoordinatorTests()
removeTestDefaults()

let exitCode = TestHarness.shared.printSummary()
exit(exitCode)
