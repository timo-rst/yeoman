#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// Renders Yeoman's Crossed Frosted-Glass Quills (Naval Yeoman badge) app icon
// on an Apple HIG-compliant transparent 1024x1024 RGBA canvas (824x824 continuous squircle)
// and packages Resources/AppIcon.png + Resources/AppIcon.icns.

enum IconSpec {
    static let canvasSize = 1024
    static let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let superellipseExponent: CGFloat = 4.45
    static let artScale: CGFloat = 824.0 / 740.0
}

enum GlassTier {
    case back
    case front
}

// MARK: - Deterministic Frosted Grain Texture

func makeFrostedNoiseImage(size: Int = 512) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    for i in 0..<(size * size) {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let value = UInt8((seed >> 56) & 0xFF)
        let offset = i * 4
        pixels[offset] = value
        pixels[offset + 1] = value
        pixels[offset + 2] = value
        pixels[offset + 3] = 255
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
        width: size,
        height: size,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )
}

let sharedNoiseImage = makeFrostedNoiseImage()

// MARK: - Geometry Helpers

func makeSquirclePath(
    in rect: CGRect,
    exponent p: CGFloat = IconSpec.superellipseExponent,
    steps: Int = 480
) -> CGPath {
    let path = CGMutablePath()
    let rx = rect.width * 0.5
    let ry = rect.height * 0.5
    let cx = rect.midX
    let cy = rect.midY
    let inv = 2.0 / p

    for i in 0..<steps {
        let theta = (CGFloat(i) / CGFloat(steps)) * 2.0 * .pi
        let cosT = cos(theta)
        let sinT = sin(theta)
        let x = cx + rx * (cosT >= 0 ? 1 : -1) * pow(abs(cosT), inv)
        let y = cy + ry * (sinT >= 0 ? 1 : -1) * pow(abs(sinT), inv)
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func transformed(
    _ path: CGPath,
    center: CGPoint = CGPoint(x: 512, y: 512),
    angleDegrees: CGFloat,
    scale: CGFloat = 1.0,
    offset: CGPoint = .zero
) -> CGPath {
    var t = CGAffineTransform.identity
    t = t.translatedBy(x: center.x + offset.x, y: center.y + offset.y)
    t = t.rotated(by: angleDegrees * .pi / 180.0)
    t = t.scaledBy(x: scale, y: scale)
    t = t.translatedBy(x: -center.x, y: -center.y)
    return path.copy(using: &t) ?? path
}

// MARK: - Squircle Stage (Transparent Background + Apple HIG Drop Shadow)

func drawSquircleStage(in ctx: CGContext) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let s = IconSpec.artScale
    let squircle = makeSquirclePath(in: IconSpec.squircleRect)

    // Apple HIG subtle drop shadow safely contained inside the 100px margin
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 22,
        color: CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.24)
    )
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.42, blue: 0.34, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clipped Vibrant Coral -> Tangerine Gradient Base
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let baseColors = [
        CGColor(srgbRed: 1.00, green: 0.27, blue: 0.36, alpha: 1.0), // bottom-left rich coral-rose
        CGColor(srgbRed: 1.00, green: 0.44, blue: 0.27, alpha: 1.0), // mid sunset-coral
        CGColor(srgbRed: 1.00, green: 0.64, blue: 0.19, alpha: 1.0), // top-right luminous tangerine
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: baseColors, locations: [0.0, 0.50, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: IconSpec.squircleRect.minX, y: IconSpec.squircleRect.minY),
            end: CGPoint(x: IconSpec.squircleRect.maxX, y: IconSpec.squircleRect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // Smooth radial tangerine bloom top-right (startRadius: 0 prevents edge artifacts)
    let bloomCenter = CGPoint(x: 512 + (780 - 512) * s, y: 512 + (780 - 512) * s)
    let bloomColors = [
        CGColor(srgbRed: 1.00, green: 0.78, blue: 0.32, alpha: 0.38),
        CGColor(srgbRed: 1.00, green: 0.64, blue: 0.24, alpha: 0.0),
    ] as CFArray
    if let bloom = CGGradient(colorsSpace: cs, colors: bloomColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            bloom,
            startCenter: bloomCenter,
            startRadius: 0,
            endCenter: bloomCenter,
            endRadius: 560 * s,
            options: []
        )
    }

    // Smooth coral richness bottom-left (startRadius: 0)
    let depthCenter = CGPoint(x: 512 + (240 - 512) * s, y: 512 + (240 - 512) * s)
    let depthColors = [
        CGColor(srgbRed: 0.96, green: 0.20, blue: 0.32, alpha: 0.32),
        CGColor(srgbRed: 0.96, green: 0.20, blue: 0.32, alpha: 0.0),
    ] as CFArray
    if let depthGrad = CGGradient(colorsSpace: cs, colors: depthColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            depthGrad,
            startCenter: depthCenter,
            startRadius: 0,
            endCenter: depthCenter,
            endRadius: 480 * s,
            options: []
        )
    }

    // Inner glass frame bevel
    let rimRect = IconSpec.squircleRect.insetBy(dx: 8 * s, dy: 8 * s)
    let rimPath = makeSquirclePath(in: rimRect)
    ctx.saveGState()
    ctx.addPath(rimPath)
    ctx.setLineWidth(3.5 * s)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let rimColors = [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.38),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
    ] as CFArray
    if let rimGrad = CGGradient(colorsSpace: cs, colors: rimColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            rimGrad,
            start: CGPoint(x: 512, y: IconSpec.squircleRect.maxY),
            end: CGPoint(x: 512, y: IconSpec.squircleRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Crisp outer glass rim inside squircle
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28))
    ctx.setLineWidth(2.5 * s)
    ctx.strokePath()

    ctx.restoreGState()
}

