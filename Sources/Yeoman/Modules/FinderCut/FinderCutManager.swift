import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

public enum FinderCutShortcut: Equatable {
    case cut
    case copy
    case paste
    case escape
    case other
}

public enum FinderCutAction: Equatable {
    case passThrough
    case transformCutToCopy
    case transformPasteToMove
    case clearCutAndPassThrough
}

public struct FinderCutState: Equatable {
    public var isCutPending: Bool = false
    public var awaitingPasteboardConfirmation: Bool = false
    public var confirmedChangeCount: Int? = nil
    public var cutStartedAt: Date? = nil
    public var cutItemCount: Int = 0

    public init(
        isCutPending: Bool = false,
        awaitingPasteboardConfirmation: Bool = false,
        confirmedChangeCount: Int? = nil,
        cutStartedAt: Date? = nil,
        cutItemCount: Int = 0
    ) {
        self.isCutPending = isCutPending
        self.awaitingPasteboardConfirmation = awaitingPasteboardConfirmation
        self.confirmedChangeCount = confirmedChangeCount
        self.cutStartedAt = cutStartedAt
        self.cutItemCount = cutItemCount
    }

    public mutating func clear() {
        isCutPending = false
        awaitingPasteboardConfirmation = false
        confirmedChangeCount = nil
        cutStartedAt = nil
        cutItemCount = 0
    }
}

public enum FinderCutDecisionEngine {
    public static let finderBundleIdentifier = "com.apple.finder"
    public static let confirmationGraceInterval: TimeInterval = 1.0
    public static let textInputRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXComboBox",
        "AXWebArea"
    ]

    public static func isTextInputElement(role: String?, subrole: String?) -> Bool {
        if let role, textInputRoles.contains(role) {
            return true
        }
        return subrole == "AXSearchField"
    }

    public static func classifyShortcut(
        keyCode: Int64,
        unicodeCharacter: String?,
        flags: CGEventFlags,
        cutKeyCode: Int64 = 7,
        copyKeyCode: Int64 = 8,
        pasteKeyCode: Int64 = 9
    ) -> FinderCutShortcut {
        let relevantMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let modifiers = flags.intersection(relevantMask)

        if modifiers.isEmpty && keyCode == 53 {
            return .escape
        }

        guard modifiers == .maskCommand else {
            return .other
        }

        if let char = unicodeCharacter?.lowercased(), !char.isEmpty {
            if char == "x" { return .cut }
            if char == "c" { return .copy }
            if char == "v" { return .paste }
        }

        if keyCode == cutKeyCode { return .cut }
        if keyCode == copyKeyCode { return .copy }
        if keyCode == pasteKeyCode { return .paste }
        return .other
    }

    public static func matchesFinderMenuItem(
        cmdChar: String?,
        modifiers: Int?,
        targetChar: String,
        targetModifiers: Int
    ) -> Bool {
        guard let cmdChar = cmdChar?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cmdChar.isEmpty else {
            return false
        }
        return cmdChar.uppercased() == targetChar.uppercased() && (modifiers ?? 0) == targetModifiers
    }

    public static func decide(
        eventType: CGEventType,
        isFinderFrontmost: Bool,
        isAutorepeat: Bool,
        isSynthetic: Bool,
        shortcut: FinderCutShortcut,
        isEditingTextInFinder: Bool,
        cancelOnEscape: Bool,
        state: inout FinderCutState,
        now: Date = Date(),
        currentChangeCount: Int? = nil
    ) -> FinderCutAction {
        guard eventType == .keyDown,
              isFinderFrontmost,
              !isAutorepeat,
              !isSynthetic,
              !isEditingTextInFinder else {
            return .passThrough
        }

        switch shortcut {
        case .cut:
            state.isCutPending = true
            state.awaitingPasteboardConfirmation = true
            state.confirmedChangeCount = nil
            state.cutStartedAt = now
            state.cutItemCount = 0
            return .transformCutToCopy

        case .copy:
            if state.isCutPending {
                state.clear()
                return .clearCutAndPassThrough
            }
            return .passThrough

        case .escape:
            if cancelOnEscape && state.isCutPending {
                state.clear()
                return .clearCutAndPassThrough
            }
            return .passThrough

        case .paste:
            guard state.isCutPending else {
                return .passThrough
            }

            if state.awaitingPasteboardConfirmation {
                let withinGrace = state.cutStartedAt.map { now.timeIntervalSince($0) <= confirmationGraceInterval } ?? false
                state.clear()
                return withinGrace ? .transformPasteToMove : .clearCutAndPassThrough
            }

            if let confirmed = state.confirmedChangeCount,
               let current = currentChangeCount,
               confirmed != current {
                state.clear()
                return .clearCutAndPassThrough
            }

            state.clear()
            return .transformPasteToMove

        case .other:
            return .passThrough
        }
    }

    public static func shouldRegisterFallbackPromptHotKey(
        isModuleRequested: Bool,
        isTapRunning: Bool,
        isFinderFrontmost: Bool,
        isPromptVisible: Bool,
        isPromptMutedForSession: Bool,
        lastPromptDismissedAt: Date?,
        now: Date = Date(),
        cooldown: TimeInterval = 30.0
    ) -> Bool {
        guard isModuleRequested,
              !isTapRunning,
              isFinderFrontmost,
              !isPromptVisible,
              !isPromptMutedForSession else {
            return false
        }
        if let lastPromptDismissedAt, now.timeIntervalSince(lastPromptDismissedAt) < cooldown {
            return false
        }
        return true
    }
}

