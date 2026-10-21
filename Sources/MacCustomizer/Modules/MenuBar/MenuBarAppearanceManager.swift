import SwiftUI
import AppKit
import Combine

public enum MenuBarShape: String, CaseIterable, Codable {
    case full = "Durchgehend (Vollbild)"
    case split = "Geteilt (Ice Split-Capsules)"
    case floating = "Schwebend (Floating Pill)"
}

public enum MenuBarStyle: String, CaseIterable, Codable {
    case transparent = "Transparent (Wallpaper sichtbar)"
    case glassBlur = "Frosted Glass (Milchglas)"
    case solid = "Einfarbig (Tint)"
    case gradient = "Farbverlauf (Gradient)"
}

public struct MenuBarAppearancePreset: Identifiable {
    public let id: String
    public let name: String
    public let shape: MenuBarShape
    public let style: MenuBarStyle
    public let tintColor: Color
    public let gradientStart: Color
    public let gradientEnd: Color
    public let opacity: Double
    public let cornerRadius: CGFloat
    public let insetPadding: CGFloat
    public let hasBorder: Bool
    public let borderColor: Color
    public let hasShadow: Bool
    
    public static let transparentWallpaper = MenuBarAppearancePreset(
        id: "transparent",
        name: "Transparent (Wallpaper pur)",
        shape: .full,
        style: .transparent,
        tintColor: .clear,
        gradientStart: .clear,
        gradientEnd: .clear,
        opacity: 0.05,
        cornerRadius: 0,
        insetPadding: 0,
        hasBorder: false,
        borderColor: .clear,
        hasShadow: false
    )
    
    public static let iceSplit = MenuBarAppearancePreset(
        id: "ice_split",
        name: "Ice Split-Capsule",
        shape: .split,
        style: .glassBlur,
        tintColor: Color.black.opacity(0.4),
        gradientStart: Color.black.opacity(0.4),
        gradientEnd: Color.black.opacity(0.4),
        opacity: 0.65,
        cornerRadius: 12,
        insetPadding: 4,
        hasBorder: true,
        borderColor: Color.white.opacity(0.15),
        hasShadow: true
    )
    
    public static let modernFloating = MenuBarAppearancePreset(
        id: "modern_floating",
        name: "Modern Floating Bar",
        shape: .floating,
        style: .glassBlur,
        tintColor: Color.black.opacity(0.35),
        gradientStart: Color.black.opacity(0.35),
        gradientEnd: Color.black.opacity(0.35),
        opacity: 0.7,
        cornerRadius: 10,
        insetPadding: 6,
        hasBorder: true,
        borderColor: Color.white.opacity(0.2),
        hasShadow: true
    )
    
    public static let auroraGradient = MenuBarAppearancePreset(
        id: "aurora",
        name: "Aurora Farbverlauf",
        shape: .floating,
        style: .gradient,
        tintColor: .purple,
        gradientStart: Color.purple.opacity(0.6),
        gradientEnd: Color.blue.opacity(0.6),
        opacity: 0.65,
        cornerRadius: 10,
        insetPadding: 4,
        hasBorder: true,
        borderColor: Color.white.opacity(0.25),
        hasShadow: true
    )
}

final class MenuBarOverlayPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Crucial fix: AppKit's default constrainFrameRect moves windows down below visibleFrame.maxY.
        // Overriding this ensures the panel sits precisely at the menu bar frame.
        return frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: Int32) -> size_t

@_silgen_name("CGSSpaceGetType")
private func CGSSpaceGetType(_ cid: Int32, _ space: size_t) -> Int32