// MARK: - 3D Frosted Milky-Glass Renderer

func drawFrostedGlassShape(
    in ctx: CGContext,
    path: CGPath,
    tier: GlassTier,
    fillRule: CGPathFillRule = .evenOdd,
    extraHighlightPath: CGPath? = nil
) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let s = IconSpec.artScale
    let bounds = path.boundingBoxOfPath
    let invBounds = CGRect(x: -100, y: -100, width: 1224, height: 1224)

    // 1. Soft warm drop shadow cast onto underlying layers
    ctx.saveGState()
    let sAlpha: CGFloat = tier == .front ? 0.30 : 0.18
    let sBlur: CGFloat = (tier == .front ? 30 : 20) * s
    let sOffset = tier == .front
        ? CGSize(width: 4 * s, height: -15 * s)
        : CGSize(width: 2 * s, height: -8 * s)
    ctx.setShadow(offset: sOffset, blur: sBlur, color: CGColor(srgbRed: 0.68, green: 0.12, blue: 0.08, alpha: sAlpha))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.96, blue: 0.94, alpha: tier == .front ? 0.85 : 0.55))
    ctx.fillPath(using: fillRule)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 2. Clipped frosted body
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip(using: fillRule)

    let fillColors: [CGColor] = tier == .front ? [
        CGColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.78),
        CGColor(srgbRed: 0.98, green: 0.96, blue: 0.96, alpha: 0.58),
        CGColor(srgbRed: 1.00, green: 0.90, blue: 0.86, alpha: 0.44),
    ] : [
        CGColor(srgbRed: 1.00, green: 0.98, blue: 0.97, alpha: 0.44),
        CGColor(srgbRed: 1.00, green: 0.92, blue: 0.88, alpha: 0.28),
        CGColor(srgbRed: 1.00, green: 0.82, blue: 0.74, alpha: 0.18),
    ]

    if let grad = CGGradient(colorsSpace: cs, colors: fillColors as CFArray, locations: [0.0, 0.50, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: bounds.minX, y: bounds.maxY),
            end: CGPoint(x: bounds.maxX, y: bounds.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // Specular surface highlight bloom
    let sheenColors = [
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: tier == .front ? 0.42 : 0.20),
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
    ] as CFArray
    if let sheen = CGGradient(colorsSpace: cs, colors: sheenColors, locations: [0.0, 1.0]) {
        let center = CGPoint(x: bounds.minX + bounds.width * 0.30, y: bounds.maxY - bounds.height * 0.25)
        ctx.drawRadialGradient(
            sheen,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: max(bounds.width, bounds.height) * 0.78,
            options: []
        )
    }

    // 3. Thick 3D glass inner bevel & warm subsurface bounce
    let invPath = CGMutablePath()
    invPath.addRect(invBounds)
    invPath.addPath(path)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 4 * s, height: -8 * s),
        blur: (tier == .front ? 12 : 8) * s,
        color: CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: tier == .front ? 0.95 : 0.65)
    )
    ctx.addPath(invPath)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: -4 * s, height: 6 * s),
        blur: (tier == .front ? 15 : 10) * s,
        color: CGColor(srgbRed: 0.94, green: 0.36, blue: 0.22, alpha: tier == .front ? 0.34 : 0.22)
    )
    ctx.addPath(invPath)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // 4. Fine sandblasted frosted grain
    if let noise = sharedNoiseImage {
        ctx.saveGState()
        ctx.setAlpha(tier == .front ? 0.045 : 0.030)
        ctx.setBlendMode(.softLight)
        ctx.draw(noise, in: CGRect(x: 0, y: 0, width: IconSpec.canvasSize, height: IconSpec.canvasSize))
        ctx.restoreGState()
    }

    // 5. Internal spine highlight ridge
    if let ridge = extraHighlightPath {
        ctx.saveGState()
        ctx.addPath(ridge)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: tier == .front ? 0.65 : 0.35))
        ctx.setLineWidth(4.5 * s)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 6. Sharp outer glass rim highlight inside clip
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth((tier == .front ? 4.0 : 2.8) * s)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let strokeColors = [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: tier == .front ? 0.95 : 0.62),
        CGColor(srgbRed: 1, green: 0.96, blue: 0.94, alpha: tier == .front ? 0.45 : 0.25),
    ] as CFArray
    if let strokeGrad = CGGradient(colorsSpace: cs, colors: strokeColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            strokeGrad,
            start: CGPoint(x: bounds.minX, y: bounds.maxY),
            end: CGPoint(x: bounds.maxX, y: bounds.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    ctx.restoreGState()

    ctx.restoreGState()
}

// MARK: - Crossed Naval Yeoman Quills Artwork

func makeQuillShape() -> (body: CGPath, spine: CGPath) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 512, y: 224))
    p.addCurve(
        to: CGPoint(x: 503, y: 344),
        control1: CGPoint(x: 506, y: 262),
        control2: CGPoint(x: 503, y: 304)
    )
    p.addCurve(
        to: CGPoint(x: 444, y: 626),
        control1: CGPoint(x: 452, y: 416),
        control2: CGPoint(x: 432, y: 534)
    )
    p.addCurve(
        to: CGPoint(x: 526, y: 796),
        control1: CGPoint(x: 454, y: 706),
        control2: CGPoint(x: 492, y: 770)
    )
    p.addCurve(
        to: CGPoint(x: 582, y: 632),
        control1: CGPoint(x: 562, y: 764),
        control2: CGPoint(x: 590, y: 696)
    )
    p.addQuadCurve(to: CGPoint(x: 542, y: 604), control: CGPoint(x: 564, y: 616))
    p.addQuadCurve(to: CGPoint(x: 580, y: 582), control: CGPoint(x: 562, y: 594))
    p.addCurve(
        to: CGPoint(x: 521, y: 344),
        control1: CGPoint(x: 576, y: 488),
        control2: CGPoint(x: 552, y: 392)
    )
    p.addCurve(
        to: CGPoint(x: 512, y: 224),
        control1: CGPoint(x: 521, y: 304),
        control2: CGPoint(x: 518, y: 262)
    )
    p.closeSubpath()

    let spine = CGMutablePath()
    spine.move(to: CGPoint(x: 512, y: 268))
    spine.addCurve(
        to: CGPoint(x: 522, y: 746),
        control1: CGPoint(x: 508, y: 436),
        control2: CGPoint(x: 512, y: 602)
    )

    return (p, spine)
}

