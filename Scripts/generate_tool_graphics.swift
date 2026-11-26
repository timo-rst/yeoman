import AppKit
import CoreText
import SwiftUI
import YeomanCore

@main
struct GenerateToolGraphics {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let outputDir = URL(fileURLWithPath: "Resources/Mockups")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        capture(
            view: TerminalSaverShowcaseGraphic().preferredColorScheme(.dark),
            width: 960,
            height: 490,
            to: outputDir.appendingPathComponent("yeoman_terminal_saver_showcase.png")
        )

        capture(
            view: FinderCutGraphic().preferredColorScheme(.dark),
            width: 860,
            height: 420,
            to: outputDir.appendingPathComponent("yeoman_finder_cut.png")
        )

        capture(
            view: SystemMonitorGraphic().preferredColorScheme(.dark),
            width: 860,
            height: 430,
            to: outputDir.appendingPathComponent("yeoman_system_stats.png")
        )

        capture(
            view: ScrollReverserGraphic().preferredColorScheme(.dark),
            width: 860,
            height: 270,
            to: outputDir.appendingPathComponent("yeoman_scroll_reverser.png")
        )
    }

    @MainActor
    static func capture<V: View>(view: V, width: CGFloat, height: CGFloat, to url: URL) {
        let sized = view.frame(width: width, height: height)
        let hostingView = NSHostingView(rootView: sized)
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
            print("Failed bitmap rep for \(url.lastPathComponent)")
            return
        }
        rep.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("Failed PNG encoding for \(url.lastPathComponent)")
            return
        }
        do {
            try png.write(to: url)
            print("Rendered \(url.lastPathComponent): \(png.count / 1024) KB (\(Int(width * 2))x\(Int(height * 2)) Retina)")
        } catch {
            print("Failed writing \(url.lastPathComponent): \(error)")
        }
    }
}

// MARK: - Shared Dark-Glass Backdrop

private struct DarkGlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.13),
                    Color(red: 0.10, green: 0.12, blue: 0.19),
                    Color(red: 0.05, green: 0.06, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.blue.opacity(0.16), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.10), Color.clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 320
            )
        }
    }
}

private struct HeaderPill: View {
    let text: String
    var dotColor: Color = .green

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - 1. Terminal Saver Live Engine Showcase

private struct TerminalSaverShowcaseGraphic: View {
    private static func warmedPipesFrame(columns: Int, rows: Int) -> ASCIIFrame {
        var latest = ASCIIFrame(columns: columns, rows: rows)
        for step in 1...110 {
            latest = TerminalSaverProceduralScenes.frame(
                scene: .pipes,
                columns: columns,
                rows: rows,
                time: Double(step) * 0.08
            )
        }
        return latest
    }

    private let bonfireImage = renderASCIIToImage(
        TerminalSaverProceduralScenes.frame(scene: .bonfire, columns: 48, rows: 12, time: 1.6),
        width: 452,
        height: 158
    )
    private let donutImage = renderASCIIToImage(
        TerminalSaverProceduralScenes.frame(scene: .spinningDonut, columns: 48, rows: 12, time: 2.3),
        width: 452,
        height: 158
    )
    private let pipesImage = renderASCIIToImage(
        warmedPipesFrame(columns: 48, rows: 12),
        width: 452,
        height: 158
    )
    private let matrixImage = renderASCIIToImage(
        TerminalSaverProceduralScenes.frame(scene: .matrix, columns: 48, rows: 12, time: 3.1),
        width: 452,
        height: 158
    )

