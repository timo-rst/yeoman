import SwiftUI
import AppKit
import WebKit

public final class WebPanelController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published public var currentURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    @Published public var zoomScale: Double = 1.0
    
    public var userAgentMode: WebUserAgentMode
    public var targetWidth: CGFloat
    public var homeURL: String
    public var associatedItem: WebWidgetItem? = nil
    
    // Persistent preloaded WKWebView instance
    public private(set) var webView: WKWebView!
    private var hasPreloaded = false
    
    // User Agents
    public static let iPhoneUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    public static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    
    public init(initialURL: String, userAgentMode: WebUserAgentMode = .auto, targetWidth: CGFloat = 320, zoomScale: Double = 1.0) {
        self.currentURL = initialURL
        self.homeURL = initialURL
        self.userAgentMode = userAgentMode
        self.targetWidth = targetWidth
        self.zoomScale = zoomScale
        super.init()
        
        setupWebView()
        preload()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isElementFullscreenEnabled = true
        
        // Inject responsive viewport script so web content scales properly to widget bounds
        let viewportScript = """
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.getElementsByTagName('head')[0].appendChild(meta);
        }
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
        """
        let userScript = WKUserScript(source: viewportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: targetWidth, height: 400), configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = resolvedUserAgent()
        wv.pageZoom = CGFloat(zoomScale)
        self.webView = wv
    }
    
    public func preload() {
        guard !hasPreloaded else { return }
        hasPreloaded = true
        loadURL(homeURL)
    }
    
    public func updateConfig(userAgentMode: WebUserAgentMode, targetWidth: CGFloat, zoomScale: Double = 1.0, newURL: String? = nil) {
        self.userAgentMode = userAgentMode
        self.targetWidth = targetWidth
        self.zoomScale = zoomScale
        applyZoom(zoomScale)
        if let u = newURL, u != currentURL && !u.isEmpty {
            self.homeURL = u
            loadURL(u)
        } else {
            updateUserAgent()
        }
    }
    
    public func applyZoom(_ scale: Double) {
        self.zoomScale = scale
        DispatchQueue.main.async { [weak self] in
            self?.webView?.pageZoom = CGFloat(scale)
        }
    }
    
    public func loadURL(_ urlString: String? = nil) {
        let str = urlString ?? currentURL
        guard let url = URL(string: str.hasPrefix("http") ? str : "https://" + str) else { return }
        currentURL = url.absoluteString
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30.0)
        request.attribution = .developer
        webView?.load(request)
    }
    
    public func reload() {
        webView?.reload()
    }
    
    public func goBack() {
        webView?.goBack()
    }
    
    public func goForward() {
        webView?.goForward()
    }
    
    public func goHome() {
        loadURL(homeURL)
    }
    
    public func stopLoading() {
        webView?.stopLoading()
    }
    
    public func resolvedUserAgent() -> String {
        switch userAgentMode {
        case .mobile:
            return Self.iPhoneUserAgent
        case .desktop:
            return Self.desktopUserAgent
        case .auto:
            return targetWidth <= 480 ? Self.iPhoneUserAgent : Self.desktopUserAgent
        }
    }
    
    public func updateUserAgent() {
        guard let wv = webView else { return }
        let ua = resolvedUserAgent()
        if wv.customUserAgent != ua {
            wv.customUserAgent = ua
            wv.reload()
        }
    }
    
    public func applyUserAgent(to wv: WKWebView) {
        wv.customUserAgent = resolvedUserAgent()
    }
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
        }
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
            if let url = webView.url?.absoluteString {
                self.currentURL = url
            }
            webView.pageZoom = CGFloat(self.zoomScale)
            
            if let item = self.associatedItem, item.useFavicon {
                WebFaviconManager.shared.extractFaviconFromWebView(webView, for: item)
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false
        }
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false
        }
    }
    
    // MARK: - WKUIDelegate
    
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

public struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var controller: WebPanelController
    
    public func makeNSView(context: Context) -> WKWebView {
        let wv = controller.webView!
        if wv.superview != nil {
            wv.removeFromSuperview()
        }
        return wv
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        if abs(nsView.pageZoom - CGFloat(controller.zoomScale)) > 0.01 {
            nsView.pageZoom = CGFloat(controller.zoomScale)
        }
    }
}

public struct WebPanelView: View {
    @ObservedObject var instance: WebWidgetInstanceController
    @ObservedObject var controller: WebPanelController
    public var onUpdateItem: ((WebWidgetItem) -> Void)?
    
