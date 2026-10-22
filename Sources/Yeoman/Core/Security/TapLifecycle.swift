import Foundation

/// Pure state machine; adapters own real TCC and CGEventTap calls.
public final class TapLifecycle {
    public var requested = false
    public private(set) var running = false
    public init() {}
    public func reconcile(permission: Bool, create: () -> Bool, destroy: () -> Void) {
        guard requested && permission else {
            if running { destroy() }
            running = false
            return
        }
        if !running { running = create() }
    }
}

public final class SingleFlight {
    private let lock = NSLock()
    private var busy = false
    public init() {}
    public func begin() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !busy else { return false }
        busy = true; return true
    }
    public func end() { lock.lock(); busy = false; lock.unlock() }
}