    var body: some View {
        ZStack {
            DarkGlassBackdrop()

            VStack(spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("Terminal Saver — Filigree Edge-Aware ASCII Engine")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Genuine procedural engine output rendered cell-by-cell • Supports custom GIF, MP4, and PNG media")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    HeaderPill(text: "TrueColor & xterm-256")
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)

                Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        TerminalSceneCard(title: "Bonfire", tag: "Procedural Flame", image: bonfireImage)
                        TerminalSceneCard(title: "3D Donut", tag: "Filigree / Strokes", image: donutImage)
                    }
                    GridRow {
                        TerminalSceneCard(title: "Pipes", tag: "Endless Network", image: pipesImage)
                        TerminalSceneCard(title: "Matrix", tag: "Code Rain", image: matrixImage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
    }
}

private struct TerminalSceneCard: View {
    let title: String
    let tag: String
    let image: NSImage

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 1.0, green: 0.76, blue: 0.18)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.28)).frame(width: 8, height: 8)
                }
                Text("zsh — \(title)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(tag)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.60))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color(red: 0.13, green: 0.14, blue: 0.17))

            Divider().background(Color.white.opacity(0.1))

            Image(nsImage: image)
                .resizable()
                .frame(maxWidth: .infinity)
                .frame(height: 158)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
    }
}

private func renderASCIIToImage(_ frame: ASCIIFrame, width: Int, height: Int) -> NSImage {
    let scale = 2
    let pixelW = width * scale
    let pixelH = height * scale
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelW,
        pixelsHigh: pixelH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return image }
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return image
    }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.setFillColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1.0)
    ctx.fill(CGRect(origin: .zero, size: size))

    if frame.columns > 0 && frame.rows > 0 {
        let insetX: CGFloat = 12
        let insetY: CGFloat = 10
        let availW = CGFloat(width) - insetX * 2
        let availH = CGFloat(height) - insetY * 2
        let lineHeightFactor: CGFloat = 1.12
        let maxFontH = availH / (CGFloat(frame.rows) * lineHeightFactor)
        let maxFontW = availW / (CGFloat(frame.columns) * 0.62)
        let fontSize = max(6.0, min(maxFontH, maxFontW))
        let lineHeight = fontSize * lineHeightFactor

        let nsFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let ctFont = nsFont as CTFont
        let ascent = CTFontGetAscent(ctFont)

        var mChar: UniChar = 0x4D
        var mGlyph: CGGlyph = 0
        var advance = CGSize.zero
        if CTFontGetGlyphsForCharacters(ctFont, &mChar, &mGlyph, 1) {
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &mGlyph, &advance, 1)
        }
        let cellWidth = max(fontSize * 0.48, advance.width > 0 ? advance.width : fontSize * 0.6)
        let drawnWidth = CGFloat(frame.columns) * cellWidth
        let drawnHeight = CGFloat(frame.rows) * lineHeight
        let originX = insetX + max(0, (availW - drawnWidth) * 0.5)
        let topOffset = insetY + max(0, (availH - drawnHeight) * 0.5)

        ctx.textMatrix = .identity
        for y in 0..<frame.rows {
            // CoreGraphics bitmap context origin is bottom-left.
            let baselineY = CGFloat(height) - (topOffset + CGFloat(y) * lineHeight + ascent)
            for x in 0..<frame.columns {
                let cell = frame[x, y]
                guard !cell.isBlank else { continue }
                let utf16 = Array(cell.character.utf16)
                guard utf16.count == 1 else { continue }
                var codeUnit = utf16[0]
                var glyph: CGGlyph = 0
                guard CTFontGetGlyphsForCharacters(ctFont, &codeUnit, &glyph, 1), glyph != 0 else { continue }
                var pos = CGPoint(x: originX + CGFloat(x) * cellWidth, y: baselineY)
                ctx.setFillColor(
                    red: CGFloat(cell.red) / 255.0,
                    green: CGFloat(cell.green) / 255.0,
                    blue: CGFloat(cell.blue) / 255.0,
                    alpha: 1.0
                )
                CTFontDrawGlyphs(ctFont, &glyph, &pos, 1, ctx)
            }
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(rep)
    return image
}

// MARK: - 2. Finder Cut Graphic

private struct FinderRowItem: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let name: String
    let modified: String
    let size: String
    let kind: String
    let isCut: Bool
}

