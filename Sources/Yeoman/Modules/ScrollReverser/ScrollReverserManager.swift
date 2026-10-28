import AppKit
import ApplicationServices
import Combine

private final class ScrollEventTapWorker {
    typealias Handler = (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    private let handler: Handler
    private let stateLock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let stopped = DispatchSemaphore(value: 0)

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start(mask: CGEventMask) -> Bool {
        let thread = Thread { [self] in
            let callback: CGEventTapCallBack = { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let worker = Unmanaged<ScrollEventTapWorker>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    worker.enableTap()
                    return Unmanaged.passUnretained(event)
                }
                return worker.handler(proxy, type, event)
            }
            guard let createdTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                // Let macOS finish its own acceleration and momentum processing
                // before Yeoman applies the final per-device direction change.
                place: ScrollReverserManager.tapPlacement,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                ready.signal()
                stopped.signal()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
            let workerRunLoop = CFRunLoopGetCurrent()
            stateLock.lock()
            tap = createdTap
            runLoop = workerRunLoop
            stateLock.unlock()
            CFRunLoopAddSource(workerRunLoop, source, .commonModes)
            CGEvent.tapEnable(tap: createdTap, enable: true)
            ready.signal()
            CFRunLoopRun()
            CGEvent.tapEnable(tap: createdTap, enable: false)
            CFMachPortInvalidate(createdTap)
            CFRunLoopRemoveSource(workerRunLoop, source, .commonModes)
            stateLock.lock()
            tap = nil
            runLoop = nil
            stateLock.unlock()
            stopped.signal()
        }
        thread.name = "de.trst.Yeoman.scroll-event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        guard ready.wait(timeout: .now() + 2) == .success else { return false }
        stateLock.lock()
        let installed = tap != nil
        stateLock.unlock()
        return installed
    }

    func stop() {
        stateLock.lock()
        let workerRunLoop = runLoop
        stateLock.unlock()
        guard let workerRunLoop else { return }
        CFRunLoopStop(workerRunLoop)
        CFRunLoopWakeUp(workerRunLoop)
        _ = stopped.wait(timeout: .now() + 2)
    }

    private func enableTap() {
        stateLock.lock()
        let currentTap = tap
        stateLock.unlock()
        if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
    }
}

public final class ScrollReverserManager: ObservableObject {
    public static let shared = ScrollReverserManager()

    // MARK: - Preferences
    @Published public var isRunning: Bool = false
    
    @Published public var reverseMouseVertical: Bool {
        didSet { updateConfiguration(); UserDefaults.standard.set(reverseMouseVertical, forKey: "sr_reverse_mouse_vertical") }
    }
    @Published public var reverseMouseHorizontal: Bool {
        didSet { updateConfiguration(); UserDefaults.standard.set(reverseMouseHorizontal, forKey: "sr_reverse_mouse_horizontal") }
    }
    @Published public var reverseTrackpadVertical: Bool {
        didSet { updateConfiguration(); UserDefaults.standard.set(reverseTrackpadVertical, forKey: "sr_reverse_trackpad_vertical") }
    }
    @Published public var reverseTrackpadHorizontal: Bool {
        didSet { updateConfiguration(); UserDefaults.standard.set(reverseTrackpadHorizontal, forKey: "sr_reverse_trackpad_horizontal") }
    }
    @Published public var mouseStepMultiplier: Int {
        didSet { mouseStepMultiplier = min(5, max(1, mouseStepMultiplier)); updateConfiguration(); UserDefaults.standard.set(mouseStepMultiplier, forKey: "sr_mouse_step_multiplier") }
    }
    
    // Live Diagnostics for User Feedback
    @Published public var hasAccessibilityPermission: Bool = false
    @Published public private(set) var permissionError: String?
    private struct ScrollConfiguration {
        var reverseMouseVertical = true
        var reverseMouseHorizontal = false
        var reverseTrackpadVertical = false
        var reverseTrackpadHorizontal = false
        var mouseStepMultiplier = 1
    }
    private let configurationLock = NSLock()
    private var configuration = ScrollConfiguration()
    private var tapWorker: ScrollEventTapWorker?
    private var permissionCheckTimer: AnyCancellable?
    
