import AppKit
import ApplicationServices
import CoreGraphics
import QuartzCore

public struct FinderCutOverlayItem: Equatable {
    public let rect: CGRect
    public let isListRow: Bool

    public init(rect: CGRect, isListRow: Bool) {
        self.rect = rect
        self.isListRow = isListRow
    }
}

public struct FinderCutProjectedGeometry: Equatable {
    public let clipAppKitRect: CGRect
    public let items: [FinderCutOverlayItem]

    public init(clipAppKitRect: CGRect, items: [FinderCutOverlayItem]) {
        self.clipAppKitRect = clipAppKitRect
        self.items = items
    }
}

private final class FinderCutItemOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FinderCutItemOverlayView: NSView {
    var items: [FinderCutOverlayItem] = [] {
        didSet {
            if oldValue != items {
                needsDisplay = true
            }
        }
    }

    private static let dashPattern: [CGFloat] = [5, 3]

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for item in items {
            let (insetRect, radius) = FinderCutItemOverlayController.styledOverlayRect(
                for: item.rect,
                isListRow: item.isListRow
            )
            guard insetRect.width >= 8, insetRect.height >= 8 else { continue }
            guard insetRect.intersects(dirtyRect) else { continue }

            let path = NSBezierPath(roundedRect: insetRect, xRadius: radius, yRadius: radius)

            NSColor.windowBackgroundColor.withAlphaComponent(0.22).setFill()
            path.fill()

            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            path.fill()

            path.lineWidth = 1.5
            Self.dashPattern.withUnsafeBufferPointer { buffer in
                path.setLineDash(buffer.baseAddress, count: buffer.count, phase: 0)
            }
            NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
            path.stroke()
        }
    }
}

/// Tracks and draws a live, click-through overlay pill directly over cut files inside Finder.
public final class FinderCutItemOverlayController: NSObject {
    public static let shared = FinderCutItemOverlayController()

    private static let maxTrackedURLs = 100
    private static let maxTrackedItems = 20
    private static let maxAXScanChildren = 120
    private static let maxAXChildDepth = 2
    private static let maxAXSubChildren = 4
    private static let activeRefreshInterval: TimeInterval = 1.0 / 120.0
    private static let idleRefreshInterval: TimeInterval = 0.08
    private static let motionHoldDuration: TimeInterval = 0.35
    private static let rescanInterval: TimeInterval = 0.25
    private static let scrollRescanDeferralInterval: TimeInterval = 0.15
    private static let maxRescanDeferralDuringScroll: TimeInterval = 0.75
    private static let axResizeDeferralInterval: TimeInterval = 0.06
    private static let maxAXDeferralDuringDrag: TimeInterval = 0.35

    private var panel: FinderCutItemOverlayPanel?
    private var overlayView: FinderCutItemOverlayView?
    private var refreshTimer: Timer?
    private var currentTimerInterval: TimeInterval = 0
    private var axObserver: AXObserver?

    private var trackedURLKeys: Set<String> = []
    private var trackedPID: pid_t = 0
    private var isFinderFrontmost = false
    private var containerElement: AXUIElement?
    private var scrollAreaElement: AXUIElement?
    private var trackedWindow: AXUIElement?

    private var trackedCGWindowID: CGWindowID = kCGNullWindowID
    private var lastLiveWindowQuartz: CGRect?
    private var lastWindowMotionTime: CFAbsoluteTime = 0
    private var lastAXSyncTime: CFAbsoluteTime = 0
    private var lastAXSnapshot: (windowAppKit: CGRect, clipAppKit: CGRect, items: [FinderCutOverlayItem])?

    private var cachedMatches: [(element: AXUIElement, isListRow: Bool)] = []
    private var lastRescanTime: CFAbsoluteTime = 0
    private var lastMotionTime: CFAbsoluteTime = 0
    private var lastScrollMotionTime: CFAbsoluteTime = 0
    private var lastRenderedItems: [FinderCutOverlayItem] = []
    private var lastWindowFrame: CGRect?
    private var lastClipFrame: CGRect?
    private var isRefreshing = false
    private var pendingCoalescedRefresh = false
    private var pendingNeedsRescan = false

    private override init() {
        super.init()
    }

    private var isTracking: Bool {
        !trackedURLKeys.isEmpty && trackedPID > 0
    }

    /// Returns a 120Hz interval during recent window/scroll motion and backs off to low-overhead polling when idle.
    public static func recommendedRefreshInterval(sinceLastMotion elapsed: TimeInterval) -> TimeInterval {
        elapsed < motionHoldDuration ? activeRefreshInterval : idleRefreshInterval
    }

    /// Converts top-left Quartz coordinates to bottom-left AppKit screen coordinates.
    public static func quartzToAppKit(_ quartzRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: quartzRect.minX,
            y: primaryScreenHeight - quartzRect.maxY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }

    /// Trims the top of `clipAppKitRect` cleanly below Finder's column headers (`AXHeader` or its `AXSortButton` children).
    public static func clipRectBelowHeader(
        clipAppKitRect: CGRect,
        headerRectsQuartz: [CGRect],
        primaryScreenHeight: CGFloat
    ) -> CGRect? {
        let validHeaders = headerRectsQuartz.filter { $0.height > 1 }
        guard let maxQuartzHeaderBottom = validHeaders.map(\.maxY).max() else {
            return clipAppKitRect
        }

        let headerBottomAppKit = primaryScreenHeight - maxQuartzHeaderBottom
        let clippedTop = min(clipAppKitRect.maxY, headerBottomAppKit)
        let clippedHeight = clippedTop - clipAppKitRect.minY
        guard clippedHeight >= 20 else {
            return nil
        }

        return CGRect(
            x: clipAppKitRect.minX,
            y: clipAppKitRect.minY,
            width: clipAppKitRect.width,
            height: clippedHeight
        )
    }