private struct FinderCutGraphic: View {
    private let rows: [FinderRowItem] = [
        FinderRowItem(icon: "folder.fill", iconColor: .blue, name: "Sources", modified: "Today at 11:42", size: "--", kind: "Folder", isCut: false),
        FinderRowItem(icon: "doc.text.fill", iconColor: .cyan, name: "RELEASE_NOTES.md", modified: "Today at 12:18", size: "4 KB", kind: "Markdown Document", isCut: true),
        FinderRowItem(icon: "shippingbox.fill", iconColor: .orange, name: "Yeoman-0.3.0.dmg", modified: "Today at 12:19", size: "4.4 MB", kind: "Disk Image", isCut: true),
        FinderRowItem(icon: "folder.fill", iconColor: .blue, name: "Scripts", modified: "Yesterday at 17:10", size: "--", kind: "Folder", isCut: false),
        FinderRowItem(icon: "doc.richtext", iconColor: .gray, name: "README.md", modified: "Today at 12:20", size: "11 KB", kind: "Markdown Document", isCut: false)
    ]

    var body: some View {
        ZStack {
            DarkGlassBackdrop()

            VStack(spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 8) {
                            Image(systemName: "scissors")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("Finder Cut — Windows-Style Cut & Paste with Live Highlight")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Delegates natively via Finder Accessibility actions • Preserves Undo and conflict dialogs • Clips cleanly under headers")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    HeaderPill(text: "Finder-Only Scope")
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)

                // Finder window chrome
                VStack(spacing: 0) {
                    // Finder toolbar
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 10, height: 10)
                            Circle().fill(Color(red: 1.0, green: 0.76, blue: 0.18)).frame(width: 10, height: 10)
                            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.28)).frame(width: 10, height: 10)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.45))
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.25))
                        }
                        .padding(.leading, 4)

                        Text("Yeoman Release Staging")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))

                        Spacer()

                        HStack(spacing: 5) {
                            Image(systemName: "scissors")
                                .font(.system(size: 10))
                            Text("2 items marked for move")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color(red: 0.15, green: 0.16, blue: 0.19))

                    Divider().background(Color.white.opacity(0.1))

                    // Finder column headers
                    HStack {
                        Text("Name").frame(width: 280, alignment: .leading)
                        Text("Date Modified").frame(width: 170, alignment: .leading)
                        Text("Size").frame(width: 100, alignment: .trailing)
                        Spacer()
                        Text("Kind").frame(width: 160, alignment: .leading)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 16)
                    .frame(height: 26)
                    .background(Color(red: 0.12, green: 0.13, blue: 0.15))

                    Divider().background(Color.white.opacity(0.08))

                    // List rows + merged cut overlay
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                HStack {
                                    HStack(spacing: 8) {
                                        Image(systemName: row.icon)
                                            .font(.system(size: 13))
                                            .foregroundColor(row.iconColor.opacity(row.isCut ? 0.55 : 0.95))
                                            .frame(width: 18)
                                        Text(row.name)
                                            .font(.system(size: 12, weight: row.isCut ? .medium : .regular))
                                            .foregroundColor(.white.opacity(row.isCut ? 0.62 : 0.92))
                                    }
                                    .frame(width: 280, alignment: .leading)

                                    Text(row.modified)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.white.opacity(0.52))
                                        .frame(width: 170, alignment: .leading)

                                    Text(row.size)
                                        .font(.system(size: 11.5).monospacedDigit())
                                        .foregroundColor(.white.opacity(0.52))
                                        .frame(width: 100, alignment: .trailing)

                                    Spacer()

                                    Text(row.kind)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.white.opacity(0.52))
                                        .frame(width: 160, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(index.isMultiple(of: 2) ? Color.white.opacity(0.02) : Color.clear)
                            }
                        }

                        // Merged live dashed highlight spanning rows 1 & 2 (index 1..2, y: 36..108)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                            )
                            .frame(height: 70)
                            .padding(.horizontal, 8)
                            .offset(y: 37)
                    }
                    .background(Color(red: 0.09, green: 0.10, blue: 0.12))
                }
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
                .padding(.horizontal, 20)

                // Key flow bar
                HStack(spacing: 14) {
                    KeyStepBadge(keys: "⌘ X", title: "Cut Selected Items", accent: true)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                    KeyStepBadge(keys: "⌘ V", title: "Native Move Item Here", accent: false)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                    KeyStepBadge(keys: "⌘ Z", title: "Full Finder Undo Intact", accent: false)
                }
                .padding(.bottom, 16)
            }
        }
    }
}

