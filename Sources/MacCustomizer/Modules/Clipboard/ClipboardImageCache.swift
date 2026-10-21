import AppKit
import ImageIO

public final class ClipboardImageCache {
    public static let shared = ClipboardImageCache()
    
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let fullImageCache = NSCache<NSString, NSImage>()
    private let ioQueue = DispatchQueue(label: "de.trst.maccustomizer.clipboard.imagecache", qos: .userInitiated, attributes: .concurrent)
    
    private init() {
        thumbnailCache.countLimit = 300
        thumbnailCache.totalCostLimit = 40 * 1024 * 1024 // 40 MB max for thumbnails
        
        fullImageCache.countLimit = 6
        fullImageCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB max for full previews
    }
    
    private func cacheKey(for fileName: String, size: CGFloat) -> NSString {
        "\(fileName)_\(Int(size))" as NSString
    }
    
    /// Synchronous memory-cache check (0ms latency, zero disk I/O, zero lag)
    public func cachedThumbnail(for item: ClipboardItem, maxPixelSize: CGFloat = 200) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let key = cacheKey(for: fileName, size: maxPixelSize)
        return thumbnailCache.object(forKey: key)
    }
    
    /// Asynchronously loads or generates downscaled thumbnail using hardware-accelerated ImageIO
    public func loadThumbnail(for item: ClipboardItem, maxPixelSize: CGFloat = 200, completion: @escaping (NSImage?) -> Void) {
        guard let fileName = item.imageFileName, let originalURL = item.imageURL else {
            completion(nil)
            return
        }
        
        let key = cacheKey(for: fileName, size: maxPixelSize)
        if let cached = thumbnailCache.object(forKey: key) {
            completion(cached)
            return
        }
        
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Check if on-disk thumbnail already exists
            let thumbFileName = "\(fileName)_thumb_\(Int(maxPixelSize)).jpg"
            let thumbURL = originalURL.deletingLastPathComponent().appendingPathComponent(thumbFileName)
            
            if FileManager.default.fileExists(atPath: thumbURL.path),
               let thumbData = try? Data(contentsOf: thumbURL),
               let thumbImage = NSImage(data: thumbData) {
                let cost = Int(thumbImage.size.width * thumbImage.size.height * 4)
                self.thumbnailCache.setObject(thumbImage, forKey: key, cost: cost)
                DispatchQueue.main.async { completion(thumbImage) }
                return
            }
            
            // 2. Decode thumbnail directly via ImageIO without loading or decompressing the full 4K bitmap
            guard FileManager.default.fileExists(atPath: originalURL.path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            
            guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let thumbImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let cost = cgImage.width * cgImage.height * 4
            self.thumbnailCache.setObject(thumbImage, forKey: key, cost: cost)
            
            // 3. Save thumbnail to disk in background for instant loading on next app launch
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let jpgData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                try? jpgData.write(to: thumbURL, options: .atomic)
            }
            
            DispatchQueue.main.async {
                completion(thumbImage)
            }
        }
    }
    
    /// Asynchronously loads full resolution image for detail view
    public func loadFullImage(for item: ClipboardItem, completion: @escaping (NSImage?) -> Void) {
        guard let fileName = item.imageFileName, let url = item.imageURL else {
            completion(nil)
            return
        }
        
        let key = fileName as NSString
        if let cached = fullImageCache.object(forKey: key) {
            completion(cached)
            return
        }
        
        ioQueue.async { [weak self] in
            guard let self = self, FileManager.default.fileExists(atPath: url.path),
                  let img = NSImage(contentsOf: url) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let cost = Int(img.size.width * img.size.height * 4)
            self.fullImageCache.setObject(img, forKey: key, cost: cost)
            DispatchQueue.main.async {
                completion(img)
            }
        }
    }
    
    /// Pre-generates thumbnail in background immediately when a screenshot or image is copied
    public func preheatThumbnail(for fileName: String, originalURL: URL, maxPixelSize: CGFloat = 200) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let key = self.cacheKey(for: fileName, size: maxPixelSize)
            let thumbFileName = "\(fileName)_thumb_\(Int(maxPixelSize)).jpg"
            let thumbURL = originalURL.deletingLastPathComponent().appendingPathComponent(thumbFileName)
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            
            guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
            
            let thumbImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let cost = cgImage.width * cgImage.height * 4
            self.thumbnailCache.setObject(thumbImage, forKey: key, cost: cost)
            
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let jpgData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                try? jpgData.write(to: thumbURL, options: .atomic)
            }
        }
    }
    
    /// Evicts caches for an item upon deletion
    public func evict(fileName: String) {
        fullImageCache.removeObject(forKey: fileName as NSString)
        thumbnailCache.removeObject(forKey: cacheKey(for: fileName, size: 120))
        thumbnailCache.removeObject(forKey: cacheKey(for: fileName, size: 200))
        thumbnailCache.removeObject(forKey: cacheKey(for: fileName, size: 300))
    }
}