    /// Produces a normalized path key for matching Finder AX item URLs against pasteboard file URLs.
    public static func normalizedFileURLKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// Computes the inset frame and pill corner radius matching Finder's list row highlight or icon bounds.
    public static func styledOverlayRect(for localRect: CGRect, isListRow: Bool) -> (rect: CGRect, cornerRadius: CGFloat) {
        let dx: CGFloat = isListRow ? (localRect.width > 60 ? 10.0 : 1.5) : 1.5
        let dy: CGFloat = isListRow ? 0.75 : 1.5
        let insetRect = localRect.insetBy(dx: dx, dy: dy)
        let cornerRadius = min(10.0, insetRect.height / 2.0)
        return (insetRect, cornerRadius)
    }

    /// Projects cached AX clip and item geometry directly onto live WindowServer window bounds during active resize/move drags.
    public static func projectGeometry(
        axWindowAppKit: CGRect,
        axClipAppKit: CGRect,
        axItems: [FinderCutOverlayItem],
        liveWindowAppKit: CGRect,
        screenVisibleFrame: CGRect,
        maxItems: Int = 20
    ) -> FinderCutProjectedGeometry? {
        guard axWindowAppKit.width >= 40,
              axWindowAppKit.height >= 40,
              liveWindowAppKit.width >= 40,
              liveWindowAppKit.height >= 40,
              maxItems > 0 else {
            return nil
        }

        let leftInset = max(0, axClipAppKit.minX - axWindowAppKit.minX)
        let rightInset = max(0, axWindowAppKit.maxX - axClipAppKit.maxX)
        let topInset = max(0, axWindowAppKit.maxY - axClipAppKit.maxY)
        let bottomInset = max(0, axClipAppKit.minY - axWindowAppKit.minY)

        let rawWidth = liveWindowAppKit.width - leftInset - rightInset
        let rawHeight = liveWindowAppKit.height - topInset - bottomInset
        guard rawWidth >= 20, rawHeight >= 20 else {
            return nil
        }

        let rawClip = CGRect(
            x: liveWindowAppKit.minX + leftInset,
            y: liveWindowAppKit.minY + bottomInset,
            width: rawWidth,
            height: rawHeight
        )
        let projectedClip = rawClip.intersection(screenVisibleFrame)
        guard !projectedClip.isNull,
              projectedClip.width >= 20,
              projectedClip.height >= 20 else {
            return nil
        }

        let dxLeft = rawClip.minX - axClipAppKit.minX
        let dyTop = rawClip.maxY - axClipAppKit.maxY

        var localItems: [FinderCutOverlayItem] = []
        localItems.reserveCapacity(min(axItems.count, maxItems))

        for item in axItems {
            let candidateRect: CGRect
            if item.isListRow && rightInset <= 20 && item.rect.width <= axClipAppKit.width + 2 {
                // Row previously fit cleanly within the scroll view -> resize flush with the viewport.
                candidateRect = CGRect(
                    x: rawClip.minX,
                    y: item.rect.minY + dyTop,
                    width: rawClip.width,
                    height: item.rect.height
                )
            } else {
                // Horizontally overflowing rows, Column View rows, and icons keep their true unclipped width and scroll offset.
                candidateRect = CGRect(
                    x: item.rect.minX + dxLeft,
                    y: item.rect.minY + dyTop,
                    width: item.rect.width,
                    height: item.rect.height
                )
            }

            guard let localRect = localVisibleRect(for: candidateRect, in: projectedClip) else {
                continue
            }
            localItems.append(FinderCutOverlayItem(rect: localRect, isListRow: item.isListRow))
            if localItems.count == maxItems {
                break
            }
        }

        return FinderCutProjectedGeometry(
            clipAppKitRect: projectedClip,
            items: mergeAdjacentItems(localItems)
        )
    }

    /// Merges adjacent list rows or neighboring icons into combined outer rectangles while keeping separated items distinct.
    public static func mergeAdjacentItems(
        _ items: [FinderCutOverlayItem],
        tolerance: CGFloat = 2.0
    ) -> [FinderCutOverlayItem] {
        guard !items.isEmpty else { return [] }
        let listRows = items.filter(\.isListRow)
        let otherItems = items.filter { !$0.isListRow }

        let mergedRows = mergeVerticallyAdjacent(listRows, tolerance: tolerance)
        let mergedHorizontally = mergeHorizontallyAdjacent(otherItems, tolerance: tolerance)
        let mergedOthers = mergeVerticallyAdjacent(mergedHorizontally, tolerance: tolerance)
        return mergedRows + mergedOthers
    }