private struct KeyStepBadge: View {
    let keys: String
    let title: String
    let accent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(accent ? .white : .white.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(accent ? Color.accentColor : Color.white.opacity(0.14)))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - 3. System Monitor & Task Manager Graphic

private struct StatsMetricSummary: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let points: [Double]
}

private struct StatsProcessRow: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let pid: String
    let cpu: String
    let cpuColor: Color
    let ram: String
}

private struct SystemMonitorGraphic: View {
    private let metrics: [StatsMetricSummary] = [
        StatsMetricSummary(title: "CPU", value: "24%", subtitle: "10 Cores", color: .blue, points: [0.32, 0.38, 0.35, 0.44, 0.50, 0.46, 0.56, 0.62, 0.54, 0.48, 0.43, 0.47]),
        StatsMetricSummary(title: "RAM", value: "58%", subtitle: "18.6 / 32 GB", color: .purple, points: [0.52, 0.53, 0.54, 0.54, 0.55, 0.56, 0.56, 0.57, 0.57, 0.58, 0.58, 0.58]),
        StatsMetricSummary(title: "GPU", value: "14%", subtitle: "Graphics Engine", color: .green, points: [0.18, 0.22, 0.26, 0.21, 0.30, 0.38, 0.34, 0.29, 0.24, 0.28, 0.25, 0.26])
    ]

    private let rows: [StatsProcessRow] = [
        StatsProcessRow(icon: "hammer", name: "swift-frontend", pid: "PID 4120", cpu: "18.4%", cpuColor: .orange, ram: "1.4 GB"),
        StatsProcessRow(icon: "safari", name: "Safari Web Content", pid: "PID 1842", cpu: "6.2%", cpuColor: .white.opacity(0.9), ram: "940 MB"),
        StatsProcessRow(icon: "apple.terminal", name: "Terminal", pid: "PID 2104", cpu: "2.1%", cpuColor: .white.opacity(0.9), ram: "215 MB"),
        StatsProcessRow(icon: "folder", name: "Finder", pid: "PID 904", cpu: "1.4%", cpuColor: .white.opacity(0.9), ram: "186 MB")
    ]

