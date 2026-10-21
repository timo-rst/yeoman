import AppKit
import SwiftUI
import WebKit

public extension Notification.Name {
    static let webFaviconDidUpdate = Notification.Name("de.trst.MacCustomizer.webFaviconDidUpdate")
}

public struct FaviconOption: Identifiable, Equatable, Hashable {
    public let id: String
    public let urlString: String
    public let label: String
    public let isTransparent: Bool
    
    public init(urlString: String, label: String, isTransparent: Bool = true) {
        self.id = urlString
        self.urlString = urlString
        self.label = label
        self.isTransparent = isTransparent
    }
}

public final class WebFaviconManager: ObservableObject {
    public static let shared = WebFaviconManager()
    
    @Published public var changeCount: Int = 0
    @Published public var discoveredOptions: [String: [FaviconOption]] = [:]
    
    private var memoryCache: [String: NSImage] = [:]
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
        
        if let selectedURL = item.selectedFaviconURL, !selectedURL.isEmpty {
            return getOrFetchIcon(forURLString: selectedURL, widgetId: item.id, removeWhite: item.removeWhiteBackground)
        }
        
        return getOrFetchBestIcon(forPageURL: item.url, widgetId: item.id, removeWhite: item.removeWhiteBackground)
    }
    
    /// Returns the raw/preview favicon for settings
    public func previewIcon(for urlString: String, widgetId: UUID? = nil, selectedFaviconURL: String? = nil, removeWhite: Bool = false) -> NSImage? {
        if let selected = selectedFaviconURL, !selected.isEmpty {
            return getOrFetchIcon(forURLString: selected, widgetId: widgetId, removeWhite: removeWhite)
        }
        return getOrFetchBestIcon(forPageURL: urlString, widgetId: widgetId, removeWhite: removeWhite)
    }
    
    /// Returns preview image for an option URL
    public func icon(forOption optionUrl: String, removeWhite: Bool = false) -> NSImage? {
        return getOrFetchIcon(forURLString: optionUrl, widgetId: nil, removeWhite: removeWhite)
    }
    
    /// Returns discovered options for a page URL
    public func options(for pageURL: String) -> [FaviconOption] {
        guard let host = extractHost(from: pageURL) else { return [] }
        return discoveredOptions[host] ?? []
    }
    
    /// Clears cached icons for a widget to force redownload
    public func clearCache(for item: WebWidgetItem) {
        let host = extractHost(from: item.url) ?? "default"
        discoveredOptions.removeValue(forKey: host)
        let key = cacheKey(for: item.url, widgetId: item.id)
        memoryCache.removeValue(forKey: key)
        try? fileManager.removeItem(at: diskFileURL(for: key))
    }
    
    /// Forces a refresh of all discovered favicons
    public func refreshFavicon(for item: WebWidgetItem, completion: (([FaviconOption]) -> Void)? = nil) {
        clearCache(for: item)
        discoverFavicons(for: item.url, widgetId: item.id, completion: completion)
    }
    
    /// Legacy fetchFavicon helper for simple calls
    public func fetchFavicon(for urlString: String, widgetId: UUID? = nil, completion: ((NSImage?) -> Void)? = nil) {
        discoverFavicons(for: urlString, widgetId: widgetId) { [weak self] _ in
            guard let self = self else {
                completion?(nil)
                return
            }
            let img = self.previewIcon(for: urlString, widgetId: widgetId)
            completion?(img)
        }
    }
    
    /// Discovers all available favicon candidates for a URL
    public func discoverFavicons(for urlString: String, widgetId: UUID? = nil, completion: (([FaviconOption]) -> Void)? = nil) {
        guard let host = extractHost(from: urlString), !host.isEmpty else {
            completion?([])
            return
        }
        
        var candidates: [URL] = []
        // Prioritize transparent favicon candidates:
        if let directAsset = URL(string: "https://\(host)/assets/favicon.ico") {
            candidates.append(directAsset)
        }
        if let directFavicon = URL(string: "https://\(host)/favicon.ico") {
            candidates.append(directFavicon)
        }
        if let ddg = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
            candidates.append(ddg)
        }
        if let google = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") {
            candidates.append(google)
        }
        if let appleTouch180 = URL(string: "https://\(host)/apple-touch-icon-180x180.png") {
            candidates.append(appleTouch180)
        }
        if let appleTouch = URL(string: "https://\(host)/apple-touch-icon.png") {
            candidates.append(appleTouch)
        }
        
        let baseDomain = extractBaseDomain(from: host)
        if baseDomain != host {
            if let ddgBase = URL(string: "https://icons.duckduckgo.com/ip3/\(baseDomain).ico") {
                candidates.append(ddgBase)
            }
            if let baseFavicon = URL(string: "https://\(baseDomain)/favicon.ico") {
                candidates.append(baseFavicon)
            }
        }
        
        fetchCandidates(candidates, host: host, widgetId: widgetId, completion: completion)
    }
    
    /// Extracts all favicon links directly from WKWebView document
    public func extractFaviconFromWebView(_ webView: WKWebView, for item: WebWidgetItem) {
        guard item.useFavicon else { return }
        
        let js = """
        (function() {
            var selectors = [
                'link[rel="icon"]',
                'link[rel="shortcut icon"]',
                'link[rel="icon"][type="image/svg+xml"]',
                'link[rel="icon"][type="image/png"]',
                'link[rel="icon"][sizes="192x192"]',
                'link[rel="icon"][sizes="180x180"]',
                'link[rel="icon"][sizes="128x128"]',
                'link[rel="apple-touch-icon"]',
                'link[rel="apple-touch-icon-precomposed"]'
            ];
            var results = [];
            for (var i = 0; i < selectors.length; i++) {
                var els = document.querySelectorAll(selectors[i]);
                for (var j = 0; j < els.length; j++) {
                    if (els[j].href && results.indexOf(els[j].href) === -1) {
                        results.push(els[j].href);
                    }
                }
            }
            return results;
        })()
        """
        
        webView.evaluateJavaScript(js) { [weak self] (result, error) in
            guard let self = self, let host = self.extractHost(from: item.url) else { return }
            if let urls = result as? [String] {
                let candidateURLs = urls.compactMap { URL(string: $0) }
                if !candidateURLs.isEmpty {
                    self.fetchCandidates(candidateURLs, host: host, widgetId: item.id, completion: nil)
                }
            }
        }
    }
    
    // MARK: - Internal Helpers & Downloading
    
    private func fetchCandidates(_ urls: [URL], host: String, widgetId: UUID?, completion: (([FaviconOption]) -> Void)?) {
        let group = DispatchGroup()
        var discovered: [FaviconOption] = self.discoveredOptions[host] ?? []
        let lock = NSLock()
        
        for url in urls {
            let urlString = url.absoluteString
            if discovered.contains(where: { $0.urlString == urlString }) {
                continue
            }
            
            group.enter()
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4.0)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                defer { group.leave() }
                guard let self = self,
                      let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let data = data, data.count > 100,
                      let rawImage = NSImage(data: data), rawImage.isValid else {
                    return
                }
                
                let isTransparent = Self.isImageTransparent(rawImage)
                var label = isTransparent ? "Transparent" : "Mit Hintergrund"
                if urlString.contains("apple-touch-icon") {
                    label = isTransparent ? "App-Icon (Transparent)" : "App-Kachel (iOS)"
                } else if urlString.contains("duckduckgo") {
                    label = isTransparent ? "DuckDuckGo (Transparent)" : "DuckDuckGo"
                } else if urlString.contains("google") {
                    label = isTransparent ? "Google (Transparent)" : "Google"
                } else if urlString.hasSuffix(".ico") {
                    label = isTransparent ? "Favicon.ico (Transparent)" : "Favicon.ico"
                } else if urlString.hasSuffix(".svg") {
                    label = "Vektor (SVG)"
                }
                
                let option = FaviconOption(urlString: urlString, label: label, isTransparent: isTransparent)
                
                // Cache raw image data on disk
                let diskKey = self.diskKey(forURLString: urlString)
                let diskURL = self.diskFileURL(for: diskKey)
                try? data.write(to: diskURL)
                
                // Format & cache in memory
                let formatted = self.formatIcon(rawImage)
                
                lock.lock()
                if !discovered.contains(where: { $0.urlString == urlString }) {
                    discovered.append(option)
                }
                self.memoryCache[diskKey] = formatted
                lock.unlock()
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // Sort: transparent options first!
            discovered.sort { (a, b) -> Bool in
                if a.isTransparent != b.isTransparent {
                    return a.isTransparent && !b.isTransparent
                }
                return a.label < b.label
            }
            
            self.discoveredOptions[host] = discovered
            self.changeCount += 1
            NotificationCenter.default.post(
                name: .webFaviconDidUpdate,
                object: nil,
                userInfo: ["host": host, "widgetId": widgetId as Any]
            )
            completion?(discovered)
        }
    }
    
    private func getOrFetchBestIcon(forPageURL pageURL: String, widgetId: UUID?, removeWhite: Bool) -> NSImage? {
        guard let host = extractHost(from: pageURL) else { return nil }
        
        // 1. If options already discovered, pick the first transparent option, or first option
        if let options = discoveredOptions[host], !options.isEmpty {
            let chosen = options.first(where: { $0.isTransparent }) ?? options[0]
            return getOrFetchIcon(forURLString: chosen.urlString, widgetId: widgetId, removeWhite: removeWhite)
        }
        
        // 2. Otherwise trigger discovery and check widget disk cache
        let key = cacheKey(for: pageURL, widgetId: widgetId)
        if let cached = memoryCache[key] {
            return removeWhite ? Self.makeWhiteTransparent(cached) : cached
        }
        
        let fileURL = diskFileURL(for: key)
        if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
            var formatted = formatIcon(image)
            if removeWhite {
                formatted = Self.makeWhiteTransparent(formatted)
            }
            memoryCache[key] = formatted
            return formatted
        }
        
        discoverFavicons(for: pageURL, widgetId: widgetId)
        return nil
    }
    
    private func getOrFetchIcon(forURLString iconURLString: String, widgetId: UUID?, removeWhite: Bool) -> NSImage? {
        let key = diskKey(forURLString: iconURLString)
        let cacheKey = removeWhite ? "\(key)_nowhite" : key
        
        if let cached = memoryCache[cacheKey] {
            return cached
        }
        
        let fileURL = diskFileURL(for: key)
        if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
            var formatted = formatIcon(image)
            if removeWhite {
                formatted = Self.makeWhiteTransparent(formatted)
            }
            memoryCache[cacheKey] = formatted
            return formatted
        }
        
        // Fetch specific icon URL
        guard let url = URL(string: iconURLString) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4.0)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data, data.count > 100,
                  let image = NSImage(data: data), image.isValid else { return }
            
            try? data.write(to: fileURL)
            var formatted = self.formatIcon(image)
            if removeWhite {
                formatted = Self.makeWhiteTransparent(formatted)
            }
            DispatchQueue.main.async {
                self.memoryCache[cacheKey] = formatted
                self.changeCount += 1
                NotificationCenter.default.post(name: .webFaviconDidUpdate, object: nil)
            }
        }.resume()
        
        return nil
    }
    
    // MARK: - Image Processing
    
    /// Formats any favicon into a crisp, high-DPI 18x18 point macOS menu bar image
    private func formatIcon(_ original: NSImage) -> NSImage {
        let targetSize = NSSize(width: 18, height: 18)
        let cornerRadius: CGFloat = 3.5
        
        let newImage = NSImage(size: targetSize, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.addClip()
            original.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        
        newImage.isTemplate = false
        return newImage
    }
    
    /// Detects if an image has transparency at its corners
    public static func isImageTransparent(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return false
        }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0 && h > 0 else { return false }
        
        let c1 = rep.colorAt(x: 0, y: 0)
        let c2 = rep.colorAt(x: max(0, w - 1), y: 0)
        let c3 = rep.colorAt(x: 0, y: max(0, h - 1))
        let c4 = rep.colorAt(x: max(0, w - 1), y: max(0, h - 1))
        
        let a1 = c1?.alphaComponent ?? 1.0
        let a2 = c2?.alphaComponent ?? 1.0
        let a3 = c3?.alphaComponent ?? 1.0
        let a4 = c4?.alphaComponent ?? 1.0
        
        return (a1 < 0.2 || a2 < 0.2 || a3 < 0.2 || a4 < 0.2)
    }
    
    /// Strips solid white background from an image if corners are white
    public static func makeWhiteTransparent(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else {
            return image
        }
        
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0 && h > 0 else { return image }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let pixelData = ctx.data else { return image }
        let buffer = pixelData.bindMemory(to: UInt8.self, capacity: w * h * 4)
        
        let cR = buffer[0]
        let cG = buffer[1]
        let cB = buffer[2]
        
        // If corner is white / near white
        if cR > 230 && cG > 230 && cB > 230 {
            for i in 0..<(w * h) {
                let offset = i * 4
                let r = buffer[offset]
                let g = buffer[offset + 1]
                let b = buffer[offset + 2]
                if r > 225 && g > 225 && b > 225 {
                    buffer[offset + 3] = 0 // make alpha 0
                }
            }
            
            if let resultCG = ctx.makeImage() {
                return NSImage(cgImage: resultCG, size: image.size)
            }
        }
        
        return image
    }
    
    // MARK: - Cache Keys
    
    private func cacheKey(for urlString: String, widgetId: UUID?) -> String {
        if let id = widgetId {
            return "widget_\(id.uuidString)"
        }
        let host = extractHost(from: urlString) ?? "default"
        return "host_\(host)"
    }
    
    private func diskKey(forURLString iconURL: String) -> String {
        let safe = iconURL.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "&", with: "_")
            .prefix(120)
        return "icon_\(safe)"
    }
    
    private func diskFileURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).png")
    }
    
    public func extractHost(from urlString: String) -> String? {
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
