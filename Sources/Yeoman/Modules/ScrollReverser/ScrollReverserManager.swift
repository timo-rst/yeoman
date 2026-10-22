import AppKit
import ApplicationServices
import Combine

public final class ScrollReverserManager: ObservableObject {
    public static let shared = ScrollReverserManager()
    
    // MARK: - Preferences
    @Published public var isRunning: Bool = false
    
    @Published public var reverseMouseVertical: Bool {
        didSet { UserDefaults.standard.set(reverseMouseVertical, forKey: "sr_reverse_mouse_vertical") }
    }
    @Published public var reverseMouseHorizontal: Bool {
        didSet { UserDefaults.standard.set(reverseMouseHorizontal, forKey: "sr_reverse_mouse_horizontal") }
    }
    @Published public var reverseTrackpadVertical: Bool {
        didSet { UserDefaults.standard.set(reverseTrackpadVertical, forKey: "sr_reverse_trackpad_vertical") }
    }
    @Published public var reverseTrackpadHorizontal: Bool {
        didSet { UserDefaults.standard.set(reverseTrackpadHorizontal, forKey: "sr_reverse_trackpad_horizontal") }
    }
    @Published public var mouseStepMultiplier: Int {
        didSet { mouseStepMultiplier = min(5, max(1, mouseStepMultiplier)); UserDefaults.standard.set(mouseStepMultiplier, forKey: "sr_mouse_step_multiplier") }
    }
    
    // Live Diagnostics for User Feedback
    @Published public var hasAccessibilityPermission: Bool = false
    @Published public private(set) var permissionError: String?
    @Published public var lastEventDevice: String = "Noch keine Events empfangen"
    @Published public var lastEventSummary: String = "Warte auf Scroll-Vorgang..."
    @Published public var lastEventTimestamp: Date?
    
    // Core Event Tap handles
    private var eventTapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionCheckTimer: AnyCancellable?
    
    public init() {
        // Defaults: Reverse mouse vertical (true), leave trackpad natural (false)
        self.reverseMouseVertical = UserDefaults.standard.object(forKey: "sr_reverse_mouse_vertical") as? Bool ?? true
        self.reverseMouseHorizontal = UserDefaults.standard.object(forKey: "sr_reverse_mouse_horizontal") as? Bool ?? false
        self.reverseTrackpadVertical = UserDefaults.standard.object(forKey: "sr_reverse_trackpad_vertical") as? Bool ?? false
        self.reverseTrackpadHorizontal = UserDefaults.standard.object(forKey: "sr_reverse_trackpad_horizontal") as? Bool ?? false
        self.mouseStepMultiplier = min(5, max(1, UserDefaults.standard.object(forKey: "sr_mouse_step_multiplier") as? Int ?? 1))
        
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
        let mask = Self.eventMask
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<ScrollReverserManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleTapEvent(proxy: proxy, type: type, event: event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.eventTapPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
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
        
        if let tap = eventTapPort {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTapPort = nil
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        
        isRunning = false
    }
    
    public func reEnableTap() {
        guard lifecycle.requested, checkAccessibility() else { tearDownTap(); return }
        if let tap = eventTapPort {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in self?.reEnableTap() }
            return Unmanaged.passUnretained(event)
        }
        
        guard Self.shouldTransform(type) else {
            return Unmanaged.passUnretained(event)
        }
        
        // 1. Differentiate Mouse vs Trackpad
        // Trackpads and continuous surfaces (Magic Mouse / Magic Trackpad) report continuous == 1.
        // Traditional wheel mice report continuous == 0.
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        
        // 2. Determine inversion configuration
        let reverseV = isContinuous ? reverseTrackpadVertical : reverseMouseVertical
        let reverseH = isContinuous ? reverseTrackpadHorizontal : reverseMouseHorizontal
        let stepMultiplier = isContinuous ? 1 : min(5, max(1, mouseStepMultiplier))
        
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
        
        // 5. Update Diagnostics (throttled)
        recordDiagnosticEvent(
            isContinuous: isContinuous,
            axis1: axis1,
            axis2: axis2,
            reversedV: reverseV,
            reversedH: reverseH
        )
        
        return Unmanaged.passUnretained(event)
    }

    public static let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    public static func shouldTransform(_ type: CGEventType) -> Bool { type == .scrollWheel }
    
    private var lastDiagnosticUpdateTime: TimeInterval = 0
    
    private func recordDiagnosticEvent(isContinuous: Bool, axis1: Int64, axis2: Int64, reversedV: Bool, reversedH: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDiagnosticUpdateTime > 0.1 else { return }
        lastDiagnosticUpdateTime = now
        
        let deviceName = isContinuous ? "Trackpad (Geste / Kontinuierlich)" : "Maus (Mausrad / Diskret)"
        var summary = ""
        if axis1 != 0 {
            summary = "Vertikal: \(axis1) \(reversedV ? "→ Umgekehrt 🔄" : "→ Nativ")"
        } else if axis2 != 0 {
            summary = "Horizontal: \(axis2) \(reversedH ? "→ Umgekehrt 🔄" : "→ Nativ")"
        }
        
        DispatchQueue.main.async {
            self.lastEventDevice = deviceName
            self.lastEventSummary = summary
            self.lastEventTimestamp = Date()
        }
    }
}