func renderAppIconBitmap() -> NSBitmapImageRep {
    let size = IconSpec.canvasSize
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to allocate 1024x1024 RGBA bitmap")
    }
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create graphics context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    drawSquircleStage(in: ctx)

    let s = IconSpec.artScale
    let (rawQuill, rawSpine) = makeQuillShape()

    let backBody = transformed(rawQuill, angleDegrees: 37, scale: s)
    let backSpine = transformed(rawSpine, angleDegrees: 37, scale: s)
    drawFrostedGlassShape(in: ctx, path: backBody, tier: .back, extraHighlightPath: backSpine)

    let frontBody = transformed(rawQuill, angleDegrees: -37, scale: s)
    let frontSpine = transformed(rawSpine, angleDegrees: -37, scale: s)
    drawFrostedGlassShape(in: ctx, path: frontBody, tier: .front, extraHighlightPath: frontSpine)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writeResizedPNG(from source: CGImage, pixelSize: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "GenerateAppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate \(pixelSize)x\(pixelSize) bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    ctx.interpolationQuality = .high
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateAppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG for \(url.lastPathComponent)"])
    }
    try pngData.write(to: url, options: .atomic)
}

func runIconutil(iconsetURL: URL, outputICNSURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputICNSURL.path]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    // Concurrently drain stdout/stderr to avoid pipe deadlocks
    let group = DispatchGroup()
    var outData = Data()
    var errData = Data()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }

    process.waitUntilExit()
    group.wait()

    if process.terminationStatus != 0 {
        let stderrText = String(data: errData, encoding: .utf8) ?? ""
        let stdoutText = String(data: outData, encoding: .utf8) ?? ""
        throw NSError(
            domain: "GenerateAppIcon",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "iconutil failed (\(process.terminationStatus)): \(stderrText) \(stdoutText)"]
        )
    }
}

