import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import Vision

public struct TerminalSaverAlphaMask: Equatable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = max(0, width)
        self.height = max(0, height)
        let expected = self.width * self.height
        self.bytes = bytes.count == expected ? bytes : Array(repeating: 0, count: expected)
    }
}

/// On-device foreground subject isolation powered by Apple Vision (`VNGenerateForegroundInstanceMaskRequest`).
public enum TerminalSaverBackgroundRemover {
    public static func foregroundMask(for image: CGImage) throws -> TerminalSaverAlphaMask? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            return nil
        }

        let pixelBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var out = [UInt8](repeating: 0, count: width * height)

        if format == kCVPixelFormatType_OneComponent32Float {
            for y in 0..<height {
                let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                let rowOut = y * width
                for x in 0..<width {
                    let v = min(1.0, max(0.0, rowPtr[x]))
                    out[rowOut + x] = UInt8((v * 255.0).rounded())
                }
            }
        } else if format == kCVPixelFormatType_OneComponent8 {
            for y in 0..<height {
                let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                let rowOut = y * width
                for x in 0..<width {
                    out[rowOut + x] = rowPtr[x]
                }
            }
        } else {
            return nil
        }

        return TerminalSaverAlphaMask(width: width, height: height, bytes: out)
    }

    /// Suppresses single-frame mask flicker while preserving moving edges.
    public static func smoothMasks(_ masks: [TerminalSaverAlphaMask]) -> [TerminalSaverAlphaMask] {
        guard masks.count >= 3 else { return masks }
        var result = masks
        for idx in 1..<(masks.count - 1) {
            let prev = masks[idx - 1]
            let cur = masks[idx]
            let next = masks[idx + 1]
            guard prev.width == cur.width, prev.height == cur.height,
                  next.width == cur.width, next.height == cur.height,
                  !cur.bytes.isEmpty else {
                continue
            }
            var smoothed = cur.bytes
            for p in 0..<smoothed.count {
                let pVal = Int(prev.bytes[p])
                let nVal = Int(next.bytes[p])
                if abs(pVal - nVal) <= 48 {
                    smoothed[p] = UInt8((pVal + 2 * Int(cur.bytes[p]) + nVal) / 4)
                }
            }
            result[idx] = TerminalSaverAlphaMask(width: cur.width, height: cur.height, bytes: smoothed)
        }
        return result
    }

    public static func applyMask(_ mask: TerminalSaverAlphaMask, to image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, mask.width > 0, mask.height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(rect)
        context.draw(image, in: rect)

        guard let rawData = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        let pixels = rawData.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        for y in 0..<height {
            let my = mask.height == height ? y : min(mask.height - 1, (y * mask.height) / height)
            let maskRow = my * mask.width
            let pixelRow = y * bytesPerRow
            for x in 0..<width {
                let mx = mask.width == width ? x : min(mask.width - 1, (x * mask.width) / width)
                let m = mask.bytes[maskRow + mx]
                let off = pixelRow + x * 4
                if m < 24 {
                    pixels[off] = 0
                    pixels[off + 1] = 0
                    pixels[off + 2] = 0
                    pixels[off + 3] = 0
                } else if m < 255 {
                    let factor = Float(m) / 255.0
                    pixels[off] = UInt8(min(255, max(0, (Float(pixels[off]) * factor).rounded())))
                    pixels[off + 1] = UInt8(min(255, max(0, (Float(pixels[off + 1]) * factor).rounded())))
                    pixels[off + 2] = UInt8(min(255, max(0, (Float(pixels[off + 2]) * factor).rounded())))
                    pixels[off + 3] = UInt8(min(255, max(0, (Float(pixels[off + 3]) * factor).rounded())))
                }
            }
        }
        return context.makeImage()
    }

    /// Generates smoothed foreground-isolated RGBA frames or returns `nil` when no subject is detected.
    public static func generateCutout(
        frames: [TerminalSaverDecodedFrame],
        timeoutSeconds: Double = TerminalSaverPolicy.cutoutTimeoutSeconds
    ) -> [TerminalSaverDecodedFrame]? {
        let count = min(frames.count, TerminalSaverPolicy.maxCutoutFrames)
        guard count > 0 else { return nil }

        let deadline = Date().addingTimeInterval(max(1.0, timeoutSeconds))
        var rawMasks = [TerminalSaverAlphaMask?](repeating: nil, count: count)
        var firstValid: TerminalSaverAlphaMask?
        var anyForeground = false

        for i in 0..<count {
            if Date() > deadline { break }
            if let mask = try? foregroundMask(for: frames[i].image),
               mask.bytes.contains(where: { $0 >= 64 }) {
                rawMasks[i] = mask
                anyForeground = true
                if firstValid == nil { firstValid = mask }
            }
        }

        guard anyForeground, let initialFallback = firstValid else {
            return nil
        }

        var filledMasks: [TerminalSaverAlphaMask] = []
        filledMasks.reserveCapacity(count)
        var lastValid = initialFallback
        for i in 0..<count {
            if let m = rawMasks[i] {
                lastValid = m
                filledMasks.append(m)
            } else {
                filledMasks.append(lastValid)
            }
        }

        let smoothed = smoothMasks(filledMasks)
        var output: [TerminalSaverDecodedFrame] = []
        output.reserveCapacity(count)
        for i in 0..<count {
            let maskedImage = applyMask(smoothed[i], to: frames[i].image) ?? frames[i].image
            output.append(TerminalSaverDecodedFrame(image: maskedImage, delaySeconds: frames[i].delaySeconds))
        }
        return output
    }

    public static func encodeCutoutAPNG(frames: [TerminalSaverDecodedFrame]) throws -> Data {
        guard !frames.isEmpty, frames.count <= TerminalSaverPolicy.maxCutoutFrames else {
            throw SecurityFailure.rejected("Ungültige Frame-Anzahl für Cutout-Cache.")
        }
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.png.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw SecurityFailure.rejected("Cutout-PNG konnte nicht erstellt werden.")
        }

        if frames.count > 1 {
            CGImageDestinationSetProperties(dest, [
                kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
            ] as CFDictionary)
        }

        for frame in frames {
            let props: CFDictionary = frames.count > 1
                ? [
                    kCGImagePropertyPNGDictionary: [
                        kCGImagePropertyAPNGDelayTime: frame.delaySeconds,
                        kCGImagePropertyAPNGUnclampedDelayTime: frame.delaySeconds
                    ]
                ] as CFDictionary
                : [:] as CFDictionary
            CGImageDestinationAddImage(dest, frame.image, props)
        }

        guard CGImageDestinationFinalize(dest) else {
            throw SecurityFailure.rejected("Cutout-PNG konnte nicht finalisiert werden.")
        }
        let result = mutableData as Data
        guard !result.isEmpty, result.count <= TerminalSaverPolicy.maxImageBytes else {
            throw SecurityFailure.rejected("Cutout-Cache überschreitet das Größenlimit.")
        }
        return result
    }
}
