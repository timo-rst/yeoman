import AppKit
import SwiftUI

@main
struct GenerateMenuBarComparison {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let outputDir = URL(fileURLWithPath: "Resources/Mockups")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let width: CGFloat = 1020
        let height: CGFloat = 276

        let view = MenuBarComparisonCanvas()
            .preferredColorScheme(.dark)
            .frame(width: width, height: height)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.orderFront(nil)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            print("Failed to create bitmap rep")
            return
        }
        rep.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("Failed to encode PNG")
            return
        }

        let destination = outputDir.appendingPathComponent("yeoman_menubar_comparison.png")
        do {
            try png.write(to: destination)
            print("Rendered \(destination.path): \(png.count / 1024) KB (\(Int(width * 2))x\(Int(height * 2)) Retina)")
        } catch {
            print("Failed to write file: \(error)")
        }
    }
}

private struct NotchCutoutShape: Shape {
    var radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct DisplayBezelTopShape: Shape {
    var radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct MenuBarComparisonCanvas: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.067, blue: 0.09)

            VStack(alignment: .leading, spacing: 18) {
                MenuBarStripRow(
                    caption: "Default macOS (16 pt spacing)",
                    itemSpacing: 17.5
                )

                MenuBarStripRow(
                    caption: "Yeoman Compact (8 pt spacing)",
                    itemSpacing: 8
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }
}

private struct MenuBarStripRow: View {
    let caption: String
    let itemSpacing: CGFloat

    private let appMenus = ["File", "Edit", "View", "Go", "Window", "Help"]
    private let thirdPartyIcons = [
        "terminal",
        "shield.lefthalf.filled",
        "calendar",
        "doc.on.clipboard",
        "computermouse"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.72))

            ZStack(alignment: .top) {
                // Realistic cropped macOS dark desktop wallpaper
                DesktopWallpaperCrop()
                    .frame(width: 980, height: 90)
                    .clipped()

                // Translucent macOS menu bar
                HStack(spacing: 0) {
                    // Left app menus
                    HStack(spacing: 14) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Finder")
                            .font(.system(size: 12.5, weight: .semibold))
                        ForEach(appMenus, id: \.self) { label in
                            Text(label)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.leading, 16)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
                .background(Color.black.opacity(0.42))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
                }

                // Right status bar items (rendered underneath the physical notch, just like macOS)
                HStack(spacing: itemSpacing) {
                    ForEach(thirdPartyIcons, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                    }

                    CompactStatsWidget()

                    Image(systemName: "wifi")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)

                    HStack(spacing: 4) {
                        Text("100%")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        Image(systemName: "battery.100percent")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white)

                    Image(systemName: "switch.2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)

                    Text("Thu 23:45")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .trailing)

                // Hardware camera notch centered on top
                NotchCutoutShape(radius: 8)
                    .fill(Color.black)
                    .frame(width: 136, height: 32)
                    .overlay(
                        Circle()
                            .fill(Color(red: 0.08, green: 0.11, blue: 0.16))
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    )
            }
            .frame(width: 980, height: 90, alignment: .top)
            .clipShape(DisplayBezelTopShape(radius: 12))
            .overlay(
                DisplayBezelTopShape(radius: 12)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.clear, Color(red: 0.055, green: 0.067, blue: 0.09).opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 18)
            }
        }
    }
}

private struct CompactStatsWidget: View {
    var body: some View {
        HStack(spacing: 6) {
            metric(label: "CPU", value: "24%", color: .blue, ratio: 0.24)
            metric(label: "RAM", value: "58%", color: .purple, ratio: 0.58)
            metric(label: "GPU", value: "14%", color: .green, ratio: 0.14)
        }
    }

    private func metric(label: String, value: String, color: Color, ratio: CGFloat) -> some View {
        HStack(spacing: 3) {
            VStack(alignment: .leading, spacing: -1) {
                Text(label)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
            }
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.18)).frame(width: 2.5, height: 15)
                Capsule().fill(color).frame(width: 2.5, height: max(3, 15 * ratio))
            }
        }
    }
}

private struct DesktopWallpaperCrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.14, blue: 0.24),
                    Color(red: 0.14, green: 0.22, blue: 0.36),
                    Color(red: 0.09, green: 0.16, blue: 0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.44, blue: 0.62).opacity(0.45), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 720, height: 140)
                .offset(x: 160, y: 26)
                .blur(radius: 18)
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.24, green: 0.28, blue: 0.56).opacity(0.42), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 560, height: 120)
                .offset(x: -210, y: 18)
                .blur(radius: 20)
        }
    }
}