    var item: WebWidgetItem {
        instance.item
    }
    
    @State private var inputURL: String = ""
    @State private var isShowingAddressInput: Bool = false
    
    public init(
        instance: WebWidgetInstanceController,
        controller: WebPanelController,
        onUpdateItem: ((WebWidgetItem) -> Void)? = nil
    ) {
        self.instance = instance
        self.controller = controller
        self.onUpdateItem = onUpdateItem
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Optional Address / Input Bar
            if item.showsAddressBar || isShowingAddressInput {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    TextField("URL eingeben...", text: $inputURL, onCommit: {
                        controller.loadURL(inputURL)
                        isShowingAddressInput = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    
                    Button(action: {
                        controller.loadURL(inputURL)
                        isShowingAddressInput = false
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
            }
            
            // Web View - Flexible area filling all available height
            ZStack {
                WebViewRepresentable(controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if controller.isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor).opacity(0.85)))
                        Spacer()
                    }
                    .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Bottom Slim Toolbar (MenuBarX Style) - Fixed at the very bottom
            HStack(spacing: 8) {
                // Home
                Button(action: { controller.goHome() }) {
                    Image(systemName: "house")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Zur Startseite (\(item.title))")
                
                // Back
                Button(action: { controller.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(!controller.canGoBack)
                .help("Zurück")
                
                // Forward
                Button(action: { controller.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(!controller.canGoForward)
                .help("Vorwärts")
                
                // Reload
                Button(action: { controller.reload() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Neu laden")
                
                Spacer()
                
                // Size Preset Menu
                Menu {
                    Section("Fenstergröße") {
                        ForEach(WebSizePreset.allCases) { preset in
                            Button(action: {
                                var updated = item
                                updated.sizePreset = preset
                                // Automatically adjust zoom scale for widget mode if at default
                                if preset == .widget && (updated.zoomScale == 1.0 || updated.zoomScale == 0) {
                                    updated.zoomScale = 0.85
                                }
                                onUpdateItem?(updated)
                                controller.applyZoom(updated.zoomScale)
                            }) {
                                HStack {
                                    Text(preset.rawValue)
                                    if item.sizePreset == preset {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    Section("User Agent (Smartphone / Desktop)") {
                        ForEach(WebUserAgentMode.allCases) { mode in
                            Button(action: {
                                var updated = item
                                updated.userAgentMode = mode
                                onUpdateItem?(updated)
                            }) {
                                HStack {
                                    Text(mode.rawValue)
                                    if item.userAgentMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button(item.showsAddressBar ? "Adressleiste verstecken" : "Adressleiste anzeigen") {
                        var updated = item
                        updated.showsAddressBar.toggle()
                        onUpdateItem?(updated)
                    }
                    
                    Button("Im Browser öffnen") {
                        if let url = URL(string: controller.currentURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    
                    Button("Einstellungen...") {
                        StatusItemController.shared.openSettingsWindow()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(Int(item.effectiveWidth)) × \(Int(item.effectiveHeight))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Zoom Level Menu (MenuBarX Feature: scales website to fit widget)
                Menu {
                    Section("Seiten-Skalierung (Zoom)") {
                        ForEach([0.5, 0.65, 0.75, 0.85, 1.0, 1.15, 1.25, 1.5], id: \.self) { z in
                            Button(action: {
                                var updated = item
                                updated.zoomScale = z
                                onUpdateItem?(updated)
                                controller.applyZoom(z)
                            }) {
                                HStack {
                                    Text("\(Int(z * 100))%")
                                    if abs(item.zoomScale - z) < 0.02 {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 8))
                        Text("\(Int(item.zoomScale * 100))%")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Address Bar Toggle
                Button(action: {
                    inputURL = controller.currentURL
                    isShowingAddressInput.toggle()
                }) {
                    Image(systemName: isShowingAddressInput || item.showsAddressBar ? "link.circle.fill" : "link")
                        .font(.system(size: 11))
                        .foregroundColor(isShowingAddressInput ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help("URL bearbeiten")
                
                // Pin Window
                Button(action: {
                    var updated = item
                    updated.isPinned.toggle()
                    onUpdateItem?(updated)
                }) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(item.isPinned ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Fenster lösen" : "Fenster anheften (offen halten)")
                
                // Open in External Browser
                Button(action: {
                    if let url = URL(string: controller.currentURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Im Standard-Browser öffnen")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .frame(maxWidth: .infinity)
        }
        .frame(width: item.effectiveWidth, height: item.effectiveHeight)
    }
}