public final class MenuBarAppearanceManager: ObservableObject {
    public static let shared = MenuBarAppearanceManager()
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "menu_bar_appearance_enabled")
            updateOverlayPanels()
        }
    }
    
    @Published public var shape: MenuBarShape = .floating {
        didSet {
            UserDefaults.standard.set(shape.rawValue, forKey: "menu_bar_shape")
            if shape == .split {
                updateDynamicMetrics()
            }
        }
    }
    
    @Published public var style: MenuBarStyle = .glassBlur {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: "menu_bar_style")
        }
    }
    
    @Published public var opacity: Double = 0.65 {
        didSet {
            UserDefaults.standard.set(opacity, forKey: "menu_bar_opacity")
        }
    }
    
    @Published public var cornerRadius: CGFloat = 10 {
        didSet {
            UserDefaults.standard.set(cornerRadius, forKey: "menu_bar_corner_radius")
        }
    }
    
    @Published public var insetPadding: CGFloat = 4 {
        didSet {
            UserDefaults.standard.set(insetPadding, forKey: "menu_bar_inset_padding")
        }
    }
    
    @Published public var hasBorder: Bool = true {
        didSet {
            UserDefaults.standard.set(hasBorder, forKey: "menu_bar_has_border")
        }
    }
    
    @Published public var hasShadow: Bool = true {
        didSet {
            UserDefaults.standard.set(hasShadow, forKey: "menu_bar_has_shadow")
        }
    }
    
    @Published public var isDynamicSplitWidth: Bool = true {
        didSet {
            UserDefaults.standard.set(isDynamicSplitWidth, forKey: "menu_bar_dynamic_split_width")
            if isDynamicSplitWidth {
                updateDynamicMetrics()
            }
        }
    }
    
    @Published public var dynamicLeftWidth: CGFloat = 380
    @Published public var dynamicRightWidth: CGFloat = 430
    
    @Published public var tintColor: Color = Color.black.opacity(0.35)
    @Published public var gradientStart: Color = Color.purple.opacity(0.6)
    @Published public var gradientEnd: Color = Color.blue.opacity(0.6)
    
    private var overlayPanels: [MenuBarOverlayPanel] = []
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "menu_bar_appearance_enabled") as? Bool ?? false
        
        if let savedShape = UserDefaults.standard.string(forKey: "menu_bar_shape"),
           let s = MenuBarShape(rawValue: savedShape) {
            self.shape = s
        }
        if let savedStyle = UserDefaults.standard.string(forKey: "menu_bar_style"),
           let s = MenuBarStyle(rawValue: savedStyle) {
            self.style = s
        }
        if let savedOpacity = UserDefaults.standard.object(forKey: "menu_bar_opacity") as? Double {
            self.opacity = savedOpacity
        }
        if let savedCornerRadius = UserDefaults.standard.object(forKey: "menu_bar_corner_radius") as? CGFloat {
            self.cornerRadius = savedCornerRadius
        }
        if let savedInsetPadding = UserDefaults.standard.object(forKey: "menu_bar_inset_padding") as? CGFloat {
            self.insetPadding = savedInsetPadding
        }
        if let savedBorder = UserDefaults.standard.object(forKey: "menu_bar_has_border") as? Bool {
            self.hasBorder = savedBorder
        }
        if let savedShadow = UserDefaults.standard.object(forKey: "menu_bar_has_shadow") as? Bool {
            self.hasShadow = savedShadow
        }
        if let savedDynamic = UserDefaults.standard.object(forKey: "menu_bar_dynamic_split_width") as? Bool {
            self.isDynamicSplitWidth = savedDynamic
        }
        
        // Listen to display changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateOverlayPanels()
            }
            .store(in: &cancellables)
            
        // React immediately when user switches Spaces / Desktops / Fullscreen
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateVisibilityForCurrentState()
            }
            .store(in: &cancellables)
            
        // Monitor macOS System Presentation Options (hideMenuBar, autoHideMenuBar in fullscreen / presentation)
        NSApp.publisher(for: \.currentSystemPresentationOptions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateVisibilityForCurrentState()
            }
            .store(in: &cancellables)
            
        // Listen to active application changes to adapt visibility or capsule size
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self?.updateVisibilityForCurrentState()
                }
            }
            .store(in: &cancellables)
            
        // Periodic lightweight check (0.8s) to guarantee fast response to fullscreen changes and status icons
        Timer.publish(every: 0.8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateVisibilityForCurrentState()
            }
            .store(in: &cancellables)
            
        if isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.updateOverlayPanels()
            }
        }
    }
    
    public var isCurrentSpaceFullscreen: Bool {
        let cid = CGSMainConnectionID()
        let space = CGSGetActiveSpace(cid)
        let type = CGSSpaceGetType(cid, space)
        // In macOS SkyLight/CGS:
        // Type 0 or 4 = standard user desktop space
        // Type 1 = native macOS fullscreen space (kCGSSpaceFullscreen)
        return type == 1
    }
    
    public var isMenuBarHiddenBySystem: Bool {
        let options = NSApp.currentSystemPresentationOptions
        return options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
    }
    
    public var isFullScreenWindowActive: Bool {
        guard let screen = NSScreen.main else { return false }
        let sFrame = screen.frame
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        for w in list {
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "Window Server" || owner == "MacCustomizer" || owner == "de.trst.MacCustomizer" || owner == "Dock" {
                continue
            }
            if layer == 0 {
                let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
                let wVal = b["Width"] ?? 0
                let hVal = b["Height"] ?? 0
                let yVal = b["Y"] ?? 999
                if yVal <= 0 && wVal >= sFrame.width && hVal >= sFrame.height {
                    return true
                }
            }
        }
        return false
    }
    
    public var shouldShowOverlay: Bool {
        guard isEnabled else { return false }
        if isCurrentSpaceFullscreen { return false }
        if isMenuBarHiddenBySystem { return false }
        if isFullScreenWindowActive { return false }
        return true
    }
    
    public func orderPanelToBack(_ panel: NSPanel) {
        // orderFrontRegardless makes the backing surface active,
        // then orderBack(nil) puts it at the lowest z-order within .statusBar (Layer 25),
        // cleanly underneath all status items and application menus (Layer 26).
        panel.orderFrontRegardless()
        panel.orderBack(nil)
    }
    
    public func updateVisibilityForCurrentState() {
        let show = shouldShowOverlay
        for panel in overlayPanels {
            if show {
                if panel.alphaValue < 1.0 {
                    panel.animator().alphaValue = 1.0
                }
                orderPanelToBack(panel)
            } else {
                if panel.alphaValue > 0.0 {
                    panel.animator().alphaValue = 0.0
                }
            }
        }
        if show && shape == .split {
            updateDynamicMetrics()
        }
    }
    
    public func applyPreset(_ preset: MenuBarAppearancePreset) {
        self.shape = preset.shape
        self.style = preset.style
        self.tintColor = preset.tintColor
        self.gradientStart = preset.gradientStart
        self.gradientEnd = preset.gradientEnd
        self.opacity = preset.opacity
        self.cornerRadius = preset.cornerRadius
        self.insetPadding = preset.insetPadding
        self.hasBorder = preset.hasBorder
        self.hasShadow = preset.hasShadow
        if !self.isEnabled {
            self.isEnabled = true
        } else if overlayPanels.isEmpty {
            updateOverlayPanels()
        } else {
            updateVisibilityForCurrentState()
        }
        if self.shape == .split {
            updateDynamicMetrics()
        }
    }
    
    public func updateDynamicMetrics() {
        guard isEnabled && shape == .split && isDynamicSplitWidth else { return }
        
        guard let screen = NSScreen.main else { return }
        let screenWidth = screen.frame.width
        let screenMidX = screen.frame.midX
        
        var measuredLeft: CGFloat = 340
        var measuredRight: CGFloat = 400
        
        // 1. Measure active app menu items
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
            var menuBarRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
               let menuBar = menuBarRef {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let items = childrenRef as? [AXUIElement] {
                    var maxLeftX: CGFloat = 0
                    for item in items {
                        var posRef: CFTypeRef?
                        var sizeRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &posRef)
                        AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeRef)
                        var p = CGPoint.zero
                        var s = CGSize.zero
                        if let pos = posRef { AXValueGetValue(pos as! AXValue, .cgPoint, &p) }
                        if let size = sizeRef { AXValueGetValue(size as! AXValue, .cgSize, &s) }
                        if p.x < screenMidX {
                            maxLeftX = max(maxLeftX, p.x + s.width)
                        }
                    }
                    if maxLeftX > 50 {
                        measuredLeft = maxLeftX + 16.0
                    }
                }
            }
        }
        
        // 2. Measure status bar items on the right
        let options: CGWindowListOption = [.optionAll]
        if let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            var minStatusX: CGFloat = screenWidth
            var foundAny = false
            
            let myWinNumbers = Set(overlayPanels.map { $0.windowNumber })
            
            for win in infoList {
                let winNumber = win[kCGWindowNumber as String] as? Int ?? -1
                if myWinNumbers.contains(winNumber) { continue }
                
                let owner = win[kCGWindowOwnerName as String] as? String ?? ""
                if owner == "Window Server" || owner == "MacCustomizer" || owner == "de.trst.MacCustomizer" {
                    continue
                }
                
                let layer = win[kCGWindowLayer as String] as? Int ?? -1
                let bounds = win[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
                
                let y = bounds["Y"] ?? 999
                let x = bounds["X"] ?? 0
                let w = bounds["Width"] ?? 0
                let h = bounds["Height"] ?? 0
                
                // Status items are on layer 25 (or 24), Y near 0, Height around 15-45, X on the right half
                if (layer == 25 || layer == 24) && y <= 5 && h >= 15 && h <= 45 && x >= (screenMidX - 100) && w > 0 && w < 600 {
                    minStatusX = min(minStatusX, x)
                    foundAny = true
                }
            }
            
            if foundAny && minStatusX < screenWidth {
                let calculated = (screenWidth - minStatusX) + 14.0
                measuredRight = calculated
            }
        }
        
        // Clamp to guarantee neither capsule collides with notch or overlaps
        let hasNotch = screen.safeAreaInsets.top > 0
        let maxLeftAllowed: CGFloat = hasNotch ? ((screen.auxiliaryTopLeftArea?.width ?? (screenWidth * 0.42)) - 10) : (screenWidth * 0.45)
        let maxRightAllowed: CGFloat = hasNotch ? ((screenWidth - (screen.auxiliaryTopRightArea?.minX ?? (screenWidth * 0.58))) - 10) : (screenWidth * 0.45)
        
        let finalLeft = min(max(130, measuredLeft), maxLeftAllowed)
        let finalRight = min(max(130, measuredRight), maxRightAllowed)
        
        if abs(self.dynamicLeftWidth - finalLeft) > 1.5 || abs(self.dynamicRightWidth - finalRight) > 1.5 {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                self.dynamicLeftWidth = finalLeft
                self.dynamicRightWidth = finalRight
            }
        }
    }
    
    public func updateOverlayPanels() {
        // Remove existing panels
        for panel in overlayPanels {
            panel.orderOut(nil)
        }
        overlayPanels.removeAll()
        
        guard isEnabled else { return }
        
        let show = shouldShowOverlay
        for screen in NSScreen.screens {
            let panel = createOverlayPanel(for: screen)
            if show {
                panel.alphaValue = 1.0
                orderPanelToBack(panel)
            } else {
                panel.alphaValue = 0.0
            }
            overlayPanels.append(panel)
        }
        
        if show {
            updateDynamicMetrics()
        }
    }
    
    private func createOverlayPanel(for screen: NSScreen) -> MenuBarOverlayPanel {
        let mbHeight: CGFloat = {
            let diff = screen.frame.maxY - screen.visibleFrame.maxY
            if diff > 0 { return diff }
            if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
            return 24.0
        }()
        
        // Shadow padding allows shadows to render naturally downwards without clipping
        let shadowPadding: CGFloat = 8.0
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - mbHeight - shadowPadding,
            width: screen.frame.width,
            height: mbHeight + shadowPadding
        )
        
        let panel = MenuBarOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Layer 25 (.statusBar): Elevated above WindowServer background (Layer 24),
        // with orderPanelToBack ensuring it is placed underneath status icons (Layer 25)
        // and app menus (Layer 26).
        panel.level = .statusBar
        panel.collectionBehavior = [.fullScreenNone, .ignoresCycle, .moveToActiveSpace]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        
        let hostingView = NSHostingView(rootView: MenuBarOverlayRenderView(
            manager: self,
            screenFrame: frame,
            mbHeight: mbHeight,
            shadowPadding: shadowPadding,
            hasNotch: screen.safeAreaInsets.top > 0
        ))
        panel.contentView = hostingView
        
        return panel
    }
}

