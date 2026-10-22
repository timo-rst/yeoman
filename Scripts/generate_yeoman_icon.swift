import AppKit

func processIcon() {
    let sourceURL = URL(fileURLWithPath: "/Users/timorichstein/.gemini/antigravity-ide/brain/b1515da3-c2b5-4493-9562-ebad78ce7cf7/yeoman_icon_clean_1792674399043.jpg")
    guard let sourceImage = NSImage(contentsOf: sourceURL) else {
        print("Failed to load source image")
        return
    }
    
    // Squircle bounding box from analysis: center ~ (511, 511.5), size ~ 636x636
    let cropRect = NSRect(x: 193, y: 192, width: 638, height: 638)
    
    // Canvas size 1024x1024
    let canvasSize: CGFloat = 1024
    let iconSize: CGFloat = 824
    let inset: CGFloat = (canvasSize - iconSize) / 2 // 100
    let cornerRadius: CGFloat = 185
    
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize),
        pixelsHigh: Int(canvasSize),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    
    let destRect = NSRect(x: inset, y: inset, width: iconSize, height: iconSize)
    let clipPath = NSBezierPath(roundedRect: destRect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // Draw subtle macOS drop shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowBlurRadius = 24
    
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    clipPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    
    // Clip and draw the cropped squircle
    NSGraphicsContext.saveGraphicsState()
    clipPath.addClip()
    sourceImage.draw(in: destRect, from: cropRect, operation: .sourceOver, fraction: 1.0)
    
    // Subtle inner stroke/highlight
    NSColor(white: 1.0, alpha: 0.12).setStroke()
    clipPath.lineWidth = 3
    clipPath.stroke()
    NSGraphicsContext.restoreGraphicsState()
    
    NSGraphicsContext.restoreGraphicsState()
    
    // Prepare .iconset
    let fm = FileManager.default
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Yeoman.iconset")
    try? fm.removeItem(at: tempDir)
    try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    let exportSizes: [(size: Int, scale: Int, name: String)] = [
        (16, 1, "icon_16x16.png"),
        (16, 2, "icon_16x16@2x.png"),
        (32, 1, "icon_32x32.png"),
        (32, 2, "icon_32x32@2x.png"),
        (128, 1, "icon_128x128.png"),
        (128, 2, "icon_128x128@2x.png"),
        (256, 1, "icon_256x256.png"),
        (256, 2, "icon_256x256@2x.png"),
        (512, 1, "icon_512x512.png"),
        (512, 2, "icon_512x512@2x.png")
    ]
    
    guard let fullPngData = rep.representation(using: .png, properties: [:]) else {
        print("Failed to get PNG data")
        return
    }
    
    // Also save preview PNG
    let resourcesDir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources", isDirectory: true)
    try? fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    let previewURL = resourcesDir.appendingPathComponent("AppIcon.png")
    try? fullPngData.write(to: previewURL)
    
    for item in exportSizes {
        let pixelDimension = item.size * item.scale
        let resizedRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelDimension,
            pixelsHigh: pixelDimension,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: resizedRep)!
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        
        NSImage(data: fullPngData)?.draw(
            in: NSRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        
        if let png = resizedRep.representation(using: .png, properties: [:]) {
            let fileURL = tempDir.appendingPathComponent(item.name)
            try? png.write(to: fileURL)
        }
    }
    
    let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", tempDir.path, "-o", icnsPath.path]
    try? proc.run()
    proc.waitUntilExit()
    
    if proc.terminationStatus == 0 {
        print("Successfully generated: \(icnsPath.path)")
    } else {
        print("iconutil failed with code \(proc.terminationStatus)")
    }
}

processIcon()
