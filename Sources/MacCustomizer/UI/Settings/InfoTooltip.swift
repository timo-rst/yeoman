import SwiftUI
import AppKit

// MARK: - Instant Native Hover Tooltip

public struct InfoTooltip: View {
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        InfoTooltipRepresentable(text: text)
            .frame(width: 16, height: 16)
    }
}

struct InfoTooltipRepresentable: NSViewRepresentable {
    let text: String
    
    func makeNSView(context: Context) -> TooltipNSView {
        let view = TooltipNSView()
        view.tooltipText = text
        return view
    }
    
    func updateNSView(_ nsView: TooltipNSView, context: Context) {
        nsView.tooltipText = text
    }
}

final class TooltipNSView: NSView {
    var tooltipText: String = "" {
        didSet {
            updateIcon()
        }
    }
    
    private var trackingArea: NSTrackingArea?
    private static var activePanel: NSPanel?
    private static var activeLabel: NSTextField?
    private static weak var currentHoveredView: TooltipNSView?
    private static var hoveredViews = NSHashTable<TooltipNSView>.weakObjects()
    private static var hoverEventMonitor: Any?
    private static var didSetupScrollObserver = false
    private static var lastScrollTimestamp: CFTimeInterval = 0
    
    private var showTimer: Timer?
    private let iconImageView = NSImageView()
    private var isHovered: Bool = false {
        didSet {
            guard oldValue != isHovered else { return }
            updateIcon()
            if isHovered {
                Self.hoveredViews.add(self)
                Self.startHoverMonitorIfNeeded()
            } else {
                Self.hoveredViews.remove(self)
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    deinit {
        showTimer?.invalidate()
        isHovered = false
        if Self.currentHoveredView === self {
            Self.hideActiveTooltip(animated: false)
        }
    }
    
    private func setupView() {
        wantsLayer = true
        iconImageView.imageScaling = .scaleProportionallyDown
        updateIcon()
        addSubview(iconImageView)
        Self.setupGlobalScrollObserverIfNeeded()
    }
    
    override func layout() {
        super.layout()
        let iconSize: CGFloat = 13
        iconImageView.frame = NSRect(
            x: (bounds.width - iconSize) / 2,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
    }
    
    private func updateIcon() {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let name = isHovered ? "info.circle.fill" : "info.circle"
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: tooltipText)?.withSymbolConfiguration(config) {
            iconImageView.image = img
            iconImageView.contentTintColor = isHovered ? .controlAccentColor : .secondaryLabelColor
        }
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    // MARK: - Global Scroll and Event Observers
    
    private static func setupGlobalScrollObserverIfNeeded() {
        guard !didSetupScrollObserver else { return }
        didSetupScrollObserver = true
        
        let center = NotificationCenter.default
        
        // Listen to scroll view bounds changes (stepped wheel, trackpad, scrollbar, etc.)
        center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleScroll()
        }
        
        // Listen to live scrolling start & update
        center.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleScroll()
        }
        
        center.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleScroll()
        }
        
        center.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleScroll()
        }
        
        // Intercept all scroll wheel events directly from the event stream
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            handleScroll()
            return event
        }
    }
    
    private static func handleScroll() {
        lastScrollTimestamp = CACurrentMediaTime()
        
        let all = hoveredViews.allObjects
        hoveredViews.removeAllObjects()
        for view in all {
            view.showTimer?.invalidate()
            view.showTimer = nil
            view.isHovered = false
        }
        
        hideActiveTooltip(animated: false)
    }
    
    private static func startHoverMonitorIfNeeded() {
        guard hoverEventMonitor == nil else { return }
        hoverEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { event in
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                handleScroll()
                return event
            }
            
            // On mouse move: verify all hovered views still genuinely contain the cursor
            let all = hoveredViews.allObjects
            for view in all {
                guard let window = view.window else {
                    view.isHovered = false
                    continue
                }
                let mouseLoc = window.mouseLocationOutsideOfEventStream
                let localPoint = view.convert(mouseLoc, from: nil)
                if !view.bounds.contains(localPoint) {
                    view.isHovered = false
                    if currentHoveredView === view {
                        hideActiveTooltip(animated: true)
                    }
                }
            }
            
            if hoveredViews.allObjects.isEmpty && activePanel?.isVisible != true {
                stopHoverMonitor()
            }
            
            return event
        }
    }
    
    private static func stopHoverMonitor() {
        if let monitor = hoverEventMonitor {
            NSEvent.removeMonitor(monitor)
            hoverEventMonitor = nil
        }
    }
    
    static func hideActiveTooltip(animated: Bool = true) {
        if let active = currentHoveredView {
            active.showTimer?.invalidate()
            active.showTimer = nil
            active.isHovered = false
        }
        currentHoveredView = nil
        
        guard let panel = activePanel, panel.isVisible else { return }
        
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.1
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                if currentHoveredView == nil {
                    panel.orderOut(nil)
                    panel.alphaValue = 0.0
                }
            })
        } else {
            panel.animator().alphaValue = 0.0
            panel.alphaValue = 0.0
            panel.orderOut(nil)
        }
    }
    
    // MARK: - Mouse Hover & Interaction
    
    private func scheduleShow() {
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            guard let self = self, self.isHovered else { return }
            
            // Double check scrolling didn't happen while timer was waiting
            if CACurrentMediaTime() - Self.lastScrollTimestamp < 0.15 {
                self.isHovered = false
                return
            }
            
            // Confirm mouse cursor is genuinely inside this view
            guard let window = self.window else { return }
            let mouseLoc = window.mouseLocationOutsideOfEventStream
            let localPoint = self.convert(mouseLoc, from: nil)
            guard self.bounds.contains(localPoint) else {
                self.isHovered = false
                return
            }
            
            self.showTooltip()
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // If the user was scrolling in the last 150ms, this was triggered by scrolling past cursor
        if CACurrentMediaTime() - Self.lastScrollTimestamp < 0.15 {
            isHovered = false
            return
        }
        isHovered = true
        scheduleShow()
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if CACurrentMediaTime() - Self.lastScrollTimestamp < 0.15 {
            isHovered = false
            return
        }
        if !isHovered {
            isHovered = true
            scheduleShow()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        showTimer?.invalidate()
        showTimer = nil
        if Self.currentHoveredView === self {
            Self.hideActiveTooltip(animated: true)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        showTimer?.invalidate()
        showTimer = nil
        isHovered = true
        showTooltip()
    }
    
    private func showTooltip() {
        guard !tooltipText.isEmpty, let window = self.window else { return }
        
        Self.currentHoveredView = self
        Self.startHoverMonitorIfNeeded()
        
        let panel = Self.getOrCreatePanel()
        guard let label = Self.activeLabel else { return }
        
        let font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.font = font
        label.stringValue = tooltipText
        
        let maxLabelWidth: CGFloat = 280
        label.preferredMaxLayoutWidth = maxLabelWidth
        let fit = label.sizeThatFits(NSSize(width: maxLabelWidth, height: CGFloat.greatestFiniteMagnitude))
        
        let labelW = max(70, min(maxLabelWidth, ceil(fit.width) + 2))
        let labelH = ceil(fit.height) + 6
        let padX: CGFloat = 12
        let padY: CGFloat = 10
        let panelW = labelW + (padX * 2)
        let panelH = labelH + (padY * 2)
        
        label.frame = NSRect(x: padX, y: padY, width: labelW, height: labelH)
        
        let viewRectInWindow = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(viewRectInWindow)
        
        var originX = screenRect.midX - (panelW / 2)
        var originY = screenRect.maxY + 5
        
        if let screen = window.screen ?? NSScreen.main {
            let screenVisible = screen.visibleFrame
            if originX < screenVisible.minX + 8 {
                originX = screenVisible.minX + 8
            } else if originX + panelW > screenVisible.maxX - 8 {
                originX = screenVisible.maxX - panelW - 8
            }
            if originY + panelH > screenVisible.maxY - 8 {
                originY = screenRect.minY - panelH - 5
            }
        }
        
        panel.setFrame(NSRect(x: originX, y: originY, width: panelW, height: panelH), display: true)
        if !panel.isVisible || panel.alphaValue < 0.1 {
            panel.alphaValue = 0.0
        }
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        showTimer?.invalidate()
        showTimer = nil
        if newWindow == nil && Self.currentHoveredView === self {
            Self.hideActiveTooltip(animated: false)
        }
    }
    
    private static func getOrCreatePanel() -> NSPanel {
        if let existing = activePanel {
            return existing
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = true
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 8
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor
        
        let label = NSTextField(labelWithString: "")
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isSelectable = false
        
        visualEffect.addSubview(label)
        panel.contentView = visualEffect
        
        activePanel = panel
        activeLabel = label
        return panel
    }
}
