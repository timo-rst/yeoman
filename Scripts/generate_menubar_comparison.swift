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

        let targetWidth: CGFloat = 740
        let targetHeight: CGFloat = 330

        let view = ComparisonGraphicView()
            .preferredColorScheme(.dark)
            .frame(width: targetWidth, height: targetHeight)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
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

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

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
            print("✅ Successfully generated menu bar comparison: \(destination.path) (\(png.count / 1024) KB)")
        } catch {
            print("❌ Failed to write file: \(error)")
        }
    }
}

// MARK: - Notch Shape (Hardware accurate rounded bottom corners)

struct MacBookNotchShape: Shape {
    var cornerRadius: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Main Comparison View

struct ComparisonGraphicView: View {
    var body: some View {
        ZStack {
            // Elegant dark macOS desktop gradient
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.15),
                    Color(red: 0.11, green: 0.13, blue: 0.21),
                    Color(red: 0.06, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Ambient background lighting
            RadialGradient(
                colors: [Color.blue.opacity(0.18), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 340
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.14), Color.clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 320
            )

            VStack(spacing: 16) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 7) {
                            Image(systemName: "menubar.dock.rectangle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("macOS Menu Bar — Real-World MacBook Notch Test")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("16 pt standard spacing collides with the notch • Yeoman 8 pt layout gives +140 pt clearance")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()

                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("macOS 14+ Sonoma / Sequoia")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                // Section 1: Default macOS Menu Bar (Hits the Notch!)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.9))
                            Text("Default macOS Menu Bar")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text("• Standard 16 pt gaps push items into the notch — 3 icons cut off & invisible")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.6))

                        Spacer()

                        Text("16 pt Spacing • Notch Collision")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundColor(.red.opacity(0.95))
                    }
                    .padding(.horizontal, 22)

                    StockCollidingBarView()
                        .padding(.horizontal, 20)
                }

                // Section 2: With Yeoman Customizer (Generous +140 pt Clearance)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                            Text("With Yeoman Customizer")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text("• Compact 8 pt spacing + System Monitor + Widgets fit with room to spare")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.6))

                        Spacer()

                        Text("8 pt Spacing • +140 pt Clearance")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 22)

                    YeomanClearanceBarView()
                        .padding(.horizontal, 20)
                }

                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
    }
}

// MARK: - Section 1: Stock Menu Bar (Icons collide directly into Notch!)

struct StockCollidingBarView: View {
    private let notchWidth: CGFloat = 110
    private let barHeight: CGFloat = 36

    var body: some View {
        ZStack(alignment: .leading) {
            // Background bar
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.17).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            // Status items anchored to TRAILING edge.
            // With 19 items and 16 pt spacing, the items physically span 625+ pt,
            // colliding directly with the notch (0 gap!).
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: 16) {
                    Group {
                        Image(systemName: "shield.lefthalf.filled") // Tailscale / VPN (hitting the notch line)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "cloud.fill") // Nextcloud
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "shippingbox.fill") // Docker
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "moon.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "lock.shield.fill") // 1Password
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "message.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "bubble.left.and.bubble.right.fill") // Slack
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "command") // Raycast
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()
                    }

                    Group {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "music.note")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "wifi")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        HStack(spacing: 3) {
                            Text("100%")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                            Image(systemName: "battery.100")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .fixedSize()

                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Image(systemName: "switch.2")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()

                        Text("Fri 22:45")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()
                    }
                }
                .padding(.trailing, 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // MacBook Hardware Notch (Sits at the top-left, physically cutting off overflowing icons)
            ZStack(alignment: .leading) {
                // Solid black notch cutout
                MacBookNotchShape(cornerRadius: 6)
                    .fill(Color.black)
                    .frame(width: notchWidth, height: barHeight - 4)
                    .overlay(
                        MacBookNotchShape(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )

                // Inside the notch: Camera lens + hidden items callout
                HStack(spacing: 6) {
                    // Camera lens
                    Circle()
                        .fill(Color(white: 0.22))
                        .frame(width: 5.5, height: 5.5)
                        .overlay(Circle().fill(Color.blue.opacity(0.35)).frame(width: 2.5, height: 2.5))
                        .padding(.leading, 7)

                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7.5))
                            .foregroundColor(.red)
                        Text("3 items hidden")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.red)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: notchWidth)

                // Red cut-off collision line exactly at the notch boundary
                Rectangle()
                    .fill(Color.red.opacity(0.95))
                    .frame(width: 2, height: barHeight)
                    .offset(x: notchWidth)
            }
        }
        .frame(height: barHeight)
    }
}