private final class FinderKeyEventTapWorker {
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
                let worker = Unmanaged<FinderKeyEventTapWorker>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    worker.enableTap()
                    return Unmanaged.passUnretained(event)
                }
                return worker.handler(proxy, type, event)
            }

            guard let createdTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: FinderCutManager.tapPlacement,
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

        thread.name = "de.trst.Yeoman.finder-cut-event-tap"
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
        if let currentTap {
            CGEvent.tapEnable(tap: currentTap, enable: true)
        }
    }
}

public final class FinderCutManager: ObservableObject {
    public static let shared = FinderCutManager()

    public static let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    public static let tapPlacement = CGEventTapPlacement.headInsertEventTap
    public static let syntheticEventMarker: Int64 = 0x59454F4D_43555400

    public static func shouldTransform(_ type: CGEventType) -> Bool {
        type == .keyDown
    }

    @Published public var isRunning: Bool = false
    @Published public var hasAccessibilityPermission: Bool = false
    @Published public private(set) var isCutPending: Bool = false
    @Published public private(set) var cutItemCount: Int = 0

    @Published public var playFeedbackSound: Bool {
        didSet {
            UserDefaults.standard.set(playFeedbackSound, forKey: "finder_cut_play_sound")
        }
    }

    @Published public var cancelOnEscape: Bool {
        didSet {
            stateLock.lock()
            cachedCancelOnEscape = cancelOnEscape
            stateLock.unlock()
            UserDefaults.standard.set(cancelOnEscape, forKey: "finder_cut_cancel_on_escape")
        }
    }

    @Published public var showVisualHUD: Bool {
        didSet {
            UserDefaults.standard.set(showVisualHUD, forKey: "finder_cut_show_hud")
            if !showVisualHUD {
                FinderCutItemOverlayController.shared.clear()
            }
        }
    }

    private let stateLock = NSLock()
    private var decisionState = FinderCutState()
    private var cutGeneration: Int = 0
    private var isFinderFrontmost: Bool = false
    private var finderPID: pid_t = 0
    private var latestChangeCount: Int = 0
    private var cutKeyCode: Int64 = 7
    private var copyKeyCode: Int64 = 8
    private var pasteKeyCode: Int64 = 9
    private var cachedCancelOnEscape: Bool = true

    private let lifecycle = TapLifecycle()
    private var tapWorker: FinderKeyEventTapWorker?
    private var permissionCheckTimer: AnyCancellable?
    private var pasteboardTimer: AnyCancellable?
    private var appActivationObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?

