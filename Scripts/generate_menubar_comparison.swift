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
        
        let targetWidth: CGFloat = 1440
        let targetHeight: CGFloat = 340
        
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

// MARK: - Comparison View

struct ComparisonGraphicView: View {
    var body: some View {
        ZStack {
            // Elegant macOS wallpaper background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.12, green: 0.14, blue: 0.22),
                    Color(red: 0.07, green: 0.08, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle ambient glows
            RadialGradient(
                colors: [Color.blue.opacity(0.18), Color.clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.14), Color.clear],
                center: .bottomLeading,
                startRadius: 50,
                endRadius: 380
            )
            
            VStack(spacing: 24) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: "menubar.dock.rectangle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("macOS Menu Bar — Real-World Comparison")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Comparing stock macOS item padding against Yeoman's optimized layout, live stats, and widgets.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("macOS 14+ Sonoma / Sequoia")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                
                // Section 1: Default macOS
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.9))
                            Text("Default macOS Menu Bar")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("• Standard 16 pt spacing — wide gaps waste space and push icons behind the MacBook notch")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                        
                        Text("Wide Spacing (16 pt)")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.red.opacity(0.15)))
                            .foregroundColor(.red.opacity(0.9))
                    }
                    .padding(.horizontal, 28)
                    
                    StockMenuBarView()
                        .padding(.horizontal, 24)
                }
                
                // Section 2: With Yeoman
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("With Yeoman Customizer")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("• Compact 8 pt spacing + Live CPU/RAM/GPU Monitor + Web Widgets + Independent Mouse Reverser")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                        
                        Text("Optimized Layout (8 pt)")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 28)
                    
                    YeomanMenuBarView()
                        .padding(.horizontal, 24)
                }
                
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
    }
}

// MARK: - Stock Menu Bar (Wide 16pt spacing, no widgets, notch clash)

struct StockMenuBarView: View {
    var body: some View {
        ZStack {
            // Background bar
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.17).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
            
            // Content
            HStack(spacing: 0) {
                // Left Menus
                HStack(spacing: 16) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Finder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("File")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Edit")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("View")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Go")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Window")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Help")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
                .fixedSize()
                .padding(.leading, 14)
                
                Spacer()
                
                // Right Status Items: Wide 16 pt spacing
                HStack(spacing: 16) {
                    // Notch Collision Warning Badge
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("3 items hidden behind notch")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.red.opacity(0.95))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.18)))
                    .fixedSize()
                    
                    // Colliding cut-off items
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.6))
                    
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Image(systemName: "message.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Image(systemName: "wifi")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                    
                    HStack(spacing: 4) {
                        Text("100%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        Image(systemName: "battery.100")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .fixedSize()
                    
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Image(systemName: "switch.2")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text("Fri 22:45")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize()
                }
                .padding(.trailing, 14)
            }
            
            // Centered MacBook Notch
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black)
                .frame(width: 120, height: 26)
                .overlay(
                    HStack(spacing: 4) {
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 5, height: 5)
                        Text("Camera Notch")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                )
        }
        .frame(height: 36)
    }
}

// MARK: - Yeoman Menu Bar (Compact 8pt, Web Widgets, Live Stats)

struct YeomanMenuBarView: View {
    var body: some View {
        ZStack {
            // Background bar
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.12, green: 0.14, blue: 0.20).opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
            
            // Content
            HStack(spacing: 0) {
                // Left Menus
                HStack(spacing: 16) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Finder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("File")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Edit")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("View")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Go")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Window")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Help")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
                .fixedSize()
                .padding(.leading, 14)
                
                Spacer()
                
                // Right Status Items: Yeoman Compact 8 pt Spacing
                HStack(spacing: 8) {
                    // Clearance badge
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("+120 pt Clearance")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                    .fixedSize()
                    
                    // Existing third party apps (now easily fitting!)
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Image(systemName: "message.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                    
                    // Divider line between native/third-party and Yeoman additions
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 16)
                    
                    // Web Widget 1: Gemini
                    ZStack {
                        RoundedRectangle(cornerRadius: 4.5)
                            .fill(LinearGradient(colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 20, height: 20)
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                    
                    // Web Widget 2: Proton Calendar
                    ZStack {
                        RoundedRectangle(cornerRadius: 4.5)
                            .fill(Color.purple.opacity(0.45))
                            .frame(width: 20, height: 20)
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // Web Widget 3: GitHub Pulse
                    ZStack {
                        RoundedRectangle(cornerRadius: 4.5)
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 20, height: 20)
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.95))
                    }
                    
                    // Module 4: Scroll Reverser
                    Image(systemName: "computermouse.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    
                    // Module 5: System Stats Capsule Pill (Single line, monospaced)
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Text("CPU")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .fixedSize()
                            Text("14%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.cyan)
                                .fixedSize()
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.cyan)
                                .frame(width: 2.5, height: 10)
                        }
                        
                        HStack(spacing: 3) {
                            Text("RAM")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .fixedSize()
                            Text("6.2G")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.purple)
                                .fixedSize()
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.purple)
                                .frame(width: 2.5, height: 10)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.8))
                    .fixedSize()
                    
                    // Native System Items (Wi-Fi, Battery, Control Center, Clock)
                    Image(systemName: "wifi")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                    
                    HStack(spacing: 3) {
                        Text("100%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize()
                        Image(systemName: "battery.100")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .fixedSize()
                    
                    Image(systemName: "switch.2")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text("Fri 22:45")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize()
                }
                .padding(.trailing, 14)
            }
            
            // Centered MacBook Notch
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black)
                .frame(width: 120, height: 26)
                .overlay(
                    HStack(spacing: 4) {
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 5, height: 5)
                        Text("Camera Notch")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                )
        }
        .frame(height: 36)
    }
}