// MARK: - Section 2: Yeoman Menu Bar (Same Notch, but +140 pt Clearance!)

struct YeomanClearanceBarView: View {
    private let notchWidth: CGFloat = 110
    private let barHeight: CGFloat = 36

    var body: some View {
        ZStack(alignment: .leading) {
            // Background bar
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.12, green: 0.14, blue: 0.20).opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )

            // Status items with compact 7.5 pt spacing anchored to the exact same trailing edge
            HStack(spacing: 0) {
                Spacer()

                HStack(spacing: 7.5) {
                    // Third-party apps
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))

                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))

                    Image(systemName: "message.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 13)

                    // Yeoman Web Widgets
                    Image(systemName: "sparkles")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))

                    Image(systemName: "calendar")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))

                    // Yeoman Clipboard
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))

                    // Yeoman Scroll Reverser
                    Image(systemName: "computermouse")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))

                    // Yeoman System Monitor (Real MenuBarStatsWidgetView design: CPU, RAM, GPU)
                    HStack(spacing: 4.5) {
                        // CPU
                        HStack(spacing: 2.5) {
                            VStack(alignment: .trailing, spacing: -1) {
                                Text("CPU")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                    .fixedSize()
                                Text("14%")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                            }

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 3.5, height: 14)

                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.blue)
                                    .frame(width: 3.5, height: max(1.5, 14.0 * 0.14))
                            }
                        }
                        .fixedSize()

                        // RAM
                        HStack(spacing: 2.5) {
                            VStack(alignment: .trailing, spacing: -1) {
                                Text("RAM")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.purple)
                                    .lineLimit(1)
                                    .fixedSize()
                                Text("62%")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                            }

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 3.5, height: 14)

                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.purple)
                                    .frame(width: 3.5, height: max(1.5, 14.0 * 0.62))
                            }
                        }
                        .fixedSize()

                        // GPU
                        HStack(spacing: 2.5) {
                            VStack(alignment: .trailing, spacing: -1) {
                                Text("GPU")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                                    .fixedSize()
                                Text("8%")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                            }

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 3.5, height: 14)

                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.green)
                                    .frame(width: 3.5, height: max(2.0, 14.0 * 0.08))
                            }
                        }
                        .fixedSize()
                    }
                    .frame(height: 18)
                    .fixedSize()

                    // Native System Items
                    Image(systemName: "wifi")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))

                    HStack(spacing: 3) {
                        Text("100%")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()
                        Image(systemName: "battery.100")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .fixedSize()

                    Image(systemName: "switch.2")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))

                    Text("Fri 22:45")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize()
                }
                .padding(.trailing, 10)
            }

            // Left Side: Same Notch + Genuine Clearance Dimension Line
            HStack(spacing: 0) {
                // MacBook Camera Notch (Identical to top bar)
                ZStack(alignment: .leading) {
                    MacBookNotchShape(cornerRadius: 6)
                        .fill(Color.black)
                        .frame(width: notchWidth, height: barHeight - 4)
                        .overlay(
                            MacBookNotchShape(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )

                    // Camera lens
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(white: 0.22))
                            .frame(width: 5.5, height: 5.5)
                            .overlay(Circle().fill(Color.blue.opacity(0.35)).frame(width: 2.5, height: 2.5))
                            .padding(.leading, 7)
                        Spacer()
                    }
                    .frame(width: notchWidth)
                }

                // The Genuine Clearance Zone (Span between notch and items)
                HStack(spacing: 4.5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .bold))
                    Text("+140 pt Clearance")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(Color.green.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5)
                        .stroke(Color.green.opacity(0.4), lineWidth: 0.8)
                )
                .fixedSize()
                .padding(.leading, 8)

                Spacer()
            }
        }
        .frame(height: barHeight)
    }
}