    private static let fallbackHotKeySignature: OSType = 0x59454F4D // 'YEOM'
    private static let fallbackHotKeyID: UInt32 = 1
    private static let promptCooldownSeconds: TimeInterval = 30.0
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var isPromptVisible: Bool = false
    private var isPromptMutedForSession: Bool = false
    private var lastPromptDismissedAt: Date?
    private var cooldownTimer: DispatchWorkItem?

    public init() {
        let initialSound = UserDefaults.standard.object(forKey: "finder_cut_play_sound") as? Bool ?? true
        let initialCancelEscape = UserDefaults.standard.object(forKey: "finder_cut_cancel_on_escape") as? Bool ?? true
        let initialShowHUD = UserDefaults.standard.object(forKey: "finder_cut_show_hud") as? Bool ?? true
        self.playFeedbackSound = initialSound
        self.cancelOnEscape = initialCancelEscape
        self.showVisualHUD = initialShowHUD
        self.cachedCancelOnEscape = initialCancelEscape

        let frontApp = NSWorkspace.shared.frontmostApplication
        self.isFinderFrontmost = frontApp?.bundleIdentifier == FinderCutDecisionEngine.finderBundleIdentifier
        self.finderPID = self.isFinderFrontmost ? (frontApp?.processIdentifier ?? 0) : 0
        self.latestChangeCount = NSPasteboard.general.changeCount
        self.cutKeyCode = Self.resolveVirtualKeyCode(for: "x") ?? 7
        self.copyKeyCode = Self.resolveVirtualKeyCode(for: "c") ?? 8
        self.pasteKeyCode = Self.resolveVirtualKeyCode(for: "v") ?? 9

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.lifecycle.requested else { return }
            self.reconcilePermission()
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.handleFrontmostApplicationChange(app)
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFrontmostState()
        }
    }

    deinit {
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        stopPermissionPolling()
        stopPasteboardWatcher()
        removeFallbackHotKeyAndHandler()
        tearDownTap()
    }

    // MARK: - Accessibility & Tap Lifecycle

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
        if Thread.isMainThread {
            reconcileFallbackHotKey()
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

    public func start() {
        precondition(Thread.isMainThread)
        lifecycle.requested = true
        isPromptMutedForSession = false
        refreshFrontmostState()
        startPermissionPolling()
        reconcilePermission()
    }

    public func stop() {
        precondition(Thread.isMainThread)
        lifecycle.requested = false
        stopPermissionPolling()
        lifecycle.reconcile(permission: hasAccessibilityPermission, create: { false }, destroy: { self.tearDownTap() })
        isRunning = lifecycle.running
        isPromptVisible = false
        removeFallbackHotKeyAndHandler()
        FinderCutPermissionPromptController.shared.close()
        FinderCutItemOverlayController.shared.clear()
        cancelPendingCut()
    }

    public func cancelPendingCut() {
        precondition(Thread.isMainThread)
        stateLock.lock()
        cutGeneration += 1
        decisionState.clear()
        stateLock.unlock()
        syncPublishedCutState(isPending: false, itemCount: 0)
        stopPasteboardWatcher()
        FinderCutItemOverlayController.shared.clear()
    }

    public func handlePermissionPromptDismissed(muteForSession: Bool) {
        precondition(Thread.isMainThread)
        isPromptVisible = false
        if muteForSession {
            isPromptMutedForSession = true
        } else {
            lastPromptDismissedAt = Date()
            cooldownTimer?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.reconcileFallbackHotKey()
            }
            cooldownTimer = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.promptCooldownSeconds, execute: item)
        }
        reconcileFallbackHotKey()
    }

    private func reconcilePermission() {
        precondition(Thread.isMainThread)
        let permission = AXIsProcessTrusted()
        hasAccessibilityPermission = permission
        lifecycle.reconcile(permission: permission, create: { self.installTap() }, destroy: { self.tearDownTap() })
        isRunning = lifecycle.running
        if isRunning {
            isPromptVisible = false
            isPromptMutedForSession = false
            lastPromptDismissedAt = nil
            cooldownTimer?.cancel()
            cooldownTimer = nil
            FinderCutPermissionPromptController.shared.close()
        }
        reconcileFallbackHotKey()
    }

    private func installTap() -> Bool {
        let worker = FinderKeyEventTapWorker { [weak self] proxy, type, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return self.handleTapEvent(proxy: proxy, type: type, event: event)
        }
        guard worker.start(mask: Self.eventMask) else { return false }
        tapWorker = worker
        return true
    }

    private func tearDownTap() {
        tapWorker?.stop()
        tapWorker = nil
        isRunning = false
    }

    public func startPermissionPolling() {
        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.reconcilePermission()
            }
    }

    public func stopPermissionPolling() {
        permissionCheckTimer?.cancel()
        permissionCheckTimer = nil
    }

    // MARK: - Finder-Only Missing-Permission Prompt Hotkey

    private func reconcileFallbackHotKey() {
        precondition(Thread.isMainThread)
        stateLock.lock()
        let finderActive = isFinderFrontmost
        stateLock.unlock()

        let shouldRegister = FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
            isModuleRequested: lifecycle.requested,
            isTapRunning: isRunning,
            isFinderFrontmost: finderActive,
            isPromptVisible: isPromptVisible,
            isPromptMutedForSession: isPromptMutedForSession,
            lastPromptDismissedAt: lastPromptDismissedAt,
            cooldown: Self.promptCooldownSeconds
        )

        if shouldRegister {
            registerFallbackHotKey()
        } else {
            unregisterFallbackHotKey()
        }
    }

    private func registerFallbackHotKey() {
        guard hotKeyRef == nil else { return }

        if hotKeyHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            var handlerRef: EventHandlerRef?
            let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    let paramStatus = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    guard paramStatus == noErr,
                          hotKeyID.signature == FinderCutManager.fallbackHotKeySignature,
                          hotKeyID.id == FinderCutManager.fallbackHotKeyID else {
                        return OSStatus(eventNotHandledErr)
                    }
                    let manager = Unmanaged<FinderCutManager>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async {
                        manager.handleFallbackHotKeyPressed()
                    }
                    return noErr
                },
                1,
                &eventType,
                selfPtr,
                &handlerRef
            )
            guard handlerStatus == noErr, let handlerRef else { return }
            hotKeyHandlerRef = handlerRef
        }

        let xKeyCode = UInt32(Self.resolveVirtualKeyCode(for: "x") ?? 7)
        let hotKeyID = EventHotKeyID(signature: Self.fallbackHotKeySignature, id: Self.fallbackHotKeyID)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            xKeyCode,
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        if status == noErr, let newRef {
            hotKeyRef = newRef
        }
    }

    private func unregisterFallbackHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func removeFallbackHotKeyAndHandler() {
        cooldownTimer?.cancel()
        cooldownTimer = nil
        unregisterFallbackHotKey()
        if let handlerRef = hotKeyHandlerRef {
            RemoveEventHandler(handlerRef)
            hotKeyHandlerRef = nil
        }
    }

    private func handleFallbackHotKeyPressed() {
        precondition(Thread.isMainThread)
        unregisterFallbackHotKey()
        reconcilePermission()
        guard lifecycle.requested, !isRunning else { return }

        stateLock.lock()
        let finderActive = isFinderFrontmost
        stateLock.unlock()
        guard finderActive else { return }

        isPromptVisible = true
        reconcileFallbackHotKey()
        startPermissionPolling()
        FinderCutPermissionPromptController.shared.show(manager: self)
    }

    // MARK: - Frontmost App & Pasteboard Reconciliation

    private func refreshFrontmostState() {
        handleFrontmostApplicationChange(NSWorkspace.shared.frontmostApplication)
    }

    private func handleFrontmostApplicationChange(_ app: NSRunningApplication?) {
        precondition(Thread.isMainThread)
        let isFinder = app?.bundleIdentifier == FinderCutDecisionEngine.finderBundleIdentifier
        let pid = isFinder ? (app?.processIdentifier ?? 0) : 0
        let currentChangeCount = NSPasteboard.general.changeCount
        let resolvedCutCode = Self.resolveVirtualKeyCode(for: "x") ?? 7
        let resolvedCopyCode = Self.resolveVirtualKeyCode(for: "c") ?? 8
        let resolvedPasteCode = Self.resolveVirtualKeyCode(for: "v") ?? 9

        var clearedPending = false
        var pending = false
        var itemCount = 0

        stateLock.lock()
        isFinderFrontmost = isFinder
        finderPID = pid
        latestChangeCount = currentChangeCount
        cutKeyCode = resolvedCutCode
        copyKeyCode = resolvedCopyCode
        pasteKeyCode = resolvedPasteCode

        if decisionState.isCutPending,
           !decisionState.awaitingPasteboardConfirmation,
           let confirmed = decisionState.confirmedChangeCount,
           confirmed != currentChangeCount {
            cutGeneration += 1
            decisionState.clear()
            clearedPending = true
        }
        pending = decisionState.isCutPending
        itemCount = decisionState.cutItemCount
        stateLock.unlock()

        if clearedPending || isCutPending != pending || cutItemCount != itemCount {
            syncPublishedCutState(isPending: pending, itemCount: itemCount)
            if !pending {
                stopPasteboardWatcher()
            }
        }
        if !pending {
            FinderCutItemOverlayController.shared.clear()
        } else {
            FinderCutItemOverlayController.shared.setFinderFrontmost(isFinder, finderPID: pid)
        }
        reconcileFallbackHotKey()
    }

    private func startPasteboardWatcher() {
        guard pasteboardTimer == nil else { return }
        pasteboardTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.reconcilePasteboardOnMain()
            }
    }

    private func stopPasteboardWatcher() {
        pasteboardTimer?.cancel()
        pasteboardTimer = nil
    }

    private func reconcilePasteboardOnMain() {
        precondition(Thread.isMainThread)
        let currentChangeCount = NSPasteboard.general.changeCount
        var shouldStopWatcher = false
        var pending = false
        var itemCount = 0

        stateLock.lock()
        latestChangeCount = currentChangeCount
        if decisionState.isCutPending,
           !decisionState.awaitingPasteboardConfirmation,
           let confirmed = decisionState.confirmedChangeCount,
           confirmed != currentChangeCount {
            cutGeneration += 1
            decisionState.clear()
            shouldStopWatcher = true
        }
        pending = decisionState.isCutPending
        itemCount = decisionState.cutItemCount
        if !pending {
            shouldStopWatcher = true
        }
        stateLock.unlock()

        syncPublishedCutState(isPending: pending, itemCount: itemCount)
        if shouldStopWatcher || !pending {
            stopPasteboardWatcher()
            FinderCutItemOverlayController.shared.clear()
        }
    }

    private func syncPublishedCutState(isPending: Bool, itemCount: Int) {
        if isCutPending != isPending {
            isCutPending = isPending
        }
        if cutItemCount != itemCount {
            cutItemCount = itemCount
        }
    }

    // MARK: - Event Tap Processing (Finder-Only)

    private func handleTapEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard Self.shouldTransform(type) else {
            return Unmanaged.passUnretained(event)
        }

        stateLock.lock()
        let finderActive = isFinderFrontmost
        let currentFinderPID = finderPID
        let pendingCut = decisionState.isCutPending
        let cancelEscape = cachedCancelOnEscape
        let currentCutKeyCode = cutKeyCode
        let currentCopyKeyCode = copyKeyCode
        let currentPasteKeyCode = pasteKeyCode
        let changeCountSnapshot = latestChangeCount
        let expectedMoveChangeCount = decisionState.confirmedChangeCount
        stateLock.unlock()

        // Fast short-circuit outside Finder: never inspect keystrokes in any other application.
        guard finderActive else {
            return Unmanaged.passUnretained(event)
        }

        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let isSynthetic = event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker
        guard !isAutorepeat, !isSynthetic else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let unicodeChar = Self.unicodeCharacter(from: event)
        let shortcut = FinderCutDecisionEngine.classifyShortcut(
            keyCode: keyCode,
            unicodeCharacter: unicodeChar,
            flags: event.flags,
            cutKeyCode: currentCutKeyCode,
            copyKeyCode: currentCopyKeyCode,
            pasteKeyCode: currentPasteKeyCode
        )

        guard shortcut != .other else {
            return Unmanaged.passUnretained(event)
        }

        let needsTextCheck = (shortcut == .cut) || (shortcut == .paste && pendingCut)
        let isEditingText = needsTextCheck ? Self.isEditingTextInFinder(pid: currentFinderPID) : false

        stateLock.lock()
        let action = FinderCutDecisionEngine.decide(
            eventType: type,
            isFinderFrontmost: isFinderFrontmost,
            isAutorepeat: isAutorepeat,
            isSynthetic: isSynthetic,
            shortcut: shortcut,
            isEditingTextInFinder: isEditingText,
            cancelOnEscape: cancelEscape,
            state: &decisionState,
            now: Date(),
            currentChangeCount: changeCountSnapshot
        )

        var generationToConfirm: Int?
        if action == .transformCutToCopy {
            cutGeneration += 1
            generationToConfirm = cutGeneration
        } else if action == .transformPasteToMove || action == .clearCutAndPassThrough {
            cutGeneration += 1
        }
        let nextPending = decisionState.isCutPending
        let nextCount = decisionState.cutItemCount
        stateLock.unlock()

        switch action {
        case .passThrough:
            return Unmanaged.passUnretained(event)

        case .clearCutAndPassThrough:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.syncPublishedCutState(isPending: nextPending, itemCount: nextCount)
                if !nextPending {
                    self.stopPasteboardWatcher()
                    FinderCutItemOverlayController.shared.clear()
                }
            }
            return Unmanaged.passUnretained(event)

        case .transformCutToCopy:
            if let gen = generationToConfirm {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.executeFinderCutOnMain(finderPID: currentFinderPID, generation: gen, fallbackCopyKeyCode: currentCopyKeyCode)
                }
            }
            // Swallow Cmd+X so Finder neither cuts text unexpectedly nor beeps.
            return nil

        case .transformPasteToMove:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.executeFinderMoveOnMain(
                    finderPID: currentFinderPID,
                    expectedChangeCount: expectedMoveChangeCount,
                    fallbackPasteKeyCode: currentPasteKeyCode
                )
            }
            // Swallow Cmd+V and invoke Finder's native Move Item Here (Cmd+Opt+V).
            return nil
        }
    }

    private enum FinderMenuPressResult {
        case pressed
        case disabled
        case apiDisabled
        case notFound
    }

    private func executeFinderCutOnMain(finderPID: pid_t, generation: Int, fallbackCopyKeyCode: Int64) {
        precondition(Thread.isMainThread)

        stateLock.lock()
        let stillActive = (cutGeneration == generation) && decisionState.isCutPending
        stateLock.unlock()
        guard stillActive else { return }

        let baselineChangeCount = NSPasteboard.general.changeCount

        // Extra safety: if Finder's Edit -> Cut is enabled (e.g. an editable field that didn't report a standard AX text role),
        // perform normal Cut and cancel file-cut staging.
        let cutResult = Self.pressFinderMenuItem(pid: finderPID, cmdChar: "X", modifiers: 0)
        switch cutResult {
        case .apiDisabled:
            cancelPendingCut()
            reconcilePermission()
            if !isRunning {
                isPromptVisible = true
                reconcileFallbackHotKey()
                FinderCutPermissionPromptController.shared.show(manager: self)
            }
            return
        case .pressed:
            cancelPendingCut()
            return
        case .disabled, .notFound:
            break
        }

        let copyResult = Self.pressFinderMenuItem(pid: finderPID, cmdChar: "C", modifiers: 0)
        switch copyResult {
        case .apiDisabled:
            cancelPendingCut()
            reconcilePermission()
            if !isRunning {
                isPromptVisible = true
                reconcileFallbackHotKey()
                FinderCutPermissionPromptController.shared.show(manager: self)
            }
            return
        case .disabled:
            cancelPendingCut()
            return
        case .pressed:
            break
        case .notFound:
            Self.postSyntheticShortcut(pid: finderPID, keyCode: fallbackCopyKeyCode, flags: .maskCommand)
        }

        syncPublishedCutState(isPending: true, itemCount: 0)
        startPasteboardWatcher()
        scheduleCutConfirmation(generation: generation, baselineChangeCount: baselineChangeCount)
    }

    private func executeFinderMoveOnMain(finderPID: pid_t, expectedChangeCount: Int?, fallbackPasteKeyCode: Int64) {
        precondition(Thread.isMainThread)
        syncPublishedCutState(isPending: false, itemCount: 0)
        stopPasteboardWatcher()
        FinderCutItemOverlayController.shared.clear()

        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        let countMatches = (expectedChangeCount == nil) || (expectedChangeCount == currentCount)
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        if countMatches && !fileURLs.isEmpty {
            let moveResult = Self.pressFinderMenuItem(pid: finderPID, cmdChar: "V", modifiers: 2)
            switch moveResult {
            case .apiDisabled:
                reconcilePermission()
                if !isRunning {
                    isPromptVisible = true
                    reconcileFallbackHotKey()
                    FinderCutPermissionPromptController.shared.show(manager: self)
                }
            case .pressed, .disabled:
                break
            case .notFound:
                Self.postSyntheticShortcut(
                    pid: finderPID,
                    keyCode: fallbackPasteKeyCode,
                    flags: [.maskCommand, .maskAlternate]
                )
            }
        } else {
            // Pasteboard changed since Cut -> perform standard Paste instead of moving stale files.
            let pasteResult = Self.pressFinderMenuItem(pid: finderPID, cmdChar: "V", modifiers: 0)
            if pasteResult == .notFound {
                Self.postSyntheticShortcut(pid: finderPID, keyCode: fallbackPasteKeyCode, flags: .maskCommand)
            }
        }
    }

    private static func pressFinderMenuItem(pid: pid_t, cmdChar: String, modifiers: Int) -> FinderMenuPressResult {
        guard pid > 0 else { return .notFound }
        let appElement = AXUIElementCreateApplication(pid)
        var menuBarValue: CFTypeRef?
        let mbError = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue)
        if mbError == .apiDisabled {
            return .apiDisabled
        }
        guard mbError == .success,
              let menuBarValue,
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
            return .notFound
        }
        let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)

        var childrenValue: CFTypeRef?
        let chError = AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue)
        guard chError == .success, let menuBarItems = childrenValue as? [AXUIElement], menuBarItems.count > 1 else {
            return .notFound
        }

        // Check Edit menu (typically index 3) first, then scan remaining top-level menus.
        var orderedMenus: [AXUIElement] = []
        if menuBarItems.count > 3 {
            orderedMenus.append(menuBarItems[3])
        }
        for (idx, item) in menuBarItems.enumerated() where idx != 0 && idx != 3 {
            orderedMenus.append(item)
        }

        for topMenuItem in orderedMenus {
            var submenusValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(topMenuItem, kAXChildrenAttribute as CFString, &submenusValue) == .success,
                  let submenus = submenusValue as? [AXUIElement],
                  let submenu = submenus.first else {
                continue
            }

            var itemsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(submenu, kAXChildrenAttribute as CFString, &itemsValue) == .success,
                  let items = itemsValue as? [AXUIElement] else {
                continue
            }

            for menuItem in items {
                var charValue: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(menuItem, kAXMenuItemCmdCharAttribute as CFString, &charValue)
                var modValue: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(menuItem, kAXMenuItemCmdModifiersAttribute as CFString, &modValue)

                if FinderCutDecisionEngine.matchesFinderMenuItem(
                    cmdChar: charValue as? String,
                    modifiers: modValue as? Int,
                    targetChar: cmdChar,
                    targetModifiers: modifiers
                ) {
                    var enabledValue: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(menuItem, kAXEnabledAttribute as CFString, &enabledValue)
                    if (enabledValue as? Bool) == false {
                        return .disabled
                    }

                    let pressErr = AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
                    if pressErr == .success {
                        return .pressed
                    } else if pressErr == .apiDisabled {
                        return .apiDisabled
                    }
                    return .notFound
                }
            }
        }

        return .notFound
    }

    private static func postSyntheticShortcut(pid: pid_t, keyCode: Int64, flags: CGEventFlags) {
        guard pid > 0,
              let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
    }

    private func scheduleCutConfirmation(generation: Int, baselineChangeCount: Int) {
        let checkpoints: [TimeInterval] = [0.06, 0.16, 0.30]
        for (index, delay) in checkpoints.enumerated() {
            let isFinal = index == checkpoints.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.confirmCutOnMain(generation: generation, baselineChangeCount: baselineChangeCount, isFinalAttempt: isFinal)
            }
        }
    }

    private func confirmCutOnMain(generation: Int, baselineChangeCount: Int, isFinalAttempt: Bool) {
        precondition(Thread.isMainThread)

        stateLock.lock()
        let stillWaiting = (cutGeneration == generation) && decisionState.isCutPending && decisionState.awaitingPasteboardConfirmation
        stateLock.unlock()
        guard stillWaiting else { return }

        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        if currentCount != baselineChangeCount {
            let fileURLs = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] ?? []

            if !fileURLs.isEmpty {
                stateLock.lock()
                if cutGeneration == generation && decisionState.isCutPending {
                    decisionState.awaitingPasteboardConfirmation = false
                    decisionState.confirmedChangeCount = currentCount
                    decisionState.cutItemCount = fileURLs.count
                    latestChangeCount = currentCount
                }
                let currentPID = finderPID
                stateLock.unlock()

                syncPublishedCutState(isPending: true, itemCount: fileURLs.count)
                if showVisualHUD {
                    FinderCutItemOverlayController.shared.beginTracking(urls: fileURLs, finderPID: currentPID)
                }
                if playFeedbackSound {
                    NSSound(named: NSSound.Name("Tink"))?.play()
                }
                return
            }

            // Pasteboard changed to something that is not Finder file URLs -> clear pending cut.
            stateLock.lock()
            if cutGeneration == generation {
                decisionState.clear()
                latestChangeCount = currentCount
            }
            stateLock.unlock()
            syncPublishedCutState(isPending: false, itemCount: 0)
            stopPasteboardWatcher()
            return
        }

        if isFinalAttempt {
            // Finder did not write anything to the pasteboard (e.g. empty selection).
            stateLock.lock()
            if cutGeneration == generation {
                decisionState.clear()
            }
            stateLock.unlock()
            syncPublishedCutState(isPending: false, itemCount: 0)
            stopPasteboardWatcher()
        }
    }

    // MARK: - Helpers

    private static func unicodeCharacter(from event: CGEvent) -> String? {
        var actualLength = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualLength, unicodeString: &buffer)
        guard actualLength > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: actualLength)
    }

    private static func isEditingTextInFinder(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return false
        }
        let element = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var roleValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        var subroleValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)

        return FinderCutDecisionEngine.isTextInputElement(
            role: roleValue as? String,
            subrole: subroleValue as? String
        )
    }

    private static func resolveVirtualKeyCode(for target: Character) -> Int64? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self)
        guard let ptr = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(ptr))
        let targetString = String(target).lowercased()

        for keyCode in 0..<128 {
            var deadKeyState: UInt32 = 0
            var actualLength = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &actualLength,
                &chars
            )
            if status == noErr && actualLength > 0 {
                let produced = String(utf16CodeUnits: chars, count: actualLength).lowercased()
                if produced == targetString {
                    return Int64(keyCode)
                }
            }
        }
        return nil
    }
}
