import AppKit
import SwiftUI
import YeomanCore

@main
struct CaptureRealScreenshots {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let previousLanguage = LocalizationManager.shared.selectedLanguage
        defer { LocalizationManager.shared.selectedLanguage = previousLanguage }
        LocalizationManager.shared.selectedLanguage = .english

        // NEVER touch production data: all mutable fixtures live in a private temp root.
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("yeoman-capture-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let suiteName = "de.trst.Yeoman.capture.\(UUID().uuidString)"
        let sandboxDefaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let sandboxSecrets = SecureFileSecretStore(directoryURL: sandbox.appendingPathComponent(".secrets"))

        let outputDir = URL(fileURLWithPath: "Resources/Mockups")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let moduleManager = ModuleManager.shared

        // ----------------------------------------------------
        // 1. Settings Window (SettingsView with full sidebar)
        // ----------------------------------------------------
        let settingsWidth: CGFloat = 1020
        let settingsHeight: CGFloat = 650
        let settingsChrome = WindowChrome(title: "Yeoman - Settings", contentWidth: settingsWidth, contentHeight: settingsHeight) {
            SettingsView()
        }
        .preferredColorScheme(.dark)

        capture(
            view: settingsChrome,
            width: settingsWidth + 56,
            height: settingsHeight + 40 + 56,
            to: outputDir.appendingPathComponent("yeoman_settings_window.png")
        )

        // ----------------------------------------------------
        // 2. Terminal Saver Module (16:9 Live Preview + Inspector)
        // ----------------------------------------------------
        let termStore = TerminalSaverMediaStore(rootDirectoryURL: sandbox)
        let termManager = TerminalSaverManager(store: termStore, shellHomeDirectoryURL: sandbox)
        let termModule = TerminalSaverModule(manager: termManager, defaults: sandboxDefaults)
        termModule.isEnabled = true
        termManager.toggleSource(.builtIn(.bouncingDVD))
        termManager.toggleSource(.builtIn(.pipes))
        termManager.toggleSource(.builtIn(.spinningDonut))
        termManager.previewSource(.builtIn(.bonfire))
        termManager.startPreview()
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))

        let termWidth: CGFloat = 940
        let termHeight: CGFloat = 640
        let termChrome = WindowChrome(title: "Yeoman - Terminal Saver", contentWidth: termWidth, contentHeight: termHeight) {
            TerminalSaverSettingsView(module: termModule)
        }
        .preferredColorScheme(.dark)

        capture(
            view: termChrome,
            width: termWidth + 56,
            height: termHeight + 40 + 56,
            to: outputDir.appendingPathComponent("yeoman_terminal_saver.png")
        )
        termManager.stopPreview()

        // ----------------------------------------------------
        // 3. Web Widgets Module (WebPanelSettingsView with sample widgets)
        // ----------------------------------------------------
        let webModule = WebPanelModule(storage: WidgetStorage(url: sandbox, defaults: sandboxDefaults, secrets: sandboxSecrets))
        webModule.isEnabled = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let sampleWidgets = [
            WebWidgetItem(
                title: "Google Gemini",
                url: "https://gemini.google.com",
                iconName: "sparkles",
                useFavicon: false,
                sizePreset: .smartphone,
                customWidth: 375,
                customHeight: 667,
                userAgentMode: .mobile,
                isEnabled: true
            ),
            WebWidgetItem(
                title: "Proton Calendar",
                url: "https://calendar.proton.me",
                iconName: "calendar",
                useFavicon: false,
                sizePreset: .custom,
                customWidth: 340,
                customHeight: 460,
                userAgentMode: .auto,
                isEnabled: true
            ),
            WebWidgetItem(
                title: "Notion Workspace",
                url: "https://notion.so",
                iconName: "doc.text",
                useFavicon: false,
                sizePreset: .large,
                customWidth: 500,
                customHeight: 700,
                userAgentMode: .desktop,
                isEnabled: true
            ),
            WebWidgetItem(
                title: "GitHub Pulse",
                url: "https://github.com/timo-rst/yeoman",
                iconName: "chevron.left.forwardslash.chevron.right",
                useFavicon: false,
                sizePreset: .widget,
                customWidth: 320,
                customHeight: 400,
                userAgentMode: .auto,
                isEnabled: true
            )
        ]
        for w in sampleWidgets {
            webModule.addWidget(w)
        }

        let webWidth: CGFloat = 880
        let webHeight: CGFloat = 560
        let webChrome = WindowChrome(title: "Yeoman - Web Widgets", contentWidth: webWidth, contentHeight: webHeight) {
            WebPanelSettingsView(module: webModule)
        }
        .preferredColorScheme(.dark)

        capture(
            view: webChrome,
            width: webWidth + 56,
            height: webHeight + 40 + 56,
            to: outputDir.appendingPathComponent("yeoman_web_widgets.png")
        )

        // ----------------------------------------------------
        // 4. Clipboard History Popover (ClipboardView)
        // ----------------------------------------------------
        let store = ClipboardHistoryStore(directory: nil, secrets: sandboxSecrets, defaults: sandboxDefaults)
        store.addItem(content: "Meeting notes: Review menu bar spacing & widget performance", type: .text, sourceApp: "Notes")
        store.addItem(content: "let package = Package(name: \"Yeoman\", platforms: [.macOS(.v14)])", type: .code, sourceApp: "Xcode")
        store.addItem(content: "https://github.com/timo-rst/yeoman", type: .url, sourceApp: "Safari")
        store.addItem(content: "git commit -m \"feat: terminal saver & auto-advance\"", type: .code, sourceApp: "Terminal")
        if let samplePNG = syntheticClipboardPreviewPNG(width: 240, height: 140) {
            store.addImageData(samplePNG, sourceApp: "macOS Capture", isScreenshot: true)
        }
        store.addItem(content: "swift run YeomanTests", type: .code, sourceApp: "Terminal")
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        if let first = store.items.first {
            store.togglePin(for: first)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let clipWidth: CGFloat = 380
        let clipHeight: CGFloat = 490
        let clipChrome = PopoverChrome(contentWidth: clipWidth, contentHeight: clipHeight) {
            ClipboardView(store: store)
        }
        .preferredColorScheme(.dark)

        capture(
            view: clipChrome,
            width: clipWidth + 48,
            height: clipHeight + 48,
            to: outputDir.appendingPathComponent("yeoman_clipboard_popover.png")
        )

        // ----------------------------------------------------
        // 5. Menu Bar Spacing & Optimizer (MenuBarSettingsView)
        // ----------------------------------------------------
        let menuBarModule = moduleManager.menuBarModule
        let prevMenuBarEnabled = menuBarModule.isEnabled
        let prevMenuBarTab = menuBarModule.activeSubTab
        defer {
            menuBarModule.isEnabled = prevMenuBarEnabled
            menuBarModule.activeSubTab = prevMenuBarTab
        }
        menuBarModule.isEnabled = true
        menuBarModule.activeSubTab = .spacing

        let menuWidth: CGFloat = 880
        let menuHeight: CGFloat = 560
        let menuChrome = WindowChrome(title: "Yeoman - Menu Bar Spacing", contentWidth: menuWidth, contentHeight: menuHeight) {
            MenuBarSettingsView(module: menuBarModule)
        }
        .preferredColorScheme(.dark)

        capture(
            view: menuChrome,
            width: menuWidth + 56,
            height: menuHeight + 40 + 56,
            to: outputDir.appendingPathComponent("yeoman_menubar_spacing.png")
        )

        print("All 5 real screenshots captured cleanly in Resources/Mockups/.")
    }

    private static func syntheticClipboardPreviewPNG(width: Int, height: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let gradient = NSGradient(
            starting: NSColor(red: 0.14, green: 0.34, blue: 0.72, alpha: 1.0),
            ending: NSColor(red: 0.24, green: 0.64, blue: 0.68, alpha: 1.0)
        )
        gradient?.draw(in: rect, angle: 35)
        NSColor(white: 1.0, alpha: 0.18).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 16, dy: 16), xRadius: 12, yRadius: 12).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
    
    @MainActor
    static func capture<V: View>(view: V, width: CGFloat, height: CGFloat, to url: URL) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1.0)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.orderFront(nil)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            print("Failed rep for \(url.lastPathComponent)")
            return
        }
        rep.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("Failed png for \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
        print("Saved \(url.lastPathComponent): \(png.count / 1024) KB (\(Int(hostingView.bounds.width * 2))x\(Int(hostingView.bounds.height * 2)) Retina)")
    }
}

// MARK: - Native Window Frame Wrapper
struct WindowChrome<Content: View>: View {
    let title: String
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            // macOS Titlebar with traffic lights
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1.0, green: 0.76, blue: 0.18)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.28)).frame(width: 12, height: 12)
                }
                .padding(.leading, 16)
                
                Spacer()
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.85))
                
                Spacer()
                
                Color.clear.frame(width: 58, height: 12)
            }
            .frame(height: 40)
            .background(Color(red: 0.16, green: 0.17, blue: 0.19))
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // Real Content
            content()
                .frame(width: contentWidth, height: contentHeight)
        }
        .frame(width: contentWidth)
        .background(Color(red: 0.12, green: 0.13, blue: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
        .padding(28)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
    }
}

// MARK: - Native Popover Wrapper
struct PopoverChrome<Content: View>: View {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(width: contentWidth, height: contentHeight)
        }
        .background(Color(red: 0.14, green: 0.14, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
        .padding(24)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
    }
}