    private static func mergeVerticallyAdjacent(
        _ items: [FinderCutOverlayItem],
        tolerance: CGFloat
    ) -> [FinderCutOverlayItem] {
        guard items.count > 1 else { return items }
        let sorted = items.sorted {
            if $0.rect.minY != $1.rect.minY { return $0.rect.minY < $1.rect.minY }
            return $0.rect.minX < $1.rect.minX
        }
        var merged: [FinderCutOverlayItem] = []
        merged.reserveCapacity(sorted.count)

        for item in sorted {
            if let matchIndex = merged.lastIndex(where: { existing in
                abs(existing.rect.minX - item.rect.minX) <= tolerance &&
                abs(existing.rect.width - item.rect.width) <= tolerance &&
                item.rect.minY <= existing.rect.maxY + tolerance
            }) {
                let existing = merged[matchIndex]
                merged[matchIndex] = FinderCutOverlayItem(
                    rect: existing.rect.union(item.rect),
                    isListRow: existing.isListRow
                )
            } else {
                merged.append(item)
            }
        }
        return merged
    }

    private static func mergeHorizontallyAdjacent(
        _ items: [FinderCutOverlayItem],
        tolerance: CGFloat
    ) -> [FinderCutOverlayItem] {
        guard items.count > 1 else { return items }
        let sorted = items.sorted {
            if $0.rect.minY != $1.rect.minY { return $0.rect.minY < $1.rect.minY }
            return $0.rect.minX < $1.rect.minX
        }
        var merged: [FinderCutOverlayItem] = []
        merged.reserveCapacity(sorted.count)

        for item in sorted {
            if let matchIndex = merged.lastIndex(where: { existing in
                abs(existing.rect.minY - item.rect.minY) <= tolerance &&
                abs(existing.rect.height - item.rect.height) <= tolerance &&
                item.rect.minX <= existing.rect.maxX + tolerance &&
                item.rect.maxX >= existing.rect.minX - tolerance
            }) {
                let existing = merged[matchIndex]
                merged[matchIndex] = FinderCutOverlayItem(
                    rect: existing.rect.union(item.rect),
                    isListRow: existing.isListRow
                )
            } else {
                merged.append(item)
            }
        }
        return merged
    }

    /// Filters item AppKit frames to those meaningfully visible within `clipAppKitRect` and translates them to clip-local coordinates.
    public static func clippedLocalItemRects(
        itemAppKitRects: [CGRect],
        clipAppKitRect: CGRect,
        maxItems: Int = 20
    ) -> [CGRect] {
        guard clipAppKitRect.width >= 20, clipAppKitRect.height >= 20, maxItems > 0 else {
            return []
        }

        var results: [CGRect] = []
        results.reserveCapacity(min(itemAppKitRects.count, maxItems))

        for itemRect in itemAppKitRects {
            guard let localRect = localVisibleRect(for: itemRect, in: clipAppKitRect) else {
                continue
            }
            results.append(localRect)
            if results.count == maxItems {
                break
            }
        }

        return results
    }

    private static func clippedOverlayItems(
        matchedItems: [(appKitRect: CGRect, isListRow: Bool)],
        clipAppKitRect: CGRect,
        maxItems: Int
    ) -> [FinderCutOverlayItem] {
        guard clipAppKitRect.width >= 20, clipAppKitRect.height >= 20, maxItems > 0 else {
            return []
        }

        var results: [FinderCutOverlayItem] = []
        results.reserveCapacity(min(matchedItems.count, maxItems))

        for entry in matchedItems {
            // Preserve the true unclipped row bounds so horizontally overflowing bars clip flat against the panel edge like Finder's blue highlight.
            guard let localRect = localVisibleRect(for: entry.appKitRect, in: clipAppKitRect) else {
                continue
            }
            results.append(FinderCutOverlayItem(rect: localRect, isListRow: entry.isListRow))
            if results.count == maxItems {
                break
            }
        }

        return results
    }

    private static func localVisibleRect(for itemRect: CGRect, in clipAppKitRect: CGRect) -> CGRect? {
        guard itemRect.width >= 12, itemRect.height >= 12 else { return nil }
        let visible = itemRect.intersection(clipAppKitRect)
        guard !visible.isNull,
              visible.width >= 2,
              visible.height >= 2 else {
            return nil
        }

        return CGRect(
            x: itemRect.minX - clipAppKitRect.minX,
            y: itemRect.minY - clipAppKitRect.minY,
            width: itemRect.width,
            height: itemRect.height
        )
    }

    public func beginTracking(urls: [URL], finderPID: pid_t) {
        precondition(Thread.isMainThread)
        guard !urls.isEmpty, finderPID > 0 else {
            clear()
            return
        }

        var keys: Set<String> = []
        keys.reserveCapacity(min(urls.count, Self.maxTrackedURLs) * 2)
        for url in urls.prefix(Self.maxTrackedURLs) {
            keys.insert(Self.normalizedFileURLKey(url))
            keys.insert(Self.normalizedFileURLKey(url.resolvingSymlinksInPath()))
        }

        trackedURLKeys = keys
        trackedPID = finderPID
        isFinderFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == finderPID

        let resolved = Self.resolveInitialElements(finderPID: finderPID)
        containerElement = resolved.container
        scrollAreaElement = resolved.scrollArea
        trackedWindow = resolved.window
        trackedCGWindowID = kCGNullWindowID
        lastLiveWindowQuartz = nil
        lastWindowMotionTime = 0
        lastAXSyncTime = 0
        lastAXSnapshot = nil

        cachedMatches = []
        lastRescanTime = 0
        lastMotionTime = CFAbsoluteTimeGetCurrent()
        lastScrollMotionTime = 0
        lastRenderedItems = []
        lastWindowFrame = nil
        lastClipFrame = nil
        pendingNeedsRescan = true
        pendingCoalescedRefresh = false

        if isFinderFrontmost {
            installAXObserver(finderPID: finderPID)
            reconcileTimerInterval(now: lastMotionTime)
            refreshOverlay(forceRescan: true, allowProjectionFastPath: false)
        } else {
            uninstallAXObserver()
            stopRefreshTimer()
            hidePanel()
        }
    }

