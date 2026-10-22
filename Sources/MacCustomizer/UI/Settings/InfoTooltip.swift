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
    
    private let iconImageView = NSImageView()
    private var isHovered: Bool = false {
        didSet {
            updateIcon()
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
    
    private func setupView() {
        wantsLayer = true
        iconImageView.imageScaling = .scaleProportionallyDown
        updateIcon()
        addSubview(iconImageView)
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
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        showTooltip()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        hideTooltip()
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        showTooltip()
    }
    
    private func showTooltip() {
        guard !tooltipText.isEmpty, let window = self.window else { return }
        
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
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }
    }
    
    private func hideTooltip() {
        guard let panel = Self.activePanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            if panel.alphaValue == 0 {
                panel.orderOut(nil)
            }
        })
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            hideTooltip()
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
