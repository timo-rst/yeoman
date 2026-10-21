import AppKit
import SwiftUI
import WebKit

public extension Notification.Name {
    static let webFaviconDidUpdate = Notification.Name("de.trst.MacCustomizer.webFaviconDidUpdate")
}

public final class WebFaviconManager: ObservableObject {
    public static let shared = WebFaviconManager()
    
    @Published public var changeCount: Int = 0
    
    private var memoryCache: [String: NSImage] = [:]
    private var pendingFetches = Set<String>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDirectory = appSupport
            .appendingPathComponent("MacCustomizer", isDirectory: true)
            .appendingPathComponent("favicons", isDirectory: true)
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Returns the menu-bar ready favicon for the given widget, or nil if not available.
    public func menuBarIcon(for item: WebWidgetItem) -> NSImage? {
        guard item.useFavicon else { return nil }
        return getOrFetchIcon(for: item.url, widgetId: item.id)
    }
    
    /// Returns the raw/preview favicon for settings or nil if not yet loaded.
    public func previewIcon(for urlString: String, widgetId: UUID? = nil) -> NSImage? {
        return getOrFetchIcon(for: urlString, widgetId: widgetId)
    }
    
    /// Forces a refresh of the favicon from web services.
    public func refreshFavicon(for item: WebWidgetItem, completion: ((NSImage?) -> Void)? = nil) {
        let cacheKey = cacheKey(for: item.url, widgetId: item.id)
        memoryCache.removeValue(forKey: cacheKey)
        let fileURL = diskFileURL(for: cacheKey)
        try? fileManager.removeItem(at: fileURL)
        
        fetchFavicon(for: item.url, widgetId: item.id, completion: completion)
    }
    
    /// Extracts higher-res favicon link directly from WKWebView document
    public func extractFaviconFromWebView(_ webView: WKWebView, for item: WebWidgetItem) {
        guard item.useFavicon else { return }
        
        let js = """
        (function() {
            var selectors = [
                'link[rel="apple-touch-icon"]',
                'link[rel="apple-touch-icon-precomposed"]',
                'link[rel="icon"][sizes="192x192"]',
                'link[rel="icon"][sizes="180x180"]',
                'link[rel="icon"][sizes="128x128"]',
                'link[rel="icon"][type="image/png"]',
                'link[rel="shortcut icon"]',
                'link[rel="icon"]'
            ];
            for (var i = 0; i < selectors.length; i++) {
                var el = document.querySelector(selectors[i]);
                if (el && el.href) return el.href;
            }
            return '';
        })()
        """
        
        webView.evaluateJavaScript(js) { [weak self] (result, error) in
            guard let self = self, let iconUrlStr = result as? String, !iconUrlStr.isEmpty, let iconURL = URL(string: iconUrlStr) else {
                return
            }
            self.downloadAndCache(url: iconURL, targetUrlStr: item.url, widgetId: item.id, completion: nil)
        }
    }
    
    // MARK: - Internal Cache & Fetching
    
    private func getOrFetchIcon(for urlString: String, widgetId: UUID?) -> NSImage? {
        let key = cacheKey(for: urlString, widgetId: widgetId)
        
        if let cached = memoryCache[key] {
            return cached
        }
        
        // Try disk
        let fileURL = diskFileURL(for: key)
        if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
            let formatted = formatIcon(image)
            memoryCache[key] = formatted
            return formatted
        }
        