    public func setFinderFrontmost(_ isFrontmost: Bool, finderPID: pid_t) {
        precondition(Thread.isMainThread)
        guard isTracking else { return }

        isFinderFrontmost = isFrontmost && finderPID == trackedPID
        if !isFinderFrontmost {
            uninstallAXObserver()
            stopRefreshTimer()
            hidePanel()
            return
        }

        trackedCGWindowID = kCGNullWindowID
        lastLiveWindowQuartz = nil
        lastAXSnapshot = nil
        lastScrollMotionTime = 0
        lastRenderedItems = []
        lastMotionTime = CFAbsoluteTimeGetCurrent()
        installAXObserver(finderPID: trackedPID)
        reconcileTimerInterval(now: lastMotionTime)
        refreshOverlay(forceRescan: true, allowProjectionFastPath: false)
    }

    public func clear() {
        precondition(Thread.isMainThread)
        uninstallAXObserver()
        stopRefreshTimer()
        trackedURLKeys.removeAll(keepingCapacity: false)
        trackedPID = 0
        isFinderFrontmost = false
        containerElement = nil
        scrollAreaElement = nil
        trackedWindow = nil
        trackedCGWindowID = kCGNullWindowID
        lastLiveWindowQuartz = nil
        lastWindowMotionTime = 0
        lastAXSyncTime = 0
        lastAXSnapshot = nil
        cachedMatches.removeAll(keepingCapacity: false)
        lastRescanTime = 0
        lastMotionTime = 0
        lastScrollMotionTime = 0
        lastRenderedItems.removeAll(keepingCapacity: false)
        lastWindowFrame = nil
        lastClipFrame = nil
        pendingCoalescedRefresh = false
        pendingNeedsRescan = false
        hidePanel()
    }

    private func installAXObserver(finderPID: pid_t) {
        uninstallAXObserver()
        guard finderPID > 0 else { return }

        var createdObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<FinderCutItemOverlayController>.fromOpaque(refcon).takeUnretainedValue()
            let noteName = notification as String
            if Thread.isMainThread {
                controller.handleAXNotification(noteName)
            } else {
                DispatchQueue.main.async { [weak controller] in
                    controller?.handleAXNotification(noteName)
                }
            }
        }

