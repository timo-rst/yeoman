import Foundation
import AppKit
import ImageIO

public enum SecurityFailure: LocalizedError {
    case rejected(String)
    public var errorDescription: String? {
        switch self { case .rejected(let reason): return reason }
    }
}

public enum SecurityPolicy {
    public static let textBytes = 1_048_576
    public static let imageBytes = 20 * 1_048_576
    public static let historyBytes = 100 * 1_048_576
    public static let imagePixels = 16_000_000
    public static let widgetCount = 32
    public static func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
    public static func webURL(_ raw: String) -> URL? {
        guard raw.utf8.count <= 8192 else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = text.contains(":") ? text : "https://" + text
        guard let c = URLComponents(string: normalized),
              c.scheme?.lowercased() == "https" || c.scheme?.lowercased() == "http",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.port == nil || (1...65535).contains(c.port!) else { return nil }
        return c.url
    }
    public static func origin(_ url: URL?) -> String {
        guard let url, let host = url.host, let scheme = url.scheme else { return "Keine Webseite" }
        return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
    }
    public static func multiply(_ value: Int64, by factor: Int) -> Int64? {
        let result = value.multipliedReportingOverflow(by: Int64(factor))
        return result.overflow ? nil : result.partialValue
    }
}

public extension UUID {
    var isValidWebKitIdentifier: Bool {
        withUnsafeBytes(of: uuid) { buffer in
            // WebKit's WTF::UUID reserves integer values 0 and 1. NSUUID's canonical
            // representation of the second sentinel ends in ...0001.
            guard buffer.contains(where: { $0 != 0 }) else { return false }
            return !(buffer.dropLast().allSatisfy { $0 == 0 } && buffer.last == 1)
        }
    }
}

public enum BoundedImage {
    public static func decode(_ data: Data, bytes: Int = SecurityPolicy.imageBytes,
                              pixels: Int = SecurityPolicy.imagePixels, thumbnail: Int = 4096) throws -> CGImage {
        guard data.count <= bytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw SecurityFailure.rejected("Bild überschreitet die zulässigen Grenzen oder ist ungültig.")
        }
        let count = CGImageSourceGetCount(source)
        guard count >= 1 && count <= 32 else {
            throw SecurityFailure.rejected("Bild hat ungültige Anzahl an Frames.")
        }
        var chosenIndex: Int?
        var chosenWidth: Int = 0
        var chosenHeight: Int = 0
        for idx in 0..<count {
            if let props = CGImageSourceCopyPropertiesAtIndex(source, idx, nil) as? [CFString: Any],
               let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
               let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
               w > 0, h > 0, w <= pixels / h {
                chosenIndex = idx
                chosenWidth = w
                chosenHeight = h
                break
            }
        }
        guard let idx = chosenIndex, chosenWidth > 0, chosenHeight > 0 else {
            throw SecurityFailure.rejected("Bild überschreitet die zulässigen Grenzen oder ist ungültig.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(4096, thumbnail)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, idx, options as CFDictionary) else {
            throw SecurityFailure.rejected("Bild konnte nicht dekodiert werden.")
        }
        return image
    }
}
