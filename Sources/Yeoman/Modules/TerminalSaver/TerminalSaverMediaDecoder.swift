import Foundation
import AVFoundation
import CoreGraphics
import ImageIO

public struct TerminalSaverDecodedFrame {
    public let image: CGImage
    public let delaySeconds: Double

    public init(image: CGImage, delaySeconds: Double) {
        self.image = image
        self.delaySeconds = delaySeconds
    }
}

public struct TerminalSaverDecodedMedia {
    public let frames: [TerminalSaverDecodedFrame]

    public init(frames: [TerminalSaverDecodedFrame]) {
        self.frames = frames
    }
}

/// Bounded media decoder using native Apple ImageIO and AVFoundation with strict size, pixel, frame, duration, and time limits.
public enum TerminalSaverMediaDecoder {
    public static func validate(data: Data, fileExtension: String) throws {
        guard let ext = TerminalSaverPolicy.normalizedExtension(fileExtension) else {
            throw SecurityFailure.rejected("Nicht unterstütztes Dateiformat.")
        }
        guard !data.isEmpty, data.count <= TerminalSaverPolicy.byteLimit(forExtension: ext) else {
            throw SecurityFailure.rejected("Datei ist leer oder überschreitet das Größenlimit.")
        }

        if TerminalSaverPolicy.videoExtensions.contains(ext) {
            let tempDir = try SecureDirectory.temporary()
            let fileName = "validate.\(ext)"
            defer {
                try? tempDir.remove(fileName)
                _ = Darwin.rmdir(tempDir.url.path)
            }
            try tempDir.write(data, name: fileName)
            let tempURL = tempDir.url.appendingPathComponent(fileName)
            let decoded = try decodeVideo(url: tempURL, targetFPS: 2, maxEdge: 128, maxSamples: 1)
            guard !decoded.frames.isEmpty else {
                throw SecurityFailure.rejected("Video enthält keine dekodierbaren Frames.")
            }
        } else {
            let decoded = try decodeImage(data: data, maxFrames: TerminalSaverPolicy.maxFrames, maxEdge: 128)
            guard !decoded.frames.isEmpty else {
                throw SecurityFailure.rejected("Bild enthält keine dekodierbaren Frames.")
            }
        }
    }

    public static func decodeImage(
        data: Data,
        maxFrames: Int = TerminalSaverPolicy.maxFrames,
        maxEdge: Int = TerminalSaverPolicy.maxDecodeEdge
    ) throws -> TerminalSaverDecodedMedia {
        guard !data.isEmpty, data.count <= TerminalSaverPolicy.maxImageBytes else {
            throw SecurityFailure.rejected("Bild überschreitet die zulässige Dateigröße.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw SecurityFailure.rejected("Bilddaten konnten nicht geöffnet werden.")
        }

        let count = CGImageSourceGetCount(source)
        let allowedFrames = max(1, min(maxFrames, TerminalSaverPolicy.maxFrames))
        guard count >= 1, count <= allowedFrames else {
            throw SecurityFailure.rejected("Bild besitzt eine ungültige Anzahl an Frames (\(count)).")
        }

        let targetEdge = max(1, min(maxEdge, TerminalSaverPolicy.maxDecodeEdge))
        let deadline = Date().addingTimeInterval(TerminalSaverPolicy.decodeTimeoutSeconds)
        var frames: [TerminalSaverDecodedFrame] = []
        frames.reserveCapacity(count)

        for idx in 0..<count {
            guard Date() <= deadline else {
                throw SecurityFailure.rejected("Zeitlimit bei der Bilddekodierung überschritten.")
            }
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, idx, nil) as? [CFString: Any],
                  let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  width > 0, height > 0,
                  width <= TerminalSaverPolicy.maxSourcePixels / height else {
                throw SecurityFailure.rejected("Frame \(idx) überschreitet das maximale Pixel-Limit.")
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: targetEdge,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, idx, options as CFDictionary) else {
                throw SecurityFailure.rejected("Frame \(idx) konnte nicht dekodiert werden.")
            }
            let delay = frameDelaySeconds(from: props)
            frames.append(TerminalSaverDecodedFrame(image: cgImage, delaySeconds: delay))
        }

        return TerminalSaverDecodedMedia(frames: frames)
    }