        guard AXObserverCreate(finderPID, callback, &createdObserver) == .success,
              let observer = createdObserver else {
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(finderPID)
        let appNotifications: [String] = [
            kAXFocusedWindowChangedNotification as String,
            kAXMovedNotification as String,
            kAXResizedNotification as String,
            kAXSelectedRowsChangedNotification as String,
            kAXSelectedChildrenChangedNotification as String
        ]
        for notification in appNotifications {
            _ = AXObserverAddNotification(observer, appElement, notification as CFString, selfPtr)
        }

        if let trackedWindow {
            let windowNotifications: [String] = [
                kAXMovedNotification as String,
                kAXResizedNotification as String,
                kAXUIElementDestroyedNotification as String
            ]
            for notification in windowNotifications {
                _ = AXObserverAddNotification(observer, trackedWindow, notification as CFString, selfPtr)
            }
        }

        if let scrollAreaElement {
            for scrollAttr in [kAXVerticalScrollBarAttribute as CFString, kAXHorizontalScrollBarAttribute as CFString] {
                if let scrollBar = Self.axElementAttribute(scrollAreaElement, attribute: scrollAttr) {
                    _ = AXObserverAddNotification(observer, scrollBar, kAXValueChangedNotification as CFString, selfPtr)
                }
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
    }

    private func uninstallAXObserver() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = nil
    }

    private func handleAXNotification(_ notification: String) {
        precondition(Thread.isMainThread)
        guard isTracking, isFinderFrontmost else { return }

        let now = CFAbsoluteTimeGetCurrent()
        lastMotionTime = now
        reconcileTimerInterval(now: now)

        let requiresRescan = notification == (kAXFocusedWindowChangedNotification as String) ||
            notification == (kAXUIElementDestroyedNotification as String) ||
            notification == (kAXSelectedRowsChangedNotification as String) ||
            notification == (kAXSelectedChildrenChangedNotification as String)
        let isScrollChange = notification == (kAXValueChangedNotification as String)

        if requiresRescan {
            pendingNeedsRescan = true
        } else if isScrollChange {
            lastScrollMotionTime = now
        } else if notification == (kAXMovedNotification as String) ||
                    notification == (kAXResizedNotification as String) {
            lastWindowMotionTime = now
        }

        guard !isRefreshing else {
            pendingCoalescedRefresh = true
            return
        }

        let needsRescan = pendingNeedsRescan
        pendingNeedsRescan = false
        let allowFastPath = !needsRescan && !isScrollChange
        refreshOverlay(forceRescan: needsRescan, allowProjectionFastPath: allowFastPath)
    }

    private func reconcileTimerInterval(now: CFAbsoluteTime) {
        let desired = Self.recommendedRefreshInterval(sinceLastMotion: now - lastMotionTime)
        if refreshTimer != nil, abs(currentTimerInterval - desired) < 0.001 {
            return
        }
        stopRefreshTimer()
        currentTimerInterval = desired
        let timer = Timer(timeInterval: desired, repeats: true) { [weak self] _ in
            self?.refreshOverlay()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        currentTimerInterval = 0
    }

    private func hidePanel() {
        lastRenderedItems.removeAll(keepingCapacity: false)
        overlayView?.items = []
        panel?.orderOut(nil)
    }

    private func flushPendingCoalescedRefreshIfNeeded() {
        guard pendingCoalescedRefresh else { return }
        pendingCoalescedRefresh = false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isTracking, self.isFinderFrontmost else { return }
            let needsRescan = self.pendingNeedsRescan
            self.pendingNeedsRescan = false
            self.refreshOverlay(forceRescan: needsRescan, allowProjectionFastPath: !needsRescan)
        }
    }

    private func refreshOverlay(forceRescan: Bool = false, allowProjectionFastPath: Bool = true) {
        precondition(Thread.isMainThread)
        guard !isRefreshing else {
            if forceRescan {
                pendingNeedsRescan = true
            }
            pendingCoalescedRefresh = true
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
            flushPendingCoalescedRefreshIfNeeded()
        }

        guard isTracking,
              isFinderFrontmost,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == trackedPID else {
            hidePanel()
            return
        }

        let now = CFAbsoluteTimeGetCurrent()

        // Zero-blocking WindowServer fast path: during live resize/move drags, read bounds directly from CGWindowList
        // at 120Hz and project the cached AX clip/row geometry without waiting on Finder's AX main thread.
        if allowProjectionFastPath,
           !forceRescan,
           !pendingNeedsRescan,
           trackedCGWindowID != kCGNullWindowID,
           let snapshot = lastAXSnapshot,
           let primaryHeight = Self.primaryScreenHeight(),
           let liveQuartz = Self.liveWindowBoundsQuartz(windowID: trackedCGWindowID, expectedPID: trackedPID) {
            let windowMovedNow = (liveQuartz != lastLiveWindowQuartz)
            if windowMovedNow {
                lastLiveWindowQuartz = liveQuartz
                lastWindowMotionTime = now
                lastMotionTime = now
            }

            if (windowMovedNow || (now - lastWindowMotionTime < Self.axResizeDeferralInterval)) &&
                (now - lastAXSyncTime < Self.maxAXDeferralDuringDrag) {
                let liveAppKit = Self.quartzToAppKit(liveQuartz, primaryScreenHeight: primaryHeight)
                let screenVisible = Self.targetVisibleFrame(for: liveAppKit)
                if let projected = Self.projectGeometry(
                    axWindowAppKit: snapshot.windowAppKit,
                    axClipAppKit: snapshot.clipAppKit,
                    axItems: snapshot.items,
                    liveWindowAppKit: liveAppKit,
                    screenVisibleFrame: screenVisible,
                    maxItems: Self.maxTrackedItems
                ), !projected.items.isEmpty {
                    lastRenderedItems = projected.items
                    applyOverlay(clipAppKitRect: projected.clipAppKitRect, items: projected.items)
                } else {
                    hidePanel()
                }
                reconcileTimerInterval(now: now)
                return
            }
        }

        pendingNeedsRescan = false
        let appElement = AXUIElementCreateApplication(trackedPID)
        let focusedWindow = Self.axElementAttribute(appElement, attribute: kAXFocusedWindowAttribute as CFString)

        if let trackedWindow {
            guard let focusedWindow,
                  CFEqual(focusedWindow, trackedWindow) else {
                hidePanel()
                return
            }
            let subrole = Self.stringAttribute(focusedWindow, attribute: kAXSubroleAttribute as CFString)
            if subrole == "AXDialog" || subrole == "AXSheet" {
                hidePanel()
                return
            }
        } else if let focusedWindow {
            let subrole = Self.stringAttribute(focusedWindow, attribute: kAXSubroleAttribute as CFString)
            if subrole == (kAXStandardWindowSubrole as String) {
                hidePanel()
                return
            }
        }

        if containerElement == nil {
            let resolved = Self.resolveInitialElements(finderPID: trackedPID)
            containerElement = resolved.container
            scrollAreaElement = resolved.scrollArea
            if trackedWindow == nil {
                trackedWindow = resolved.window
            }
            if resolved.scrollArea != nil {
                installAXObserver(finderPID: trackedPID)
            }
        }

        guard let container = containerElement,
              let primaryHeight = Self.primaryScreenHeight() else {
            hidePanel()
            return
        }

        let isActivelyScrolling = (now - lastScrollMotionTime) < Self.scrollRescanDeferralInterval
        let rescanDue = (!isActivelyScrolling && (now - lastRescanTime >= Self.rescanInterval)) ||
            (now - lastRescanTime >= Self.maxRescanDeferralDuringScroll)
        let didRescanNow = forceRescan || cachedMatches.isEmpty || rescanDue
        if didRescanNow {
            cachedMatches = collectMatchedElements(in: container)
            lastRescanTime = now
        }

        guard !cachedMatches.isEmpty else {
            lastAXSnapshot = nil
            hidePanel()
            reconcileTimerInterval(now: now)
            return
        }

        // Tight micro-batch geometry read: sample window, scroll clip, header, and item rects together so frame shifts do not desync.
        guard let sampled = sampleGeometryBatch(
            container: container,
            primaryScreenHeight: primaryHeight,
            allowFallbackRescan: !didRescanNow
        ) else {
            hidePanel()
            return
        }

        if let windowQuartz = sampled.windowQuartz {
            let windowAppKit = Self.quartzToAppKit(windowQuartz, primaryScreenHeight: primaryHeight)
            let snapshotItems = sampled.matchedItems.map {
                FinderCutOverlayItem(rect: $0.appKitRect, isListRow: $0.isListRow)
            }
            lastAXSnapshot = (windowAppKit: windowAppKit, clipAppKit: sampled.clipAppKitRect, items: snapshotItems)
            lastAXSyncTime = now
            lastLiveWindowQuartz = windowQuartz
            if trackedCGWindowID == kCGNullWindowID {
                trackedCGWindowID = Self.resolveCGWindowID(finderPID: trackedPID, matchingQuartzRect: windowQuartz)
            }
        }

        if sampled.windowQuartz != lastWindowFrame || sampled.clipQuartz != lastClipFrame {
            lastWindowFrame = sampled.windowQuartz
            lastClipFrame = sampled.clipQuartz
            lastMotionTime = now
        }

        let localItems = Self.clippedOverlayItems(
            matchedItems: sampled.matchedItems,
            clipAppKitRect: sampled.clipAppKitRect,
            maxItems: Self.maxTrackedItems
        )
        let mergedItems = Self.mergeAdjacentItems(localItems)

        if mergedItems != lastRenderedItems {
            lastRenderedItems = mergedItems
            lastMotionTime = now
            lastScrollMotionTime = now
        }
        reconcileTimerInterval(now: now)

        guard !mergedItems.isEmpty else {
            hidePanel()
            return
        }

        applyOverlay(clipAppKitRect: sampled.clipAppKitRect, items: mergedItems)
    }

    private func applyOverlay(clipAppKitRect: CGRect, items: [FinderCutOverlayItem]) {
        let overlayPanel: FinderCutItemOverlayPanel
        let view: FinderCutItemOverlayView
        if let existingPanel = panel, let existingView = overlayView {
            overlayPanel = existingPanel
            view = existingView
        } else {
            let createdView = FinderCutItemOverlayView(frame: NSRect(origin: .zero, size: clipAppKitRect.size))
            let createdPanel = FinderCutItemOverlayPanel(
                contentRect: clipAppKitRect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            createdPanel.isFloatingPanel = false
            createdPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) + 1)
            createdPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            createdPanel.ignoresMouseEvents = true
            createdPanel.isOpaque = false
            createdPanel.backgroundColor = .clear
            createdPanel.hasShadow = false
            createdPanel.hidesOnDeactivate = false
            createdPanel.isReleasedWhenClosed = false
            createdPanel.contentView = createdView

            self.panel = createdPanel
            self.overlayView = createdView
            overlayPanel = createdPanel
            view = createdView
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        defer {
            NSAnimationContext.endGrouping()
            CATransaction.commit()
        }

        let frameChanged = overlayPanel.frame != clipAppKitRect
        let itemsChanged = view.items != items
        view.items = items

        if frameChanged {
            view.needsDisplay = true
            overlayPanel.setFrame(clipAppKitRect, display: true)
        } else if itemsChanged {
            view.displayIfNeeded()
        }

        if !overlayPanel.isVisible {
            overlayPanel.orderFrontRegardless()
        }
    }

    private struct SampledGeometry {
        let windowQuartz: CGRect?
        let clipQuartz: CGRect
        let clipAppKitRect: CGRect
        let matchedItems: [(appKitRect: CGRect, isListRow: Bool)]
    }

    private func sampleGeometryBatch(
        container: AXUIElement,
        primaryScreenHeight: CGFloat,
        allowFallbackRescan: Bool
    ) -> SampledGeometry? {
        guard let rawClipQuartz = Self.axRect(of: scrollAreaElement ?? container) else {
            return nil
        }

        let windowQuartz = trackedWindow.flatMap { Self.axRect(of: $0) }
        let headerRects = Self.headerRectsQuartz(for: container)

        var matchedItems: [(appKitRect: CGRect, isListRow: Bool)] = []
        matchedItems.reserveCapacity(cachedMatches.count)
        var missingRect = false

        for entry in cachedMatches {
            guard let itemQuartz = Self.axRect(of: entry.element) else {
                missingRect = true
                continue
            }
            matchedItems.append((
                appKitRect: Self.quartzToAppKit(itemQuartz, primaryScreenHeight: primaryScreenHeight),
                isListRow: entry.isListRow
            ))
        }

        if missingRect && allowFallbackRescan {
            cachedMatches = collectMatchedElements(in: container)
            lastRescanTime = CFAbsoluteTimeGetCurrent()
            return sampleGeometryBatch(
                container: container,
                primaryScreenHeight: primaryScreenHeight,
                allowFallbackRescan: false
            )
        }

        var clipAppKitRect = Self.quartzToAppKit(rawClipQuartz, primaryScreenHeight: primaryScreenHeight)

        guard let headerClipped = Self.clipRectBelowHeader(
            clipAppKitRect: clipAppKitRect,
            headerRectsQuartz: headerRects,
            primaryScreenHeight: primaryScreenHeight
        ) else {
            return nil
        }
        clipAppKitRect = headerClipped

        if let windowQuartz {
            let windowAppKit = Self.quartzToAppKit(windowQuartz, primaryScreenHeight: primaryScreenHeight)
            clipAppKitRect = clipAppKitRect.intersection(windowAppKit)
        }

        let screenVisibleFrame = Self.targetVisibleFrame(for: clipAppKitRect)
        clipAppKitRect = clipAppKitRect.intersection(screenVisibleFrame)

        guard !clipAppKitRect.isNull,
              clipAppKitRect.width >= 20,
              clipAppKitRect.height >= 20 else {
            return nil
        }

        return SampledGeometry(
            windowQuartz: windowQuartz,
            clipQuartz: rawClipQuartz,
            clipAppKitRect: clipAppKitRect,
            matchedItems: matchedItems
        )
    }

    private static func headerRectsQuartz(for container: AXUIElement) -> [CGRect] {
        guard let headerElement = axElementAttribute(container, attribute: kAXHeaderAttribute as CFString) else {
            return []
        }
        if let rect = axRect(of: headerElement), rect.height > 1 {
            return [rect]
        }
        guard let children = axElementArrayAttribute(headerElement, attribute: kAXChildrenAttribute as CFString, limit: 8) else {
            return []
        }
        return children.compactMap { child in
            guard let rect = axRect(of: child), rect.height > 1 else { return nil }
            return rect
        }
    }

    private static func resolveCGWindowID(finderPID: pid_t, matchingQuartzRect target: CGRect) -> CGWindowID {
        guard finderPID > 0,
              let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return kCGNullWindowID
        }

        var bestID: CGWindowID = kCGNullWindowID
        var bestScore = CGFloat.greatestFiniteMagnitude
        var soleCandidateID: CGWindowID = kCGNullWindowID
        var candidateCount = 0

        for entry in infoList {
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) == finderPID,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                  windowID != kCGNullWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] else {
                continue
            }