public struct MenuBarOverlayRenderView: View {
    @ObservedObject var manager: MenuBarAppearanceManager
    let screenFrame: NSRect
    let mbHeight: CGFloat
    let shadowPadding: CGFloat
    let hasNotch: Bool
    
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            
            VStack(spacing: 0) {
                // The native menu bar overlay region: vertically centered in mbHeight
                ZStack(alignment: .center) {
                    switch manager.shape {
                    case .full:
                        fullBackground(w: w, h: mbHeight)
                        
                    case .floating:
                        floatingBackground(w: w, h: mbHeight)
                        
                    case .split:
                        splitBackground(w: w, h: mbHeight)
                    }
                }
                .frame(width: w, height: mbHeight)
                
                // Extra space reserved for drop shadow to render smoothly without clipping
                Spacer()
                    .frame(height: shadowPadding)
            }
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private func fullBackground(w: CGFloat, h: CGFloat) -> some View {
        styledSurface()
            .frame(width: w, height: h)
            .shadow(color: manager.hasShadow ? Color.black.opacity(0.35) : .clear, radius: 4, x: 0, y: 3)
    }
    
    @ViewBuilder
    private func floatingBackground(w: CGFloat, h: CGFloat) -> some View {
        let p = manager.insetPadding
        let barWidth = max(0, w - (max(6, p * 2) * 2))
        let barHeight = max(0, h - (p * 2))
        
        styledSurface()
            .frame(width: barWidth, height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: manager.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: manager.cornerRadius)
                    .stroke(manager.hasBorder ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .shadow(color: manager.hasShadow ? Color.black.opacity(0.4) : .clear, radius: 4, x: 0, y: 2)
    }
    
    @ViewBuilder
    private func splitBackground(w: CGFloat, h: CGFloat) -> some View {
        let p = manager.insetPadding
        let barHeight = max(0, h - (p * 2))
        
        let maxLeft = hasNotch ? (w * 0.42) : (w * 0.46)
        let maxRight = hasNotch ? (w * 0.42) : (w * 0.46)
        
        let targetLeft = manager.isDynamicSplitWidth ? min(max(130, manager.dynamicLeftWidth), maxLeft) : (w * 0.42)
        let targetRight = manager.isDynamicSplitWidth ? min(max(130, manager.dynamicRightWidth), maxRight) : (w * 0.42)
        
        HStack(spacing: 0) {
            // Left App Menus Capsule
            styledSurface()
                .frame(width: targetLeft, height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: manager.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: manager.cornerRadius)
                        .stroke(manager.hasBorder ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                .shadow(color: manager.hasShadow ? Color.black.opacity(0.4) : .clear, radius: 4, x: 0, y: 2)
            
            Spacer(minLength: hasNotch ? 160 : 30)
            
            // Right Status Items Capsule
            styledSurface()
                .frame(width: targetRight, height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: manager.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: manager.cornerRadius)
                        .stroke(manager.hasBorder ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                .shadow(color: manager.hasShadow ? Color.black.opacity(0.4) : .clear, radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, max(6, p * 2))
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: manager.dynamicLeftWidth)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: manager.dynamicRightWidth)
    }
    
    @ViewBuilder
    private func styledSurface() -> some View {
        switch manager.style {
        case .transparent:
            Color.clear
            
        case .glassBlur:
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                manager.tintColor.opacity(manager.opacity)
            }
            
        case .solid:
            manager.tintColor.opacity(manager.opacity)
            
        case .gradient:
            LinearGradient(
                colors: [
                    manager.gradientStart.opacity(manager.opacity),
                    manager.gradientEnd.opacity(manager.opacity)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
