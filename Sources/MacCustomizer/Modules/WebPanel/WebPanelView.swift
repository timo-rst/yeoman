import SwiftUI
import AppKit
import WebKit

public final class WebPanelController: ObservableObject {
    @Published public var currentURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    
    weak var webView: WKWebView?
    weak var module: WebPanelModule?
    
    // User Agents
    public static let iPhoneUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    public static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    
    public init(initialURL: String) {
        self.currentURL = initialURL
    }
    
    public func loadURL(_ urlString: String? = nil) {
        let str = urlString ?? currentURL
        guard let url = URL(string: str.hasPrefix("http") ? str : "https://" + str) else { return }
        currentURL = url.absoluteString
        let request = URLRequest(url: url)
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
        if let home = module?.targetURL {
            loadURL(home)
        }
    }
    
    public func resolvedUserAgent() -> String {
        guard let mod = module else { return Self.iPhoneUserAgent }
        switch mod.userAgentMode {
        case .mobile:
            return Self.iPhoneUserAgent
        case .desktop:
            return Self.desktopUserAgent
        case .auto:
            // If window width <= 480pt, simulate iPhone / mobile web app
            return mod.panelWidth <= 480 ? Self.iPhoneUserAgent : Self.desktopUserAgent
        }
    }
    
    public func updateUserAgent() {
        guard let wv = webView else { return }
        let ua = resolvedUserAgent()
        wv.customUserAgent = ua
        wv.reload()
    }
    
    public func applyUserAgent(to wv: WKWebView) {
        wv.customUserAgent = resolvedUserAgent()
    }
}

public struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var controller: WebPanelController
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // Inject viewport script so mobile pages render perfectly at native scale
        let viewportScript = """
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
            document.getElementsByTagName('head')[0].appendChild(meta);
        }
        """
        let userScript = WKUserScript(source: viewportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        controller.webView = webView
        
        controller.applyUserAgent(to: webView)
        controller.loadURL()
        
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // Keeps user agent and state in sync
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }
    
    public class Coordinator: NSObject, WKNavigationDelegate {
        var controller: WebPanelController
        
        init(controller: WebPanelController) {
            self.controller = controller
        }
        
        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.controller.isLoading = true
            }
        }
        
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.controller.isLoading = false
                self.controller.canGoBack = webView.canGoBack
                self.controller.canGoForward = webView.canGoForward
                if let url = webView.url?.absoluteString {
                    self.controller.currentURL = url
                }
            }
        }
        
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.controller.isLoading = false
            }
        }
    }
}

public struct WebPanelView: View {
    @ObservedObject var module: WebPanelModule
    @ObservedObject var controller: WebPanelController
    @State private var inputURL: String = ""
    @State private var isShowingAddressInput: Bool = false
    
    public init(module: WebPanelModule) {
        self.module = module
        self.controller = module.controller
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Optional Address / Input Bar
            if module.showsAddressBar || isShowingAddressInput {
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
            
            // Web View
            ZStack {
                WebViewRepresentable(controller: controller)
                
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
            
            Divider()
            
            // Bottom Slim Toolbar (MenuBarX Style)
            HStack(spacing: 10) {
                // Home
                Button(action: { controller.goHome() }) {
                    Image(systemName: "house")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Zur Startseite")
                
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
                
                // Current Size & Mode Display / Menu (like in MenuBarX screenshot: 320 x 400 | Mobil)
                Menu {
                    Section("Fenstergröße") {
                        ForEach(WebSizePreset.allCases) { preset in
                            Button(action: {
                                module.sizePreset = preset
                            }) {
                                HStack {
                                    Text(preset.rawValue)
                                    if module.sizePreset == preset {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    Section("User Agent (Smartphone / Desktop)") {
                        ForEach(WebUserAgentMode.allCases) { mode in
                            Button(action: {
                                module.userAgentMode = mode
                            }) {
                                HStack {
                                    Text(mode.rawValue)
                                    if module.userAgentMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button(module.showsAddressBar ? "Adressleiste verstecken" : "Adressleiste anzeigen") {
                        module.showsAddressBar.toggle()
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
                    HStack(spacing: 4) {
                        Text("\(Int(module.panelWidth)) × \(Int(module.panelHeight)) | \(module.userAgentMode == .desktop ? "Desktop" : "Mobil")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
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
                    Image(systemName: isShowingAddressInput || module.showsAddressBar ? "link.circle.fill" : "link")
                        .font(.system(size: 11))
                        .foregroundColor(isShowingAddressInput ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help("URL bearbeiten")
                
                // Pin Window
                Button(action: { module.isPinned.toggle() }) {
                    Image(systemName: module.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(module.isPinned ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help(module.isPinned ? "Fenster lösen" : "Fenster anheften (offen halten)")
                
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: module.panelWidth, height: module.panelHeight)
    }
}
