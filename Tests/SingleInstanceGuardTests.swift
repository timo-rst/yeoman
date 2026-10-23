import Foundation
import YeomanCore

func runSingleInstanceGuardTests() {
    TestHarness.shared.runSuite("SingleInstanceGuard Tests") {
        TestHarness.shared.test("acquireOrActivateExisting prevents duplicate instances via kernel lock") {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("yeoman_test_lock_\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                SingleInstanceGuard.releaseLockForTesting()
                try? FileManager.default.removeItem(at: tempDir)
            }
            
            // First instance acquires lock successfully
            let firstResult = SingleInstanceGuard.acquireOrActivateExisting(
                bundleIdentifier: "de.trst.Yeoman.test.\(UUID().uuidString)",
                lockDirectory: tempDir
            )
            assertEqual(firstResult, true, "First instance must successfully acquire lock")
            
            // Duplicate instance attempt must fail
            let secondResult = SingleInstanceGuard.acquireOrActivateExisting(
                bundleIdentifier: "de.trst.Yeoman.test.\(UUID().uuidString)",
                lockDirectory: tempDir
            )
            assertEqual(secondResult, false, "Second instance must be rejected")
            
            // Releasing lock allows another instance to acquire
            SingleInstanceGuard.releaseLockForTesting()
            let thirdResult = SingleInstanceGuard.acquireOrActivateExisting(
                bundleIdentifier: "de.trst.Yeoman.test.\(UUID().uuidString)",
                lockDirectory: tempDir
            )
            assertEqual(thirdResult, true, "Subsequent instance must succeed after release")
            SingleInstanceGuard.releaseLockForTesting()
        }
    }
}