    public init() {
        // Defaults: Reverse mouse vertical (true), leave trackpad natural (false)
        self.reverseMouseVertical = UserDefaults.standard.object(forKey: "sr_reverse_mouse_vertical") as? Bool ?? true
        self.reverseMouseHorizontal = UserDefaults.standard.object(forKey: "sr_reverse_mouse_horizontal") as? Bool ?? false
        self.reverseTrackpadVertical = UserDefaults.standard.object(forKey: "sr_reverse_trackpad_vertical") as? Bool ?? false
        self.reverseTrackpadHorizontal = UserDefaults.standard.object(forKey: "sr_reverse_trackpad_horizontal") as? Bool ?? false
        self.mouseStepMultiplier = min(5, max(1, UserDefaults.standard.object(forKey: "sr_mouse_step_multiplier") as? Int ?? 1))
        updateConfiguration()
        
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivated), name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func applicationActivated() { if lifecycle.requested { reconcilePermission() } }
    private let lifecycle = TapLifecycle()
    private func reconcilePermission() {
        precondition(Thread.isMainThread)
        let permission = AXIsProcessTrusted()
        hasAccessibilityPermission = permission
        lifecycle.reconcile(permission: permission, create: { self.installTap() }, destroy: { self.tearDownTap() })
        isRunning = lifecycle.running
    }

    // MARK: - Accessibility
    
    @discardableResult
    public func checkAccessibility(prompt: Bool = false) -> Bool {
        let trusted: Bool
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }
        
