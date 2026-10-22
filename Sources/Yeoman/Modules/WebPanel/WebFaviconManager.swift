import AppKit
import SwiftUI
import WebKit
import CryptoKit

public extension Notification.Name {
    static let webFaviconDidUpdate = Notification.Name("de.trst.Yeoman.webFaviconDidUpdate")
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

// Native network fetching is deliberately absent. Page-controlled resources stay
// inside WebKit and its origin/network sandbox. Only bounded raster bytes cross.
public final class WebFaviconManager: ObservableObject {
    public static let shared = WebFaviconManager()
    @Published public private(set) var changeCount = 0
    @Published public private(set) var legacyCleanupError: String?
    private let cache = NSCache<NSString, NSImage>()
    private var optionsByWidget: [UUID: [FaviconOption]] = [:]
    private var views: [UUID: WeakWebView] = [:]
    private var pending: [UUID: WebWidgetItem] = [:]
    private var active: [UUID: UUID] = [:]
    private var generations: [UUID: Int] = [:]
    private var insertionOrder: [NSString] = []
    private let decoding = OperationQueue()
    private struct WeakWebView { weak var value: WKWebView? }
    private init() {
        cache.countLimit = 256; cache.totalCostLimit = 8 * 1024 * 1024
        decoding.maxConcurrentOperationCount = 2
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Yeoman", isDirectory: true)
            if FileManager.default.fileExists(atPath: appSupport.path) {
                let root = try SecureDirectory(appSupport, create: false)
                if try root.exists("favicons") {
                    try root.child("favicons", create: false).purgeRegularFiles()
                }
            }
        } catch {
            legacyCleanupError = "Alter Favicon-Cache konnte nicht sicher bereinigt werden: \(error.localizedDescription)"
        }
    }
    public static func cacheKey(widget: UUID, url: String, removeWhite: Bool) -> String {
        let raw = "\(widget.uuidString)|\(removeWhite)|\(url)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func menuBarIcon(for item: WebWidgetItem) -> NSImage? {
        previewIcon(for: item.url, widgetId: item.id, selectedFaviconURL: item.selectedFaviconURL, removeWhite: item.removeWhiteBackground)
    }
    public func previewIcon(for urlString: String, widgetId: UUID? = nil, selectedFaviconURL: String? = nil, removeWhite: Bool = false) -> NSImage? {
        precondition(Thread.isMainThread)
        guard let id = widgetId, let options = optionsByWidget[id],
              let chosen = selectedFaviconURL ?? options.first?.urlString else { return nil }
        return cache.object(forKey: Self.cacheKey(widget: id, url: chosen, removeWhite: removeWhite) as NSString)
    }
    public func icon(forOption optionUrl: String, widgetId: UUID, removeWhite: Bool = false) -> NSImage? {
        precondition(Thread.isMainThread)
        guard optionsByWidget[widgetId]?.contains(where: { $0.urlString == optionUrl }) == true else { return nil }
        return cache.object(forKey: Self.cacheKey(widget: widgetId, url: optionUrl, removeWhite: removeWhite) as NSString)
    }
    public func options(for widgetId: UUID?) -> [FaviconOption] {
        precondition(Thread.isMainThread)
        return widgetId.flatMap { optionsByWidget[$0] } ?? []
    }
    public func clearCache(for item: WebWidgetItem) {
        precondition(Thread.isMainThread)
        generations[item.id, default: 0] += 1
        optionsByWidget.removeValue(forKey: item.id)
        // NSCache is bounded; clear avoids retaining removed profiles.
        cache.removeAllObjects()
        insertionOrder.removeAll(keepingCapacity: true)
    }
    public func removeWidget(_ item: WebWidgetItem) {
        clearCache(for: item); views.removeValue(forKey: item.id); pending.removeValue(forKey: item.id)
        if active[item.id] == nil { generations.removeValue(forKey: item.id) }
    }
    public func refreshFavicon(for item: WebWidgetItem, completion: (([FaviconOption]) -> Void)? = nil) {
        clearCache(for: item)
        if let web = views[item.id]?.value { extractFaviconFromWebView(web, for: item) }
        completion?(options(for: item.id))
    }
    public func fetchFavicon(for urlString: String, widgetId: UUID? = nil, completion: ((NSImage?) -> Void)? = nil) {
        completion?(previewIcon(for: urlString, widgetId: widgetId))
    }
    public func discoverFavicons(for urlString: String, widgetId: UUID? = nil, completion: (([FaviconOption]) -> Void)? = nil) {
        completion?(options(for: widgetId))
    }
    public func extractHost(from urlString: String) -> String? { SecurityPolicy.webURL(urlString)?.host }
    public func extractFaviconFromWebView(_ webView: WKWebView, for item: WebWidgetItem) {
        precondition(Thread.isMainThread)
        guard item.useFavicon else { return }
        views[item.id] = WeakWebView(value: webView)
        guard pending.count < SecurityPolicy.widgetCount, active[item.id] == nil else { return }
        pending[item.id] = item; drain()
    }
    private func drain() {
        precondition(Thread.isMainThread)
        while active.count < 2, let (id, item) = pending.first {
            pending.removeValue(forKey: id)
            guard let web = views[id]?.value else { continue }
            let token = UUID()
            active[id] = token
            let generation = generations[id, default: 0]
            let pageURL = web.url
            web.callAsyncJavaScript(Self.script, arguments: ["selected": item.selectedFaviconURL ?? ""], in: nil, in: .defaultClient) { result in
                DispatchQueue.main.async {
                    guard self.active[id] == token else { return }
                    guard case .success(let raw) = result, let entries = raw as? [[String: String]], entries.count <= 8 else {
                        self.finish(id: id, token: token); return
                    }
                    self.decoding.addOperation {
                        var decoded: [(FaviconOption, NSImage, NSImage)] = []
                        for entry in entries {
                            guard let url = entry["url"], url.utf8.count <= 8192,
                                  let candidate = URL(string: url), let pageURL,
                                  Self.allows(candidate: candidate, page: pageURL),
                                  let encoded = entry["data"], encoded.utf8.count <= 2_800_000,
                                  let data = Data(base64Encoded: encoded),
                                  let cg = try? BoundedImage.decode(data, bytes: 2 * 1_048_576, pixels: 4_000_000, thumbnail: 64) else { continue }
                            let image = NSImage(cgImage: cg, size: NSSize(width: 18, height: 18))
                            let option = FaviconOption(urlString: url, label: "Webseiten-Icon", isTransparent: Self.isImageTransparent(image))
                            decoded.append((option, image, Self.makeWhiteTransparent(image)))
                        }
                        DispatchQueue.main.async {
                            defer { self.finish(id: id, token: token) }
                            guard self.active[id] == token,
                                  self.generations[id, default: 0] == generation,
                                  self.views[id]?.value != nil else { return }
                            self.optionsByWidget[id] = decoded.map { $0.0 }
                            for (option, image, transparent) in decoded {
                                self.insert(image, key: Self.cacheKey(widget: id, url: option.urlString, removeWhite: false) as NSString)
                                self.insert(transparent, key: Self.cacheKey(widget: id, url: option.urlString, removeWhite: true) as NSString)
                            }
                            self.changeCount += 1
                            NotificationCenter.default.post(name: .webFaviconDidUpdate, object: nil, userInfo: ["widgetId": id])
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                self.finish(id: id, token: token)
            }
        }
    }
    private func finish(id: UUID, token: UUID) {
        precondition(Thread.isMainThread)
        guard active[id] == token else { return }
        active.removeValue(forKey: id)
        if views[id]?.value == nil { generations.removeValue(forKey: id) }
        drain()
    }
    private func insert(_ image: NSImage, key: NSString) {
        insertionOrder.removeAll { $0 == key }
        insertionOrder.append(key)
        cache.setObject(image, forKey: key, cost: 64 * 64 * 4)
        while insertionOrder.count > 256 { cache.removeObject(forKey: insertionOrder.removeFirst()) }
    }
    public static func allows(candidate: URL, page: URL) -> Bool {
        guard SecurityPolicy.webURL(candidate.absoluteString) != nil,
              candidate.scheme == "https", page.scheme == "https",
              let host = candidate.host, host == page.host else { return false }
        return (candidate.port ?? 443) == (page.port ?? 443)
    }
    private static let script = #"""
    const base = new URL(location.href);
    if (base.protocol !== 'https:' || base.username || base.password) return [];
    const candidates = [];
    const add = value => {
        try {
            const u = new URL(value, base);
            if (u.protocol === 'https:' && u.origin === base.origin && !u.username && !u.password &&
                u.href.length <= 8192 && candidates.length < 8 && !candidates.includes(u.href)) candidates.push(u.href);
        } catch (_) {}
    };
    if (selected) add(selected);
    const links = document.querySelectorAll('link[rel~="icon"],link[rel="apple-touch-icon"]');
    for (let i = 0; i < Math.min(links.length, 64) && candidates.length < 8; i++) add(links[i].href);
    add('/favicon.ico');
    const result = [];
    const deadline = Date.now() + 4000;
    for (const url of candidates) {
        const remaining = deadline - Date.now();
        if (remaining <= 0) break;
        const abort = new AbortController();
        const timer = setTimeout(() => abort.abort(), remaining);
        try {
            const response = await fetch(url, {mode:'same-origin', credentials:'omit', redirect:'error', signal:abort.signal});
            if (!response.ok || !response.body) continue;
            const reader = response.body.getReader();
            let length = 0; const chunks = [];
            while (true) {
                const part = await reader.read(); if (part.done) break;
                length += part.value.byteLength;
                if (length > 2097152) { await reader.cancel(); throw new Error('limit'); }
                chunks.push(part.value);
            }
            let binary = '';
            for (const chunk of chunks) {
                for (let i = 0; i < chunk.length; i += 16384) binary += String.fromCharCode(...chunk.subarray(i, i + 16384));
            }
            result.push({url, data:btoa(binary)});
        } catch (_) {} finally { clearTimeout(timer); }
    }
    return result;
    """#
    public static func isImageTransparent(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        return cg.alphaInfo != .none && cg.alphaInfo != .noneSkipFirst && cg.alphaInfo != .noneSkipLast
    }
    public static func makeWhiteTransparent(_ image: NSImage) -> NSImage {
        // Only already bounded 64px images arrive here; do not expand original data.
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width <= 64, cg.height <= 64,
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let memory = context.data else { return image }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let pixels = memory.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(cg.width * cg.height) where pixels[i*4] > 230 && pixels[i*4+1] > 230 && pixels[i*4+2] > 230 { pixels[i*4+3] = 0 }
        return context.makeImage().map { NSImage(cgImage: $0, size: image.size) } ?? image
    }
    public func imageFingerprint(_ image: NSImage) -> String? {
        guard let data = image.tiffRepresentation else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
