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
runStatusItemControllerTests()
runSingleInstanceGuardTests()
runSystemStatsTests()
runFinderCutTests()
runTerminalSaverTests()
removeTestDefaults()

let exitCode = TestHarness.shared.printSummary()
exit(exitCode)