            candidateCount += 1
            soleCandidateID = windowID

            var rect = CGRect.zero
            let boundsCF = boundsDict as CFTypeRef
            guard CFGetTypeID(boundsCF) == CFDictionaryGetTypeID(),
                  CGRectMakeWithDictionaryRepresentation(unsafeBitCast(boundsCF, to: CFDictionary.self), &rect) else {
                continue
            }

            let score = abs(rect.minX - target.minX) +
                abs(rect.minY - target.minY) +
                abs(rect.width - target.width) +
                abs(rect.height - target.height)
            if score < bestScore {
                bestScore = score
                bestID = windowID
            }
        }

        if bestScore <= 16.0 {
            return bestID
        }
        return candidateCount == 1 ? soleCandidateID : kCGNullWindowID
    }

    private static func liveWindowBoundsQuartz(windowID: CGWindowID, expectedPID: pid_t) -> CGRect? {
        guard windowID != kCGNullWindowID,
              expectedPID > 0,
              let infoList = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let entry = infoList.first,
              (entry[kCGWindowOwnerPID as String] as? pid_t) == expectedPID,
              let boundsDict = entry[kCGWindowBounds as String],
              CFGetTypeID(boundsDict as CFTypeRef) == CFDictionaryGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        let boundsCF = boundsDict as CFTypeRef
        guard CGRectMakeWithDictionaryRepresentation(unsafeBitCast(boundsCF, to: CFDictionary.self), &rect),
              rect.width >= 40,
              rect.height >= 40 else {
            return nil
        }
        return rect
    }

    private func collectMatchedElements(
        in container: AXUIElement
    ) -> [(element: AXUIElement, isListRow: Bool)] {
        let primaryCandidates = Self.candidateElements(in: container, limit: Self.maxAXScanChildren)
        var items = matchedElements(from: primaryCandidates)

        if items.isEmpty {
            let selectedFallback = Self.selectedCandidateElements(in: container, limit: Self.maxTrackedItems)
            if !selectedFallback.isEmpty {
                items = matchedElements(from: selectedFallback)
            }
        }

        return items
    }

    private func matchedElements(
        from candidates: [AXUIElement]
    ) -> [(element: AXUIElement, isListRow: Bool)] {
        var matched: [(element: AXUIElement, isListRow: Bool)] = []
        matched.reserveCapacity(min(candidates.count, Self.maxTrackedItems))

        for candidate in candidates {
            guard let url = Self.extractURL(from: candidate, maxDepth: Self.maxAXChildDepth),
                  matchesTrackedURL(url) else {
                continue
            }
            let isListRow = Self.stringAttribute(candidate, attribute: kAXRoleAttribute as CFString) == (kAXRowRole as String)
            matched.append((element: candidate, isListRow: isListRow))
            if matched.count == Self.maxTrackedItems {
                break
            }
        }

        return matched
    }

    private func matchesTrackedURL(_ url: URL) -> Bool {
        let key = Self.normalizedFileURLKey(url)
        if trackedURLKeys.contains(key) {
            return true
        }
        let resolvedKey = Self.normalizedFileURLKey(url.resolvingSymlinksInPath())
        return trackedURLKeys.contains(resolvedKey)
    }

    // MARK: - AX Helpers

    private struct ResolvedElements {
        let container: AXUIElement?
        let scrollArea: AXUIElement?
        let window: AXUIElement?
    }

    private static func resolveInitialElements(finderPID: pid_t) -> ResolvedElements {
        let appElement = AXUIElementCreateApplication(finderPID)
        guard let focused = axElementAttribute(appElement, attribute: kAXFocusedUIElementAttribute as CFString) else {
            return ResolvedElements(container: nil, scrollArea: nil, window: nil)
        }

        let scrollArea = enclosingAncestor(from: focused, role: kAXScrollAreaRole as String, maxHops: 5)
        let window = axElementAttribute(focused, attribute: kAXWindowAttribute as CFString)
            ?? enclosingAncestor(from: focused, role: kAXWindowRole as String, maxHops: 5)
            ?? axElementAttribute(appElement, attribute: kAXFocusedWindowAttribute as CFString)

        return ResolvedElements(container: focused, scrollArea: scrollArea, window: window)
    }

    private static func enclosingAncestor(
        from startElement: AXUIElement,
        role targetRole: String,
        maxHops: Int
    ) -> AXUIElement? {
        var current: AXUIElement? = startElement
        var remaining = max(0, maxHops)

        while let element = current, remaining > 0 {
            if stringAttribute(element, attribute: kAXRoleAttribute as CFString) == targetRole {
                return element
            }
            current = axElementAttribute(element, attribute: kAXParentAttribute as CFString)
            remaining -= 1
        }
        return nil
    }

    private static func candidateElements(in container: AXUIElement, limit: Int) -> [AXUIElement] {
        for attribute in [
            kAXVisibleRowsAttribute as CFString,
            kAXVisibleChildrenAttribute as CFString,
            kAXChildrenAttribute as CFString
        ] {
            if let children = axElementArrayAttribute(container, attribute: attribute, limit: limit),
               !children.isEmpty {
                return children
            }
        }
        return []
    }

    private static func selectedCandidateElements(in container: AXUIElement, limit: Int) -> [AXUIElement] {
        for attribute in [
            kAXSelectedRowsAttribute as CFString,
            kAXSelectedChildrenAttribute as CFString
        ] {
            if let children = axElementArrayAttribute(container, attribute: attribute, limit: limit),
               !children.isEmpty {
                return children
            }
        }
        return []
    }

    private static func extractURL(from element: AXUIElement, maxDepth: Int) -> URL? {
        var urlRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef) == .success,
           let urlValue = urlRef {
            if CFGetTypeID(urlValue) == CFURLGetTypeID() {
                let url = unsafeBitCast(urlValue, to: CFURL.self) as URL
                if url.isFileURL {
                    return url
                }
            } else if let str = urlValue as? String,
                      let url = URL(string: str),
                      url.isFileURL {
                return url
            }
        }

        guard maxDepth > 0,
              let children = axElementArrayAttribute(
                element,
                attribute: kAXChildrenAttribute as CFString,
                limit: maxAXSubChildren
              ) else {
            return nil
        }

        for child in children {
            if let nestedURL = extractURL(from: child, maxDepth: maxDepth - 1) {
                return nestedURL
            }
        }

        return nil
    }

    private static func primaryScreenHeight() -> CGFloat? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? NSScreen.main?.frame.height
    }

    private static func targetVisibleFrame(for rect: CGRect) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) || $0.frame.intersects(rect) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private static let rectAttributes: CFArray = [kAXPositionAttribute as CFString, kAXSizeAttribute as CFString] as CFArray

    private static func axRect(of element: AXUIElement) -> CGRect? {
        var valuesRef: CFArray?
        if AXUIElementCopyMultipleAttributeValues(element, rectAttributes, [], &valuesRef) == .success,
           let values = valuesRef,
           CFArrayGetCount(values) == 2,
           let posPtr = CFArrayGetValueAtIndex(values, 0),
           let sizePtr = CFArrayGetValueAtIndex(values, 1) {
            let posObj = Unmanaged<AnyObject>.fromOpaque(posPtr).takeUnretainedValue()
            let sizeObj = Unmanaged<AnyObject>.fromOpaque(sizePtr).takeUnretainedValue()
            if CFGetTypeID(posObj) == AXValueGetTypeID(),
               CFGetTypeID(sizeObj) == AXValueGetTypeID() {
                var origin = CGPoint.zero
                var size = CGSize.zero
                let posAX = unsafeBitCast(posObj, to: AXValue.self)
                let sizeAX = unsafeBitCast(sizeObj, to: AXValue.self)
                if AXValueGetType(posAX) == .cgPoint,
                   AXValueGetType(sizeAX) == .cgSize,
                   AXValueGetValue(posAX, .cgPoint, &origin),
                   AXValueGetValue(sizeAX, .cgSize, &size) {
                    return CGRect(origin: origin, size: size)
                }
            }
        }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        let posAX = unsafeBitCast(posRef, to: AXValue.self)
        let sizeAX = unsafeBitCast(sizeRef, to: AXValue.self)
        guard AXValueGetValue(posAX, .cgPoint, &origin),
              AXValueGetValue(sizeAX, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private static func axElementAttribute(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    private static func axElementArrayAttribute(
        _ element: AXUIElement,
        attribute: CFString,
        limit: Int
    ) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == CFArrayGetTypeID() else {
            return nil
        }
        let cfArray = unsafeBitCast(ref, to: CFArray.self)
        let count = min(CFArrayGetCount(cfArray), max(0, limit))
        var result: [AXUIElement] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let ptr = CFArrayGetValueAtIndex(cfArray, index) else { continue }
            let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
            if CFGetTypeID(obj) == AXUIElementGetTypeID() {
                result.append(unsafeBitCast(obj, to: AXUIElement.self))
            }
        }
        return result
    }

    private static func stringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else {
            return nil
        }
        return ref as? String
    }
}