    public static func decodeVideo(
        url: URL,
        targetFPS: Int = 12,
        maxEdge: Int = TerminalSaverPolicy.maxDecodeEdge,
        maxSamples: Int = TerminalSaverPolicy.maxFrames
    ) throws -> TerminalSaverDecodedMedia {
        guard url.isFileURL else {
            throw SecurityFailure.rejected("Ungültige Video-URL.")
        }
        var st = stat()
        guard Darwin.lstat(url.path, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFREG,
              st.st_size > 0,
              st.st_size <= TerminalSaverPolicy.maxVideoBytes else {
            throw SecurityFailure.rejected("Videodatei ist kein regulärer Dateieintrag oder überschreitet das Größenlimit.")
        }

        let clampedFPS = TerminalSaverPolicy.clamp(targetFPS, TerminalSaverPolicy.framesPerSecondRange)
        let targetEdge = max(1, min(maxEdge, TerminalSaverPolicy.maxDecodeEdge))
        let frameCap = max(1, min(maxSamples, TerminalSaverPolicy.maxFrames))
        let asset = AVURLAsset(url: url)

        let durationSeconds = try loadDurationSync(asset: asset, timeout: TerminalSaverPolicy.decodeTimeoutSeconds)
        guard durationSeconds.isFinite, durationSeconds > 0, durationSeconds <= TerminalSaverPolicy.maxVideoSeconds else {
            throw SecurityFailure.rejected("Videodauer überschreitet das zulässige Limit von \(Int(TerminalSaverPolicy.maxVideoSeconds))s.")
        }

        let desiredCount = min(frameCap, max(1, Int((durationSeconds * Double(clampedFPS)).rounded(.up))))
        let step = durationSeconds / Double(desiredCount)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: targetEdge, height: targetEdge)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)

        let times: [CMTime] = (0..<desiredCount).map { idx in
            let seconds = min(max(0, durationSeconds - 0.01), Double(idx) * step)
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }
        let boundedDelay = min(max(step, TerminalSaverPolicy.minimumFrameDelay), TerminalSaverPolicy.maximumFrameDelay)
        let deadline = Date().addingTimeInterval(TerminalSaverPolicy.decodeTimeoutSeconds)
        let box = LockedFramesBox()
        let sema = DispatchSemaphore(value: 0)

        Task.detached {
            for await result in generator.images(for: times) {
                if Date() > deadline {
                    generator.cancelAllCGImageGeneration()
                    break
                }
                if case .success(requestedTime: let time, image: let image, actualTime: _) = result {
                    box.append(TerminalSaverDecodedFrame(image: image, delaySeconds: boundedDelay), at: time)
                }
            }
            sema.signal()
        }

        if sema.wait(timeout: .now() + TerminalSaverPolicy.decodeTimeoutSeconds + 0.5) != .success {
            generator.cancelAllCGImageGeneration()
        }

        let frames = box.snapshot()
        guard !frames.isEmpty else {
            throw SecurityFailure.rejected("Video enthält keine dekodierbaren Frames.")
        }
        return TerminalSaverDecodedMedia(frames: frames)
    }

    private final class LockedFramesBox: @unchecked Sendable {
        private let lock = NSLock()
        private var frames: [(time: CMTime, frame: TerminalSaverDecodedFrame)] = []

        func append(_ frame: TerminalSaverDecodedFrame, at time: CMTime) {
            lock.lock()
            frames.append((time, frame))
            lock.unlock()
        }

        func snapshot() -> [TerminalSaverDecodedFrame] {
            lock.lock()
            let copy = frames
            lock.unlock()
            return copy.sorted { $0.time < $1.time }.map(\.frame)
        }
    }

    private static func frameDelaySeconds(from properties: [CFString: Any]) -> Double {
        let dictionaries: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime)
        ]
        for (dictKey, unclampedKey, fallbackKey) in dictionaries {
            if let dict = properties[dictKey] as? [CFString: Any] {
                if let unclamped = (dict[unclampedKey] as? NSNumber)?.doubleValue, unclamped > 0 {
                    return min(max(unclamped, TerminalSaverPolicy.minimumFrameDelay), TerminalSaverPolicy.maximumFrameDelay)
                }
                if let clamped = (dict[fallbackKey] as? NSNumber)?.doubleValue, clamped > 0 {
                    return min(max(clamped, TerminalSaverPolicy.minimumFrameDelay), TerminalSaverPolicy.maximumFrameDelay)
                }
            }
        }
        return 1.0 / 15.0
    }

    private static func loadDurationSync(asset: AVURLAsset, timeout: Double) throws -> Double {
        final class Box: @unchecked Sendable {
            var value: Result<Double, Error>?
        }
        let box = Box()
        let sema = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let cmDuration = try await asset.load(.duration)
                box.value = .success(CMTimeGetSeconds(cmDuration))
            } catch {
                box.value = .failure(error)
            }
            sema.signal()
        }
        guard sema.wait(timeout: .now() + timeout) == .success, let result = box.value else {
            throw SecurityFailure.rejected("Zeitlimit beim Lesen der Videometadaten überschritten.")
        }
        return try result.get()
    }
}
