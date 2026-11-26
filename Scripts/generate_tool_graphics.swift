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
            height: 416,
            to: outputDir.appendingPathComponent("yeoman_terminal_saver_showcase.png")
        )

        capture(
            view: FinderCutGraphic().preferredColorScheme(.dark),
            width: 860,
            height: 356,
            to: outputDir.appendingPathComponent("yeoman_finder_cut.png")
        )

        capture(
            view: ScrollReverserGraphic().preferredColorScheme(.dark),
            width: 860,
            height: 170,
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

private let canvasBackground = Color(red: 0.055, green: 0.067, blue: 0.09)

// MARK: - 1. Terminal Saver Live Engine Output

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
            canvasBackground

            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    TerminalSceneCard(title: "Bonfire", image: bonfireImage)
                    TerminalSceneCard(title: "3D Donut", image: donutImage)
                }
                GridRow {
                    TerminalSceneCard(title: "Pipes", image: pipesImage)
                    TerminalSceneCard(title: "Matrix", image: matrixImage)
                }
            }
            .padding(18)
        }
    }
}

private struct TerminalSceneCard: View {
    let title: String
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
        FinderRowItem(icon: "shippingbox.fill", iconColor: .orange, name: "Yeoman-0.3.0.dmg", modified: "Today at 12:19", size: "9.5 MB", kind: "Disk Image", isCut: true),
        FinderRowItem(icon: "folder.fill", iconColor: .blue, name: "Scripts", modified: "Yesterday at 17:10", size: "--", kind: "Folder", isCut: false),
        FinderRowItem(icon: "doc.richtext", iconColor: .gray, name: "README.md", modified: "Today at 12:20", size: "11 KB", kind: "Markdown Document", isCut: false)
    ]

    var body: some View {
        ZStack {
            canvasBackground

            VStack(spacing: 14) {
                VStack(spacing: 0) {
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
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color(red: 0.15, green: 0.16, blue: 0.19))

                    Divider().background(Color.white.opacity(0.1))

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
            }
            .padding(20)
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

// MARK: - 3. Independent Scroll Reverser Graphic

private struct ScrollReverserGraphic: View {
    var body: some View {
        ZStack {
            canvasBackground

            HStack(spacing: 16) {
                ScrollDeviceCard(
                    icon: "rectangle.and.hand.point.up.left",
                    title: "Trackpad",
                    badgeText: "Natural Scrolling Preserved",
                    badgeColor: .green,
                    subtitle: "macOS trackpad preferences remain untouched"
                )

                ScrollDeviceCard(
                    icon: "computermouse",
                    title: "Mouse Wheel",
                    badgeText: "Independently Inverted",
                    badgeColor: .accentColor,
                    subtitle: "Discrete wheel deltas inverted at tail CGEventTap"
                )
            }
            .padding(20)
        }
    }
}

private struct ScrollDeviceCard: View {
    let icon: String
    let title: String
    let badgeText: String
    let badgeColor: Color
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(badgeColor.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(badgeColor.opacity(0.32), lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(badgeColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(badgeText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(badgeColor.opacity(0.14)))
                }

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color(red: 0.11, green: 0.12, blue: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