// MARK: - Main

do {
    let fileManager = FileManager.default
    let rootDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    let resourcesDir = rootDir.appendingPathComponent("Resources", isDirectory: true)
    let pngOutURL = resourcesDir.appendingPathComponent("AppIcon.png")
    let icnsOutURL = resourcesDir.appendingPathComponent("AppIcon.icns")

    try fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

    let masterRep = renderAppIconBitmap()
    guard let masterPNG = masterRep.representation(using: .png, properties: [:]),
          let masterCGImage = masterRep.cgImage else {
        throw NSError(domain: "GenerateAppIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize master AppIcon bitmap"])
    }
    try masterPNG.write(to: pngOutURL, options: .atomic)

    let iconsetURL = fileManager.temporaryDirectory
        .appendingPathComponent("yeoman-iconset-\(UUID().uuidString).iconset", isDirectory: true)
    try fileManager.createDirectory(
        at: iconsetURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    defer {
        try? fileManager.removeItem(at: iconsetURL)
    }

    let entries: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for entry in entries {
        try writeResizedPNG(
            from: masterCGImage,
            pixelSize: entry.pixels,
            to: iconsetURL.appendingPathComponent(entry.name)
        )
    }

    try runIconutil(iconsetURL: iconsetURL, outputICNSURL: icnsOutURL)

    print("Generated \(pngOutURL.path)")
    print("Generated \(icnsOutURL.path)")
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
