import AppKit

func generateIconSet() {
    let iconSize = 1024
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: iconSize,
        pixelsHigh: iconSize,
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
    
    let fullRect = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
    
    // Background Squircle (macOS style)
    let inset: CGFloat = 80
    let squircleRect = fullRect.insetBy(dx: inset, dy: inset)
    let cornerRadius: CGFloat = 185
    let path = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // Gradient: Deep Slate Navy to Indigo/Purple
    let gradient = NSGradient(
        starting: NSColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1.0),
        ending: NSColor(red: 0.15, green: 0.18, blue: 0.28, alpha: 1.0)
    )!
    gradient.draw(in: path, angle: -45)
    
    // Outer subtle border
    NSColor(white: 1.0, alpha: 0.15).setStroke()
    path.lineWidth = 4
    path.stroke()
    
    // Top-left subtle highlight
    let glowPath = NSBezierPath(roundedRect: squircleRect.insetBy(dx: 2, dy: 2), xRadius: cornerRadius - 2, yRadius: cornerRadius - 2)
    NSColor(white: 1.0, alpha: 0.08).setStroke()
    glowPath.lineWidth = 3
    glowPath.stroke()
    
    // Draw SF Symbol: "slider.horizontal.3" or "menubar.rectangle"
    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
        .applying(.init(paletteColors: [NSColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1.0)]))
    if let symbol = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        
        let symbolRect = NSRect(
            x: (CGFloat(iconSize) - 520) / 2,
            y: (CGFloat(iconSize) - 520) / 2,
            width: 520,
            height: 520
        )
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    NSGraphicsContext.restoreGraphicsState()
    
    // Export iconset sizes
    let fm = FileManager.default
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MacCustomizer.iconset")
    try? fm.removeItem(at: tempDir)
    try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes {
        let resized = NSImage(size: NSSize(width: s, height: s))
        resized.lockFocus()
        NSImage(data: rep.representation(using: .png, properties: [:])!)?.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        resized.unlockFocus()
        
        if let tiff = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            if s <= 512 {
                try? png.write(to: tempDir.appendingPathComponent("icon_\(s)x\(s).png"))
            }
            if s >= 32 {
                let half = s / 2
                try? png.write(to: tempDir.appendingPathComponent("icon_\(half)x\(half)@2x.png"))
            }
        }
    }
    
    // Convert to .icns using iconutil
    let resourcesDir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources", isDirectory: true)
    try? fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")
    
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", tempDir.path, "-o", icnsPath.path]
    try? proc.run()
    proc.waitUntilExit()
    
    print("Icon generated at: \(icnsPath.path)")
}

generateIconSet()
