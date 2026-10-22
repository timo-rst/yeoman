import Foundation

public final class TestHarness {
    public static let shared = TestHarness()
    
    public private(set) var passedCount = 0
    public private(set) var failedCount = 0
    private var currentSuiteName = ""
    private var currentTestName = ""
    private var currentTestFailed = false
    
    private init() {}
    
    public func runSuite(_ name: String, block: () -> Void) {
        currentSuiteName = name
        print("\n\u{001B}[1;36m=== Test Suite: \(name) ===\u{001B}[0m")
        block()
    }
    
    public func test(_ name: String, block: () throws -> Void) {
        currentTestName = name
        currentTestFailed = false
        
        do {
            try block()
            if !currentTestFailed {
                passedCount += 1
                print("  \u{001B}[32m✓\u{001B}[0m \(name)")
            }
        } catch {
            recordFailure("Threw unexpected error: \(error)", file: #file, line: #line)
        }
    }
    
    public func recordFailure(_ message: String, file: String, line: Int) {
        if !currentTestFailed {
            failedCount += 1
            currentTestFailed = true
        }
        let fileName = (file as NSString).lastPathComponent
        print("  \u{001B}[31m✗\u{001B}[0m \(currentTestName)")
        print("    \u{001B}[31mError:\u{001B}[0m \(message) [\(fileName):\(line)]")
    }
    
    public func printSummary() -> Int32 {
        let total = passedCount + failedCount
        print("\n------------------------------------------------------------")
        if failedCount == 0 {
            print("\u{001B}[1;32mALL TESTS PASSED!\u{001B}[0m (\(passedCount)/\(total) passed)")
            print("------------------------------------------------------------\n")
            return 0
        } else {
            print("\u{001B}[1;31mTEST SUITE FAILED:\u{001B}[0m \(failedCount) of \(total) tests failed.")
            print("------------------------------------------------------------\n")
            return 1
        }
    }
}

public func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual != expected {
        let msg = message.isEmpty ? "Expected \(expected), but got \(actual)" : "\(message) (Expected \(expected), got \(actual))"
        TestHarness.shared.recordFailure(msg, file: file, line: line)
    }
}

public func assertTrue(_ condition: Bool, _ message: String = "Expected condition to be true", file: String = #file, line: Int = #line) {
    if !condition {
        TestHarness.shared.recordFailure(message, file: file, line: line)
    }
}

public func assertFalse(_ condition: Bool, _ message: String = "Expected condition to be false", file: String = #file, line: Int = #line) {
    if condition {
        TestHarness.shared.recordFailure(message, file: file, line: line)
    }
}

public func assertNotNil<T>(_ value: T?, _ message: String = "Expected value not to be nil", file: String = #file, line: Int = #line) {
    if value == nil {
        TestHarness.shared.recordFailure(message, file: file, line: line)
    }
}

public func assertNil<T>(_ value: T?, _ message: String = "Expected value to be nil", file: String = #file, line: Int = #line) {
    if value != nil {
        TestHarness.shared.recordFailure(message, file: file, line: line)
    }
}
