import AppKit

public final class ClipboardImageCache {
    public static let shared = ClipboardImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; return q }()
    private let lock = NSLock()
    private var generation = 0
    private var waiters: [String: [(NSImage?) -> Void]] = [:]
    private init() { cache.countLimit = 300; cache.totalCostLimit = 40 * 1024 * 1024 }
    public func clear() {
        lock.lock()
        generation += 1; cache.removeAllObjects(); queue.cancelAllOperations()
        let callbacks = waiters.values.flatMap { $0 }; waiters.removeAll()
        lock.unlock()
        DispatchQueue.main.async { callbacks.forEach { $0(nil) } }
    }
    public func evict(fileName: String) { clear() }
    private func key(_ item: ClipboardItem, _ size: CGFloat) -> NSString { "\(item.id)-\(Int(size))" as NSString }
    public func cachedThumbnail(for item: ClipboardItem, maxPixelSize: CGFloat = 200) -> NSImage? {
        guard maxPixelSize.isFinite, (1...4096).contains(maxPixelSize) else { return nil }
        return cache.object(forKey: key(item, maxPixelSize))
    }
    public func loadThumbnail(for item: ClipboardItem, maxPixelSize: CGFloat = 200, completion: @escaping (NSImage?) -> Void) {
        guard maxPixelSize.isFinite, (1...4096).contains(maxPixelSize),
              let data = ClipboardHistoryStore.shared.imageData(for: item) else { completion(nil); return }
        if let cached = cachedThumbnail(for: item, maxPixelSize: maxPixelSize) { completion(cached); return }
        let cacheKey = key(item, maxPixelSize), requestKey = cacheKey as String
        lock.lock()
        if waiters[requestKey] != nil {
            waiters[requestKey]!.append(completion); lock.unlock(); return
        }
        guard waiters.count < 2 else { lock.unlock(); completion(nil); return }
        waiters[requestKey] = [completion]
        let expected = generation
        lock.unlock()
        queue.addOperation {
            let cg = try? BoundedImage.decode(data, thumbnail: Int(maxPixelSize))
            let image = cg.map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async {
                self.lock.lock()
                let valid = self.generation == expected
                let callbacks = self.waiters.removeValue(forKey: requestKey) ?? []
                if valid, let image, let cg { self.cache.setObject(image, forKey: cacheKey, cost: cg.width * cg.height * 4) }
                self.lock.unlock()
                callbacks.forEach { $0(valid ? image : nil) }
            }
        }
    }
    public func loadFullImage(for item: ClipboardItem, completion: @escaping (NSImage?) -> Void) {
        loadThumbnail(for: item, maxPixelSize: 2048, completion: completion)
    }
}