        hasAccessibilityPermission = trusted
        if !trusted {
            lifecycle.reconcile(permission: false, create: { false }, destroy: { self.tearDownTap() })
            isRunning = lifecycle.running
        }
        return trusted
    }
    
    public func openAccessibilitySettings() {
        checkAccessibility(prompt: true)
        startPermissionPolling()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func resetTCCPermission() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var failure: Error?
            for bundleId in ["de.trst.Yeoman", "de.trst.MacCustomizer"] {
                do {
                    let result = try BoundedProcess.run("/usr/bin/tccutil", ["reset", "Accessibility", bundleId], timeout: 5, limit: 16_384)
                    guard result.status == 0 else { throw SecurityFailure.rejected("TCC-Berechtigung konnte nicht zurückgesetzt werden.") }
                } catch { failure = failure ?? error }
            }
            let errorMessage = failure?.localizedDescription
            DispatchQueue.main.async {
                self?.permissionError = errorMessage
                self?.checkAccessibility(prompt: true)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    // MARK: - Event Tap Lifecycle
    
    public func start() {
        precondition(Thread.isMainThread)
        lifecycle.requested = true
        startPermissionPolling()
        reconcilePermission()
    }
    private func installTap() -> Bool {
        let worker = ScrollEventTapWorker { [weak self] proxy, type, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return self.handleTapEvent(proxy: proxy, type: type, event: event)
        }
        guard worker.start(mask: Self.eventMask) else { return false }
        tapWorker = worker
        return true
    }
    
    public func stop() {
        precondition(Thread.isMainThread)
        lifecycle.requested = false
        stopPermissionPolling()
        lifecycle.reconcile(permission: hasAccessibilityPermission, create: { false }, destroy: { self.tearDownTap() })
        isRunning = lifecycle.running
    }
    private func tearDownTap() {
        tapWorker?.stop()
        tapWorker = nil
        isRunning = false
    }
    
    public func startPermissionPolling() {
        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.reconcilePermission()
        }
    }

    public func stopPermissionPolling() {
        permissionCheckTimer?.cancel()
        permissionCheckTimer = nil
    }
    
    // MARK: - Event Processing Logic
    
    private func handleTapEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard Self.shouldTransform(type) else {
            return Unmanaged.passUnretained(event)
        }
        
        // 1. Differentiate Mouse vs Trackpad
        // Trackpads and continuous surfaces (Magic Mouse / Magic Trackpad) report continuous == 1.
        // Traditional wheel mice report continuous == 0.
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let configuration = configurationSnapshot()

        // A passive device must stay on the shortest possible path. In particular,
        // do not inspect more deltas or enqueue diagnostics for native trackpad
        // scrolling: the event tap is synchronous and extra callback work can make
        // rapid direction changes feel delayed.
        guard Self.requiresMutation(
            isContinuous: isContinuous,
            reverseMouseVertical: configuration.reverseMouseVertical,
            reverseMouseHorizontal: configuration.reverseMouseHorizontal,
            reverseTrackpadVertical: configuration.reverseTrackpadVertical,
            reverseTrackpadHorizontal: configuration.reverseTrackpadHorizontal,
            mouseStepMultiplier: configuration.mouseStepMultiplier
        ) else {
            return Unmanaged.passUnretained(event)
        }
        
        // 2. Determine inversion configuration
        let reverseV = isContinuous ? configuration.reverseTrackpadVertical : configuration.reverseMouseVertical
        let reverseH = isContinuous ? configuration.reverseTrackpadHorizontal : configuration.reverseMouseHorizontal
        let stepMultiplier = isContinuous ? 1 : configuration.mouseStepMultiplier
        
        let vmul = reverseV ? -stepMultiplier : stepMultiplier
        let hmul = reverseH ? -stepMultiplier : stepMultiplier
        
        // 3. Read current deltas
        let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let fixedPtAxis1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixedPtAxis2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        
        guard let vertical = SecurityPolicy.multiply(axis1, by: vmul),
              let horizontal = SecurityPolicy.multiply(axis2, by: hmul),
              let verticalPoint = SecurityPolicy.multiply(pointAxis1, by: vmul),
              let horizontalPoint = SecurityPolicy.multiply(pointAxis2, by: hmul),
              (fixedPtAxis1 * Double(vmul)).isFinite,
              (fixedPtAxis2 * Double(hmul)).isFinite else { return Unmanaged.passUnretained(event) }

        // 4. Invert axes if required
        // Note: setting DeltaAxis first causes macOS to recompute
        // PointDeltaAxis internally, so we set DeltaAxis first, then restore the multiplied Point and FixedPt deltas.
        if vmul != 1 {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: vertical)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixedPtAxis1 * Double(vmul))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: verticalPoint)
        }
        
        if hmul != 1 {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: horizontal)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedPtAxis2 * Double(hmul))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: horizontalPoint)
        }
        
        return Unmanaged.passUnretained(event)
    }

    public static let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    public static let tapPlacement = CGEventTapPlacement.tailAppendEventTap
    public static func shouldTransform(_ type: CGEventType) -> Bool { type == .scrollWheel }

    public static func requiresMutation(
        isContinuous: Bool,
        reverseMouseVertical: Bool,
        reverseMouseHorizontal: Bool,
        reverseTrackpadVertical: Bool,
        reverseTrackpadHorizontal: Bool,
        mouseStepMultiplier: Int
    ) -> Bool {
        if isContinuous {
            return reverseTrackpadVertical || reverseTrackpadHorizontal
        }
        return reverseMouseVertical || reverseMouseHorizontal || mouseStepMultiplier != 1
    }

    private func updateConfiguration() {
        configurationLock.lock()
        configuration = ScrollConfiguration(
            reverseMouseVertical: reverseMouseVertical,
            reverseMouseHorizontal: reverseMouseHorizontal,
            reverseTrackpadVertical: reverseTrackpadVertical,
            reverseTrackpadHorizontal: reverseTrackpadHorizontal,
            mouseStepMultiplier: min(5, max(1, mouseStepMultiplier))
        )
        configurationLock.unlock()
    }

    private func configurationSnapshot() -> ScrollConfiguration {
        configurationLock.lock()
        let snapshot = configuration
        configurationLock.unlock()
        return snapshot
    }
}
