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

public final class MenuBarAppearanceManager: ObservableObject {
    public static let shared = MenuBarAppearanceManager()
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "menu_bar_appearance_enabled")
            updateOverlayPanels()
        }
    }
    
    @Published public var shape: MenuBarShape = .floating
    @Published public var style: MenuBarStyle = .glassBlur
    @Published public var opacity: Double = 0.65
    @Published public var cornerRadius: CGFloat = 10
    @Published public var insetPadding: CGFloat = 4
    @Published public var hasBorder: Bool = true
    @Published public var hasShadow: Bool = true
    @Published public var tintColor: Color = Color.black.opacity(0.35)
    @Published public var gradientStart: Color = Color.purple.opacity(0.6)
    @Published public var gradientEnd: Color = Color.blue.opacity(0.6)
    
    private var overlayPanels: [NSPanel] = []
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "menu_bar_appearance_enabled") as? Bool ?? false
        
        // Listen to display changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateOverlayPanels()
            }
            .store(in: &cancellables)
            
        if isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.updateOverlayPanels()
            }
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
        }
    }
    
    public func updateOverlayPanels() {
        // Remove existing panels
        for panel in overlayPanels {
            panel.orderOut(nil)
        }
        overlayPanels.removeAll()
        
        guard isEnabled else { return }
        
        for screen in NSScreen.screens {
            let panel = createOverlayPanel(for: screen)
            panel.orderFrontRegardless()
            overlayPanels.append(panel)
        }
    }
    
    private func createOverlayPanel(for screen: NSScreen) -> NSPanel {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarHeight,
            width: screen.frame.width,
            height: menuBarHeight
        )
        
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Layer 23: directly below system menu bar items (layer 24 / 25)
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        
        let hostingView = NSHostingView(rootView: MenuBarOverlayRenderView(
            manager: self,
            screenFrame: frame,
            hasNotch: screen.safeAreaInsets.top > 0
        ))
        panel.contentView = hostingView
        
        return panel
    }
}

public struct MenuBarOverlayRenderView: View {
    @ObservedObject var manager: MenuBarAppearanceManager
    let screenFrame: NSRect
    let hasNotch: Bool
    
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            switch manager.shape {
            case .full:
                fullBackground(w: w, h: h)
                
            case .floating:
                floatingBackground(w: w, h: h)
                
            case .split:
                splitBackground(w: w, h: h)
            }
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private func fullBackground(w: CGFloat, h: CGFloat) -> some View {
        styledSurface()
            .frame(width: w, height: h)
    }
    
    @ViewBuilder
    private func floatingBackground(w: CGFloat, h: CGFloat) -> some View {
        let p = manager.insetPadding
        styledSurface()
            .clipShape(RoundedRectangle(cornerRadius: manager.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: manager.cornerRadius)
                    .stroke(manager.hasBorder ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
            )
            .shadow(color: manager.hasShadow ? Color.black.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
            .padding(.horizontal, p * 2)
            .padding(.vertical, p)
    }
    
    @ViewBuilder
    private func splitBackground(w: CGFloat, h: CGFloat) -> some View {
        let p = manager.insetPadding
        HStack(spacing: hasNotch ? 180 : 80) {
            // Left App Menus Capsule
            styledSurface()
                .frame(width: w * 0.42)
                .clipShape(RoundedRectangle(cornerRadius: manager.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: manager.cornerRadius)
                        .stroke(manager.hasBorder ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                )
                .shadow(color: manager.hasShadow ? Color.black.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
            
            Spacer()
            
            // Right Status Items Capsule
            styledSurface()
                .frame(width: w * 0.42)
                .clipShape(RoundedRectangle(cornerRadius: manager.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: manager.cornerRadius)
                        .stroke(manager.hasBorder ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                )
                .shadow(color: manager.hasShadow ? Color.black.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, p * 2)
        .padding(.vertical, p)
    }
    
    @ViewBuilder
    private func styledSurface() -> some View {
        switch manager.style {
        case .transparent:
            Color.clear
            
        case .glassBlur:
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(manager.tintColor.opacity(manager.opacity))
            
        case .solid:
            manager.tintColor.opacity(manager.opacity)
            
        case .gradient:
            LinearGradient(
                colors: [manager.gradientStart.opacity(manager.opacity), manager.gradientEnd.opacity(manager.opacity)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