        // Asynchronously fetch
        fetchFavicon(for: urlString, widgetId: widgetId)
        return nil
    }
    
    public func fetchFavicon(for urlString: String, widgetId: UUID?, completion: ((NSImage?) -> Void)? = nil) {
        guard let host = extractHost(from: urlString), !host.isEmpty else {
            completion?(nil)
            return
        }
        
        let key = cacheKey(for: urlString, widgetId: widgetId)
        guard !pendingFetches.contains(key) else { return }
        pendingFetches.insert(key)
        
        // Candidates in order of reliability and quality:
        // 1. DuckDuckGo Favicon Service (extremely fast, full resolution ICO/PNG)
        // 2. Direct /assets/favicon.ico or /favicon.ico on host
        // 3. Apple Touch Icon on host
        // 4. Google Favicon Service
        // 5. Fallback base domain if subdomain
        var candidates: [URL] = []
        if let ddg = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
            candidates.append(ddg)
        }
        if let directFavicon = URL(string: "https://\(host)/favicon.ico") {
            candidates.append(directFavicon)
        }
        if let appleTouch = URL(string: "https://\(host)/apple-touch-icon.png") {
            candidates.append(appleTouch)
        }
        if let google = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") {
            candidates.append(google)
        }
        
        let baseDomain = extractBaseDomain(from: host)
        if baseDomain != host {
            if let ddgBase = URL(string: "https://icons.duckduckgo.com/ip3/\(baseDomain).ico") {
                candidates.append(ddgBase)
            }
            if let googleBase = URL(string: "https://www.google.com/s2/favicons?domain=\(baseDomain)&sz=128") {
                candidates.append(googleBase)
            }
        }
        
        tryCandidates(candidates, targetUrlStr: urlString, widgetId: widgetId) { [weak self] image in
            self?.pendingFetches.remove(key)
            completion?(image)
        }
    }
    
    private func tryCandidates(_ urls: [URL], targetUrlStr: String, widgetId: UUID?, completion: @escaping (NSImage?) -> Void) {
        guard let current = urls.first else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: current, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 5.0)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let data = data, data.count > 100,
               let rawImage = NSImage(data: data), rawImage.isValid {
                
                let key = self.cacheKey(for: targetUrlStr, widgetId: widgetId)
                let diskURL = self.diskFileURL(for: key)
                try? data.write(to: diskURL)
                
                let formatted = self.formatIcon(rawImage)
                
                DispatchQueue.main.async {
                    self.memoryCache[key] = formatted
                    self.changeCount += 1
                    NotificationCenter.default.post(
                        name: .webFaviconDidUpdate,
                        object: nil,
                        userInfo: ["widgetId": widgetId as Any, "url": targetUrlStr]
                    )
                    completion(formatted)
                }
            } else {
                // Try next candidate
                let remaining = Array(urls.dropFirst())
                self.tryCandidates(remaining, targetUrlStr: targetUrlStr, widgetId: widgetId, completion: completion)
            }
        }.resume()
    }
    
    private func downloadAndCache(url: URL, targetUrlStr: String, widgetId: UUID?, completion: ((NSImage?) -> Void)?) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6.0)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, data.count > 100, let image = NSImage(data: data), image.isValid else {
                completion?(nil)
                return
            }
            
            let key = self.cacheKey(for: targetUrlStr, widgetId: widgetId)
            let diskURL = self.diskFileURL(for: key)
            try? data.write(to: diskURL)
            
            let formatted = self.formatIcon(image)
            DispatchQueue.main.async {
                self.memoryCache[key] = formatted
                self.changeCount += 1
                NotificationCenter.default.post(
                    name: .webFaviconDidUpdate,
                    object: nil,
                    userInfo: ["widgetId": widgetId as Any, "url": targetUrlStr]
                )
                completion?(formatted)
            }
        }.resume()
    }
    
    // MARK: - Formatting
    
    /// Formats any favicon into a crisp, high-DPI 18x18 point macOS menu bar image with subtle rounded corners.
    private func formatIcon(_ original: NSImage) -> NSImage {
        let targetSize = NSSize(width: 18, height: 18)
        let cornerRadius: CGFloat = 3.5
        
        let newImage = NSImage(size: targetSize, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.addClip()
            original.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        
        // Preserve vivid colors like MenuBarX (isTemplate = false)
        newImage.isTemplate = false
        return newImage
    }
    
    // MARK: - Helpers
    
    private func cacheKey(for urlString: String, widgetId: UUID?) -> String {
        if let id = widgetId {
            return "widget_\(id.uuidString)"
        }
        let host = extractHost(from: urlString) ?? "default"
        return "host_\(host)"
    }
    
    private func diskFileURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).png")
    }
    
    private func extractHost(from urlString: String) -> String? {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = clean.hasPrefix("http") ? clean : "https://" + clean
        return URL(string: full)?.host
    }
    
    private func extractBaseDomain(from host: String) -> String {
        let parts = host.split(separator: ".")
        if parts.count >= 2 {
            return "\(parts[parts.count - 2]).\(parts[parts.count - 1])"
        }
        return host
    }
}