    var body: some View {
        ZStack {
            DarkGlassBackdrop()

            VStack(spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 8) {
                            Image(systemName: "gauge.with.needle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("System Monitor — Live Menu Bar Telemetry & Task Manager")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("On-demand process sampling while open • Identity-checked termination (PID + UID + Start Time)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    HeaderPill(text: "Zero Idle Overhead")
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)

                // Simulated macOS menu bar item strip + popover card
                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        Text("Menu Bar Readout")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                        Spacer()
                        HStack(spacing: 12) {
                            menuMetricBadge(label: "CPU", value: "24%", color: .blue, fill: 0.24)
                            menuMetricBadge(label: "RAM", value: "58%", color: .purple, fill: 0.58)
                            menuMetricBadge(label: "GPU", value: "14%", color: .green, fill: 0.14)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color(red: 0.14, green: 0.15, blue: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.14), lineWidth: 1))

                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            ForEach(metrics) { card in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(card.title)
                                            .font(.system(size: 10.5, weight: .bold))
                                            .foregroundColor(.white.opacity(0.65))
                                        Spacer()
                                        Text(card.value)
                                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                                            .foregroundColor(card.color)
                                    }
                                    SparklineShape(points: card.points)
                                        .stroke(card.color, lineWidth: 1.8)
                                        .frame(height: 22)
                                    Text(card.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.55))
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1))
                            }
                        }
                        .padding(12)

                        Divider().background(Color.white.opacity(0.10))

                        HStack {
                            Text("PROCESS")
                            Spacer()
                            Text("CPU").frame(width: 60, alignment: .trailing)
                            Text("RAM").frame(width: 68, alignment: .trailing)
                            Text("ACTION").frame(width: 48, alignment: .trailing)
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 14)
                        .frame(height: 24)

                        Divider().background(Color.white.opacity(0.08))

                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                HStack {
                                    HStack(spacing: 8) {
                                        Image(systemName: row.icon)
                                            .font(.system(size: 11.5))
                                            .foregroundColor(.white.opacity(0.75))
                                            .frame(width: 18)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(row.name)
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundColor(.white.opacity(0.92))
                                            Text(row.pid)
                                                .font(.system(size: 9.5).monospacedDigit())
                                                .foregroundColor(.white.opacity(0.45))
                                        }
                                    }
                                    Spacer()
                                    Text(row.cpu)
                                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                        .foregroundColor(row.cpuColor)
                                        .frame(width: 60, alignment: .trailing)
                                    Text(row.ram)
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundColor(.white.opacity(0.65))
                                        .frame(width: 68, alignment: .trailing)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.red.opacity(0.9))
                                        .frame(width: 18, height: 18)
                                        .background(Circle().fill(Color.red.opacity(0.16)))
                                        .frame(width: 48, alignment: .trailing)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(index.isMultiple(of: 2) ? Color.white.opacity(0.02) : Color.clear)
                            }
                        }
                    }
                    .background(Color(red: 0.10, green: 0.11, blue: 0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 8)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
    }

    private func menuMetricBadge(label: String, value: String, color: Color, fill: CGFloat) -> some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
            }
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 3, height: 16)
                Capsule().fill(color).frame(width: 3, height: max(3, 16 * fill))
            }
        }
    }
}

private struct SparklineShape: Shape {
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        for (i, v) in points.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(points.count - 1)
            let y = rect.maxY - rect.height * CGFloat(min(1, max(0, v)))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// MARK: - 4. Independent Scroll Reverser Graphic

private struct ScrollReverserGraphic: View {
    var body: some View {
        ZStack {
            DarkGlassBackdrop()

            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 8) {
                            Image(systemName: "computermouse")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("Independent Scroll Reverser — Per-Device Input Routing")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Runs at the tail of macOS scroll acceleration • Zero modification to System Settings trackpad preferences")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    HeaderPill(text: "User-Interactive CGEventTap")
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                HStack(spacing: 16) {
                    ScrollDeviceCard(
                        icon: "rectangle.and.hand.point.up.left",
                        title: "Trackpad Gestures",
                        badgeText: "Preserved (No-Op)",
                        badgeColor: .green,
                        topLabel: "Fingers move up",
                        bottomLabel: "Page follows natural macOS inertia",
                        arrowIcon: "arrow.up.and.down.circle.fill"
                    )

                    ScrollDeviceCard(
                        icon: "computermouse",
                        title: "External Mouse Wheel",
                        badgeText: "Independently Inverted",
                        badgeColor: .accentColor,
                        topLabel: "Discrete wheel notches",
                        bottomLabel: "Wheel deltas inverted in real time",
                        arrowIcon: "arrow.up.arrow.down.circle.fill"
                    )
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
    }
}

private struct ScrollDeviceCard: View {
    let icon: String
    let title: String
    let badgeText: String
    let badgeColor: Color
    let topLabel: String
    let bottomLabel: String
    let arrowIcon: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(badgeColor.opacity(0.14))
                    .frame(width: 56, height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(badgeColor.opacity(0.35), lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(badgeColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(badgeText)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(badgeColor.opacity(0.16)))
                }

                Text(topLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))

                HStack(spacing: 6) {
                    Image(systemName: arrowIcon)
                        .font(.system(size: 11))
                        .foregroundColor(badgeColor)
                    Text(bottomLabel)
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
