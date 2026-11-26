import Foundation
import Darwin

/// Centralized limits for Terminal Saver. All externally influenced sizes are bounded here.
public enum TerminalSaverPolicy {
    public static let maxImageBytes = 25 * 1_048_576
    public static let maxVideoBytes = 40 * 1_048_576
    public static let maxConfigBytes = 512 * 1024
    public static let maxSourcePixels = 16_000_000
    public static let maxFrames = 300
    public static let maxVideoSeconds: Double = 30
    public static let maxDecodeEdge = 512
    public static let decodeTimeoutSeconds: Double = 15
    public static let maxCutoutEdge = 256
    public static let maxCutoutFrames = 90
    public static let cutoutTimeoutSeconds: Double = 25.0
    public static let maxLibraryItems = 64
    public static let maxDisplayNameLength = 120
    public static let columnRange = 10...500
    public static let rowRange = 5...200
    public static let idleTimeoutRange = 15...1800
    public static let defaultIdleTimeout = 120
    public static let autoAdvanceDurationRange = 5...600
    public static let wakeDurationRange = 140...2800
    public static let defaultWakeDuration = 280
    public static let startDurationRange = 210...4200
    public static let defaultStartDuration = 420
    public static let transitionDurationRange = 150...3000
    public static let defaultTransitionDuration = 300
    public static let maxCachedSessionPlaybacks = 8
    public static let maxInputBytes = 64
    public static let inputSequenceTimeout: TimeInterval = 0.05
    public static let transitionSpeedRange: ClosedRange<Double> = 0.1...2.0
    public static let defaultTransitionSpeed: Double = 1.0

    public static func clampedTransitionSpeed(_ value: Double) -> Double {
        SecurityPolicy.bounded(value, transitionSpeedRange, fallback: defaultTransitionSpeed)
    }

    public static func transitionDurationMilliseconds(
        defaultDuration: Int,
        range: ClosedRange<Int>,
        speed: Double
    ) -> Int {
        let safeSpeed = clampedTransitionSpeed(speed)
        let raw = Int((Double(defaultDuration) / safeSpeed).rounded())
        return clamp(raw, range)
    }

    public static func transitionSpeed(
        durationMilliseconds: Int,
        defaultDuration: Int,
        range: ClosedRange<Int>
    ) -> Double {
        let clamped = clamp(durationMilliseconds, range)
        let raw = Double(defaultDuration) / Double(max(1, clamped))
        let rounded = (raw * 10).rounded() / 10
        return clampedTransitionSpeed(rounded)
    }
    public static let framesPerSecondRange = 5...30
    public static let minimumFrameDelay: Double = 1.0 / 30.0
    public static let maximumFrameDelay: Double = 2.0
    public static let playbackSpeedRange: ClosedRange<Double> = 0.1...2.0
    public static let defaultPlaybackSpeed: Double = 1.0

    public static func clampedSpeed(_ value: Double) -> Double {
        SecurityPolicy.bounded(value, playbackSpeedRange, fallback: defaultPlaybackSpeed)
    }

    /// Maps a speed in `0.1...2.0` to `-1.0...1.0` with `1.0×` at exact center `0.0`.
    public static func speedSliderPosition(for speed: Double) -> Double {
        let clamped = clampedSpeed(speed)
        if clamped <= defaultPlaybackSpeed {
            return (clamped - defaultPlaybackSpeed) / (defaultPlaybackSpeed - playbackSpeedRange.lowerBound)
        } else {
            return (clamped - defaultPlaybackSpeed) / (playbackSpeedRange.upperBound - defaultPlaybackSpeed)
        }
    }

    /// Maps a normalized slider position in `-1.0...1.0` back to a `0.1`-snapped speed in `0.1...2.0`.
    public static func speedFromSliderPosition(_ position: Double) -> Double {
        let pos = SecurityPolicy.bounded(position, -1.0...1.0, fallback: 0.0)
        let raw: Double
        if pos <= 0 {
            raw = defaultPlaybackSpeed + pos * (defaultPlaybackSpeed - playbackSpeedRange.lowerBound)
        } else {
            raw = defaultPlaybackSpeed + pos * (playbackSpeedRange.upperBound - defaultPlaybackSpeed)
        }
        let snapped = (raw * 10.0).rounded() / 10.0
        return clampedSpeed(snapped)
    }

    public static func adjustedFrameDelay(_ baseDelay: Double, speed: Double) -> Double {
        let safeBase = SecurityPolicy.bounded(baseDelay, minimumFrameDelay...maximumFrameDelay, fallback: 0.1)
        let safeSpeed = clampedSpeed(speed)
        return SecurityPolicy.bounded(safeBase / safeSpeed, 0.012...5.0, fallback: 0.1)
    }

    public static let imageExtensions: Set<String> = ["gif", "png", "jpg", "jpeg", "webp", "apng", "heic", "heif"]
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    public static func clampedGrid(columns: Int, rows: Int) -> (columns: Int, rows: Int) {
        (min(max(columns, columnRange.lowerBound), columnRange.upperBound),
         min(max(rows, rowRange.lowerBound), rowRange.upperBound))
    }

    public static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    public static func normalizedExtension(_ raw: String) -> String? {
        let ext = raw.lowercased()
        guard imageExtensions.contains(ext) || videoExtensions.contains(ext) else { return nil }
        return ext
    }

    public static func byteLimit(forExtension ext: String) -> Int {
        videoExtensions.contains(ext.lowercased()) ? maxVideoBytes : maxImageBytes
    }
}

/// Character ramps. Every style deliberately avoids solid block glyphs (`█▓▒░`).
public enum ASCIIRenderStyle: String, Codable, CaseIterable, Identifiable {
    case filigree
    case ultraFine
    case classicDense
    case unicodeStrokes

    public var id: String { rawValue }

    public var ramp: [Character] {
        switch self {
        case .filigree:
            return Array(" .'`^,:;~-_!i/\\|()<>+*=xrnvczoae#%&@")
        case .ultraFine:
            return Array(" .'`,-:;~!/\\|+*=^v()[]{}#@")
        case .classicDense:
            return Array(" .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$")
        case .unicodeStrokes:
            return Array(" ·∙∘°+×*✧✦")
        }
    }

    /// Contour glyphs: vertical edge, horizontal edge, rising diagonal, falling diagonal.
    public var edgeGlyphs: (vertical: Character, horizontal: Character, rising: Character, falling: Character) {
        switch self {
        case .unicodeStrokes:
            return ("│", "─", "╱", "╲")
        default:
            return ("|", "-", "/", "\\")
        }
    }
}

public enum ASCIIColorPreset: String, Codable, CaseIterable, Identifiable {
    case original
    case phosphor
    case amber
    case moonlit
    case bloodMoon

    public var id: String { rawValue }

    /// Grades a linear 0...1 RGB sample into an 8-bit foreground color.
    public func grade(red: Float, green: Float, blue: Float, luminance: Float) -> (UInt8, UInt8, UInt8) {
        func byte(_ value: Float) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
        let level = 0.35 + 0.65 * max(0, min(1, luminance))
        switch self {
        case .original:
            let peak = max(red, green, blue)
            let gain = peak > 0.001 ? min(1.5, 1 / peak) : 1
            return (byte(red * gain), byte(green * gain), byte(blue * gain))
        case .phosphor:
            return (byte(0.25 * level), byte(1.0 * level), byte(0.45 * level))
        case .amber:
            return (byte(1.0 * level), byte(0.69 * level), byte(0.25 * level))
        case .moonlit:
            return (byte(0.55 * level), byte(0.85 * level), byte(1.0 * level))
        case .bloodMoon:
            return (byte(1.0 * level), byte(0.18 * level), byte(0.15 * level))
        }
    }
}

public enum ASCIIFitMode: String, Codable, CaseIterable, Identifiable {
    case contain
    case cover
    public var id: String { rawValue }
}

public enum TerminalWakeAnimation: String, Codable, CaseIterable, Identifiable {
    case random
    case swarm
    case decode
    case morph
    case shatter
    case rain
    case ripple
    case dissolve
    case curtain
    case cascade
    case glitch
    case iris
    case instant
    public var id: String { rawValue }

    public static let randomPool: [TerminalWakeAnimation] = [
        .glitch, .swarm, .decode, .morph, .shatter, .rain, .ripple, .cascade, .dissolve
    ]

    public func resolved(seed: Int) -> TerminalWakeAnimation {
        guard self == .random else { return self }
        let noise = TerminalSaverNoise.value(seed, 977, 1)
        let idx = min(Self.randomPool.count - 1, max(0, Int(noise * Double(Self.randomPool.count))))
        return Self.randomPool[idx]
    }
}

public enum TerminalTransitionDirection: Equatable {
    case forward
    case backward
}

public enum TerminalTransitionAnimation: String, Codable, CaseIterable, Identifiable {
    case random
    case swarm
    case decode
    case morph
    case shatter
    case rain
    case ripple
    case slide
    case dissolve
    case wipe
    case glitch
    case instant
    public var id: String { rawValue }

    public static let randomPool: [TerminalTransitionAnimation] = [
        .glitch, .swarm, .decode, .morph, .shatter, .rain, .ripple
    ]

    public func resolved(seed: Int) -> TerminalTransitionAnimation {
        guard self == .random else { return self }
        let noise = TerminalSaverNoise.value(seed, 911, 1)
        let idx = min(Self.randomPool.count - 1, max(0, Int(noise * Double(Self.randomPool.count))))
        return Self.randomPool[idx]
    }
}

public enum TerminalSaverKey: Codable, Equatable, Hashable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case pageUp
    case pageDown
    case tab
    case shiftTab
    case space
    case character(String)

    public static func sanitized(_ key: TerminalSaverKey, fallback: TerminalSaverKey) -> TerminalSaverKey {
        guard case .character(let raw) = key else { return key }
        let scalars = Array(raw.unicodeScalars)
        guard scalars.count == 1, let scalar = scalars.first,
              scalar.value >= 0x21, scalar.value <= 0x7E else {
            return fallback
        }
        return .character(String(scalar).lowercased())
    }

    public var displayLabel: String {
        switch self {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .pageUp: return "⇞"
        case .pageDown: return "⇟"
        case .tab: return "⇥"
        case .shiftTab: return "⇧⇥"
        case .space: return "␣"
        case .character(let value): return value.uppercased()
        }
    }
}

public enum TerminalSaverBuiltInScene: String, Codable, CaseIterable, Identifiable {
    case bonfire
    case bouncingDVD
    case starfield
    case windMeadow
    case matrix
    case gameOfLife
    case pipes
    case spinningDonut
    public var id: String { rawValue }

    public var supportsRenderStyle: Bool { self == .spinningDonut }

    public init?(identifier: String) {
        if identifier == "moonlitRain" {
            self = .bouncingDVD
        } else {
            self.init(rawValue: identifier)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let identifier = try container.decode(String.self)
        guard let scene = Self(identifier: identifier) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown built-in scene")
        }
        self = scene
    }
}

public struct TerminalSaverSceneSettings: Codable, Equatable {
    public var playbackSpeed: Double
    public var colorPreset: ASCIIColorPreset
    public var style: ASCIIRenderStyle?

    public init(
        playbackSpeed: Double = TerminalSaverPolicy.defaultPlaybackSpeed,
        colorPreset: ASCIIColorPreset = .original,
        style: ASCIIRenderStyle? = nil
    ) {
        self.playbackSpeed = playbackSpeed
        self.colorPreset = colorPreset
        self.style = style
    }

    public func animationTime(_ time: Double, advancingBy elapsed: Double) -> Double {
        time + elapsed * TerminalSaverPolicy.clampedSpeed(playbackSpeed)
    }
}

public enum TerminalSaverMediaKind: String, Codable {
    case image
    case video
}

public enum TerminalSaverSource: Codable, Equatable, Hashable {
    case builtIn(TerminalSaverBuiltInScene)
    case media(UUID)
}

public enum TerminalSaverAutoAdvanceMode: String, Codable {
    case off
    case time

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawMode = try container.decode(String.self)
        if rawMode == "repetitions" {
            self = .time
        } else if let mode = Self(rawValue: rawMode) {
            self = mode
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown automatic advancement mode.")
        }
    }
}

public enum TerminalSaverAutoAdvanceCutoff: String, Codable, CaseIterable, Identifiable {
    case finishLoop
    case hardCut
    public var id: String { rawValue }
}

public struct TerminalSaverAutoAdvanceSettings: Codable, Equatable {
    public var mode: TerminalSaverAutoAdvanceMode
    public var durationSeconds: Int
    public var cutoff: TerminalSaverAutoAdvanceCutoff

    public init(
        mode: TerminalSaverAutoAdvanceMode = .off,
        durationSeconds: Int = 30,
        cutoff: TerminalSaverAutoAdvanceCutoff = .finishLoop
    ) {
        self.mode = mode
        self.durationSeconds = durationSeconds
        self.cutoff = cutoff
    }

    private enum CodingKeys: String, CodingKey {
        case mode, durationSeconds, cutoff
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(TerminalSaverAutoAdvanceMode.self, forKey: .mode)) ?? .off
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 30
        cutoff = (try? c.decodeIfPresent(TerminalSaverAutoAdvanceCutoff.self, forKey: .cutoff)) ?? .finishLoop
    }

    func sanitized() -> Self {
        Self(
            mode: mode,
            durationSeconds: TerminalSaverPolicy.clamp(durationSeconds, TerminalSaverPolicy.autoAdvanceDurationRange),
            cutoff: cutoff
        )
    }

    public var timeLimit: TimeInterval? {
        mode == .time ? TimeInterval(durationSeconds) : nil
    }

    public var waitsForMediaLoop: Bool {
        cutoff == .finishLoop
    }

    public func shouldAdvance(timeElapsed: Bool, hasMediaLoop: Bool, finishedMediaCycle: Bool) -> Bool {
        guard mode == .time, timeElapsed else { return false }
        if !hasMediaLoop || cutoff == .hardCut {
            return true
        }
        return finishedMediaCycle
    }
}

public struct TerminalSaverMediaCursor {
    public private(set) var frameIndex = 0
    private var isReversing = false

    public init() {}

    /// Reverses without displaying each turning frame twice and reports a completed playback cycle.
    @discardableResult
    public mutating func advance(frameCount: Int, pingPong: Bool) -> Bool {
        guard frameCount > 1, frameIndex < frameCount else {
            self = Self()
            return false
        }

        if !pingPong {
            isReversing = false
            frameIndex = (frameIndex + 1) % frameCount
            return frameIndex == 0
        }

        if frameIndex == 0 {
            isReversing = false
        } else if frameIndex == frameCount - 1 {
            isReversing = true
        }
        frameIndex += isReversing ? -1 : 1
        return frameIndex == 0
    }
}

public struct TerminalSaverMediaItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var displayName: String
    public let fileExtension: String
    public let byteCount: Int
    public let addedAt: Date
    public var style: ASCIIRenderStyle
    public var colorPreset: ASCIIColorPreset
    public var fitMode: ASCIIFitMode
    public var playbackSpeed: Double
    public var removeBackground: Bool
    public var pingPongLoop: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        fileExtension: String,
        byteCount: Int,
        addedAt: Date = Date(),
        style: ASCIIRenderStyle = .filigree,
        colorPreset: ASCIIColorPreset = .original,
        fitMode: ASCIIFitMode = .cover,
        playbackSpeed: Double = TerminalSaverPolicy.defaultPlaybackSpeed,
        removeBackground: Bool = false,
        pingPongLoop: Bool = false
    ) {
        self.id = id
        self.displayName = Self.sanitizedDisplayName(displayName)
        self.fileExtension = fileExtension.lowercased()
        self.byteCount = byteCount
        self.addedAt = addedAt
        self.style = style
        self.colorPreset = colorPreset
        self.fitMode = fitMode
        self.playbackSpeed = playbackSpeed
        self.removeBackground = removeBackground
        self.pingPongLoop = pingPongLoop
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, fileExtension, byteCount, addedAt, style, colorPreset, fitMode, playbackSpeed, removeBackground, pingPongLoop
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        fileExtension = try c.decode(String.self, forKey: .fileExtension)
        byteCount = try c.decode(Int.self, forKey: .byteCount)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        style = (try? c.decodeIfPresent(ASCIIRenderStyle.self, forKey: .style)) ?? .filigree
        colorPreset = (try? c.decodeIfPresent(ASCIIColorPreset.self, forKey: .colorPreset)) ?? .original
        fitMode = (try? c.decodeIfPresent(ASCIIFitMode.self, forKey: .fitMode)) ?? .cover
        playbackSpeed = try c.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? TerminalSaverPolicy.defaultPlaybackSpeed
        removeBackground = try c.decodeIfPresent(Bool.self, forKey: .removeBackground) ?? false
        pingPongLoop = try c.decodeIfPresent(Bool.self, forKey: .pingPongLoop) ?? false
    }

    public var kind: TerminalSaverMediaKind {
        TerminalSaverPolicy.videoExtensions.contains(fileExtension) ? .video : .image
    }

    public var supportsAnimation: Bool {
        kind == .video || fileExtension == "gif" || fileExtension == "webp" || fileExtension == "apng"
    }

    /// Stored file names are derived only from the UUID and an allow-listed extension.
    public var storedFileName: String { "\(id.uuidString).\(fileExtension)" }

    /// Cached APNG cutout stored alongside the original media.
    public var cutoutCacheFileName: String { "cutout-\(id.uuidString).png" }

    public var isValid: Bool {
        guard TerminalSaverPolicy.normalizedExtension(fileExtension) == fileExtension else { return false }
        return byteCount > 0 && byteCount <= TerminalSaverPolicy.byteLimit(forExtension: fileExtension)
    }

    public static func sanitizedDisplayName(_ raw: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(.newlines).union(.illegalCharacters)
        let scalars = raw.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        let collapsed = scalars.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        let trimmed = String(collapsed.prefix(TerminalSaverPolicy.maxDisplayNameLength))
        return trimmed.isEmpty ? "Media" : trimmed
    }
}

public struct TerminalSaverConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var idleTimeoutSeconds: Int
    public var edgeDetail: Double
    public var darkFloor: Double
    public var gamma: Double
    public var framesPerSecond: Int
    public var startAnimation: TerminalWakeAnimation
    public var startDurationMilliseconds: Int
    public var wakeAnimation: TerminalWakeAnimation
    public var wakeDurationMilliseconds: Int
    public var transitionAnimation: TerminalTransitionAnimation
    public var transitionDurationMilliseconds: Int
    public var previousKey: TerminalSaverKey
    public var nextKey: TerminalSaverKey
    public var autoAdvance: TerminalSaverAutoAdvanceSettings
    public var selectedSource: TerminalSaverSource
    public var selectedSources: [TerminalSaverSource]
    public var mediaItems: [TerminalSaverMediaItem]
    private var sceneSettings: [TerminalSaverBuiltInScene: TerminalSaverSceneSettings]

    public subscript(settingsFor scene: TerminalSaverBuiltInScene) -> TerminalSaverSceneSettings {
        get { sceneSettings[scene] ?? TerminalSaverSceneSettings() }
        set { sceneSettings[scene] = newValue }
    }

    public init(
        isEnabled: Bool = false,
        idleTimeoutSeconds: Int = TerminalSaverPolicy.defaultIdleTimeout,
        edgeDetail: Double = 0.55,
        darkFloor: Double = 0.08,
        gamma: Double = 1.15,
        framesPerSecond: Int = 15,
        startAnimation: TerminalWakeAnimation = .dissolve,
        startDurationMilliseconds: Int = TerminalSaverPolicy.defaultStartDuration,
        wakeAnimation: TerminalWakeAnimation = .dissolve,
        wakeDurationMilliseconds: Int = TerminalSaverPolicy.defaultWakeDuration,
        transitionAnimation: TerminalTransitionAnimation = .slide,
        transitionDurationMilliseconds: Int = TerminalSaverPolicy.defaultTransitionDuration,
        previousKey: TerminalSaverKey = .leftArrow,
        nextKey: TerminalSaverKey = .rightArrow,
        autoAdvance: TerminalSaverAutoAdvanceSettings = TerminalSaverAutoAdvanceSettings(),
        selectedSource: TerminalSaverSource = .builtIn(.bonfire),
        selectedSources: [TerminalSaverSource]? = nil,
        mediaItems: [TerminalSaverMediaItem] = []
    ) {
        self.isEnabled = isEnabled
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.edgeDetail = edgeDetail
        self.darkFloor = darkFloor
        self.gamma = gamma
        self.framesPerSecond = framesPerSecond
        self.startAnimation = startAnimation
        self.startDurationMilliseconds = startDurationMilliseconds
        self.wakeAnimation = wakeAnimation
        self.wakeDurationMilliseconds = wakeDurationMilliseconds
        self.transitionAnimation = transitionAnimation
        self.transitionDurationMilliseconds = transitionDurationMilliseconds
        self.previousKey = previousKey
        self.nextKey = nextKey
        self.autoAdvance = autoAdvance
        self.selectedSource = selectedSource
        self.selectedSources = selectedSources ?? [selectedSource]
        self.mediaItems = mediaItems
        self.sceneSettings = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, idleTimeoutSeconds, edgeDetail, darkFloor, gamma
        case framesPerSecond, startAnimation, startDurationMilliseconds, wakeAnimation, wakeDurationMilliseconds
        case transitionAnimation, transitionDurationMilliseconds, previousKey, nextKey, selectedSource
        case selectedSources, mediaItems, sceneSettings, autoAdvance
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case shufflePool, playbackMode, style, colorPreset, fitMode
    }

    private struct RawMediaItem: Decodable {
        let id: UUID
        let displayName: String
        let fileExtension: String
        let byteCount: Int
        let addedAt: Date
        let style: ASCIIRenderStyle?
        let colorPreset: ASCIIColorPreset?
        let fitMode: ASCIIFitMode?
        let playbackSpeed: Double?
        let removeBackground: Bool?
        let pingPongLoop: Bool?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let d = TerminalSaverConfig()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        idleTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .idleTimeoutSeconds) ?? d.idleTimeoutSeconds
        edgeDetail = try c.decodeIfPresent(Double.self, forKey: .edgeDetail) ?? d.edgeDetail
        darkFloor = try c.decodeIfPresent(Double.self, forKey: .darkFloor) ?? d.darkFloor
        gamma = try c.decodeIfPresent(Double.self, forKey: .gamma) ?? d.gamma
        framesPerSecond = try c.decodeIfPresent(Int.self, forKey: .framesPerSecond) ?? d.framesPerSecond
        startAnimation = (try? c.decodeIfPresent(TerminalWakeAnimation.self, forKey: .startAnimation)) ?? d.startAnimation
        startDurationMilliseconds = try c.decodeIfPresent(Int.self, forKey: .startDurationMilliseconds) ?? d.startDurationMilliseconds
        wakeAnimation = (try? c.decodeIfPresent(TerminalWakeAnimation.self, forKey: .wakeAnimation)) ?? d.wakeAnimation
        wakeDurationMilliseconds = try c.decodeIfPresent(Int.self, forKey: .wakeDurationMilliseconds) ?? d.wakeDurationMilliseconds
        transitionAnimation = (try? c.decodeIfPresent(TerminalTransitionAnimation.self, forKey: .transitionAnimation)) ?? d.transitionAnimation
        transitionDurationMilliseconds = try c.decodeIfPresent(Int.self, forKey: .transitionDurationMilliseconds) ?? d.transitionDurationMilliseconds
        previousKey = (try? c.decodeIfPresent(TerminalSaverKey.self, forKey: .previousKey)) ?? d.previousKey
        nextKey = (try? c.decodeIfPresent(TerminalSaverKey.self, forKey: .nextKey)) ?? d.nextKey
        autoAdvance = try c.decodeIfPresent(TerminalSaverAutoAdvanceSettings.self, forKey: .autoAdvance) ?? d.autoAdvance
        selectedSource = (try? c.decodeIfPresent(TerminalSaverSource.self, forKey: .selectedSource)) ?? d.selectedSource
        sceneSettings = try c.decodeIfPresent(
            [TerminalSaverBuiltInScene: TerminalSaverSceneSettings].self, forKey: .sceneSettings
        ) ?? [:]

        let legacyStyle = (try? legacy.decodeIfPresent(ASCIIRenderStyle.self, forKey: .style)) ?? .filigree
        let legacyColor = (try? legacy.decodeIfPresent(ASCIIColorPreset.self, forKey: .colorPreset)) ?? .original
        let legacyFit = (try? legacy.decodeIfPresent(ASCIIFitMode.self, forKey: .fitMode)) ?? .cover

        let rawItems = try c.decodeIfPresent([RawMediaItem].self, forKey: .mediaItems) ?? []
        let decodedItems = rawItems.map { raw in
            TerminalSaverMediaItem(
                id: raw.id,
                displayName: raw.displayName,
                fileExtension: raw.fileExtension,
                byteCount: raw.byteCount,
                addedAt: raw.addedAt,
                style: raw.style ?? legacyStyle,
                colorPreset: raw.colorPreset ?? legacyColor,
                fitMode: raw.fitMode ?? legacyFit,
                playbackSpeed: raw.playbackSpeed ?? TerminalSaverPolicy.defaultPlaybackSpeed,
                removeBackground: raw.removeBackground ?? false,
                pingPongLoop: raw.pingPongLoop ?? false
            )
        }
        mediaItems = decodedItems
        if let decodedSources = try? c.decodeIfPresent([TerminalSaverSource].self, forKey: .selectedSources) {
            selectedSources = decodedSources
        } else if let legacyPool = try? legacy.decodeIfPresent([TerminalSaverSource].self, forKey: .shufflePool) {
            selectedSources = legacyPool
        } else if (try? legacy.decodeIfPresent(String.self, forKey: .playbackMode)) == "shuffle" {
            let fallbackAll = TerminalSaverBuiltInScene.allCases.map { TerminalSaverSource.builtIn($0) }
                + decodedItems.map { TerminalSaverSource.media($0.id) }
            selectedSources = fallbackAll
        } else {
            selectedSources = [selectedSource]
        }
    }

    public func mediaItem(for source: TerminalSaverSource) -> TerminalSaverMediaItem? {
        guard case .media(let id) = source else { return nil }
        return mediaItems.first(where: { $0.id == id })
    }

    /// Returns a copy with every value clamped and invalid or duplicate media removed.
    public func sanitized() -> TerminalSaverConfig {
        var copy = self
        copy.idleTimeoutSeconds = TerminalSaverPolicy.clamp(idleTimeoutSeconds, TerminalSaverPolicy.idleTimeoutRange)
        copy.startDurationMilliseconds = TerminalSaverPolicy.clamp(startDurationMilliseconds, TerminalSaverPolicy.startDurationRange)
        copy.wakeDurationMilliseconds = TerminalSaverPolicy.clamp(wakeDurationMilliseconds, TerminalSaverPolicy.wakeDurationRange)
        copy.transitionDurationMilliseconds = TerminalSaverPolicy.clamp(transitionDurationMilliseconds, TerminalSaverPolicy.transitionDurationRange)
        copy.autoAdvance = autoAdvance.sanitized()
        copy.previousKey = TerminalSaverKey.sanitized(previousKey, fallback: .leftArrow)
        copy.nextKey = TerminalSaverKey.sanitized(nextKey, fallback: .rightArrow)
        if copy.previousKey == copy.nextKey {
            copy.nextKey = (copy.previousKey == .rightArrow) ? .leftArrow : .rightArrow
        }
        copy.framesPerSecond = TerminalSaverPolicy.clamp(framesPerSecond, TerminalSaverPolicy.framesPerSecondRange)
        copy.edgeDetail = SecurityPolicy.bounded(edgeDetail, 0...1, fallback: 0.55)
        copy.darkFloor = SecurityPolicy.bounded(darkFloor, 0...0.65, fallback: 0.08)
        copy.gamma = SecurityPolicy.bounded(gamma, 0.6...3.5, fallback: 1.15)

        var seen = Set<UUID>()
        var items: [TerminalSaverMediaItem] = []
        for var item in mediaItems where item.isValid && seen.insert(item.id).inserted {
            item.displayName = TerminalSaverMediaItem.sanitizedDisplayName(item.displayName)
            item.playbackSpeed = SecurityPolicy.bounded(
                item.playbackSpeed,
                TerminalSaverPolicy.playbackSpeedRange,
                fallback: TerminalSaverPolicy.defaultPlaybackSpeed
            )
            if !item.supportsAnimation { item.pingPongLoop = false }
            items.append(item)
            if items.count == TerminalSaverPolicy.maxLibraryItems { break }
        }
        copy.mediaItems = items

        for (scene, var settings) in sceneSettings {
            settings.playbackSpeed = TerminalSaverPolicy.clampedSpeed(settings.playbackSpeed)
            if !scene.supportsRenderStyle { settings.style = nil }
            copy.sceneSettings[scene] = settings == TerminalSaverSceneSettings() ? nil : settings
        }

        if case .media(let id) = copy.selectedSource, !items.contains(where: { $0.id == id }) {
            copy.selectedSource = .builtIn(.bonfire)
        }
        let cleanSources = copy.effectiveSelectedSources
        copy.selectedSources = cleanSources
        if !cleanSources.contains(copy.selectedSource), let first = cleanSources.first {
            copy.selectedSource = first
        }
        return copy
    }

    /// Deduplicated valid sources selected for playback/rotation, guaranteed non-empty.
    public var effectiveSelectedSources: [TerminalSaverSource] {
        let validMediaIDs = Set(mediaItems.map(\.id))
        var seen = Set<TerminalSaverSource>()
        var result: [TerminalSaverSource] = []
        for source in selectedSources {
            if case .media(let id) = source, !validMediaIDs.contains(id) {
                continue
            }
            if seen.insert(source).inserted {
                result.append(source)
            }
        }
        if !result.isEmpty {
            return result
        }
        if case .media(let id) = selectedSource, !validMediaIDs.contains(id) {
            return [.builtIn(.bonfire)]
        }
        return [selectedSource]
    }

    /// True automatically whenever more than one scene or media item is selected.
    public var isShuffleActive: Bool {
        effectiveSelectedSources.count > 1
    }

    /// All playable sources: built-in scenes followed by imported media.
    public var allSources: [TerminalSaverSource] {
        TerminalSaverBuiltInScene.allCases.map { .builtIn($0) } + mediaItems.map { .media($0.id) }
    }

    public var startAnimationSpeed: Double {
        get {
            TerminalSaverPolicy.transitionSpeed(
                durationMilliseconds: startDurationMilliseconds,
                defaultDuration: TerminalSaverPolicy.defaultStartDuration,
                range: TerminalSaverPolicy.startDurationRange
            )
        }
        set {
            startDurationMilliseconds = TerminalSaverPolicy.transitionDurationMilliseconds(
                defaultDuration: TerminalSaverPolicy.defaultStartDuration,
                range: TerminalSaverPolicy.startDurationRange,
                speed: newValue
            )
        }
    }

    public var wakeAnimationSpeed: Double {
        get {
            TerminalSaverPolicy.transitionSpeed(
                durationMilliseconds: wakeDurationMilliseconds,
                defaultDuration: TerminalSaverPolicy.defaultWakeDuration,
                range: TerminalSaverPolicy.wakeDurationRange
            )
        }
        set {
            wakeDurationMilliseconds = TerminalSaverPolicy.transitionDurationMilliseconds(
                defaultDuration: TerminalSaverPolicy.defaultWakeDuration,
                range: TerminalSaverPolicy.wakeDurationRange,
                speed: newValue
            )
        }
    }

    public var transitionAnimationSpeed: Double {
        get {
            TerminalSaverPolicy.transitionSpeed(
                durationMilliseconds: transitionDurationMilliseconds,
                defaultDuration: TerminalSaverPolicy.defaultTransitionDuration,
                range: TerminalSaverPolicy.transitionDurationRange
            )
        }
        set {
            transitionDurationMilliseconds = TerminalSaverPolicy.transitionDurationMilliseconds(
                defaultDuration: TerminalSaverPolicy.defaultTransitionDuration,
                range: TerminalSaverPolicy.transitionDurationRange,
                speed: newValue
            )
        }
    }
}

/// Stores a complete cycle and the unplayed suffix for the next activation.
public struct TerminalSaverRotationState: Codable, Equatable {
    public var pool: [TerminalSaverSource]
    public var remaining: [TerminalSaverSource]
    public var lastDelivered: TerminalSaverSource?
    public var order: [TerminalSaverSource]

    private enum CodingKeys: String, CodingKey {
        case pool, remaining, lastDelivered, order
    }

    public init(
        pool: [TerminalSaverSource] = [],
        remaining: [TerminalSaverSource] = [],
        lastDelivered: TerminalSaverSource? = nil,
        order: [TerminalSaverSource] = []
    ) {
        self.pool = pool
        self.remaining = remaining
        self.lastDelivered = lastDelivered
        self.order = order
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pool = try container.decodeIfPresent([TerminalSaverSource].self, forKey: .pool) ?? []
        remaining = try container.decodeIfPresent([TerminalSaverSource].self, forKey: .remaining) ?? []
        lastDelivered = try container.decodeIfPresent(TerminalSaverSource.self, forKey: .lastDelivered)
        order = try container.decodeIfPresent([TerminalSaverSource].self, forKey: .order) ?? []
    }
}

/// Plays a single shuffled cycle repeatedly, with a cursor shared by both navigation directions.
public struct TerminalSaverRotationQueue {
    private let pool: [TerminalSaverSource]
    private var order: [TerminalSaverSource] = []
    private var nextIndex = 0
    private var lastDelivered: TerminalSaverSource?

    public init(pool: [TerminalSaverSource], state: TerminalSaverRotationState? = nil) {
        var seen = Set<TerminalSaverSource>()
        let unique = pool.filter { seen.insert($0).inserted }
        self.pool = unique.isEmpty ? [.builtIn(.bonfire)] : unique
        guard let state else { return }

        let selected = Set(self.pool)
        if let last = state.lastDelivered, selected.contains(last) {
            lastDelivered = last
        }
        let previousPool = Set(state.pool)
        guard selected.isSubset(of: previousPool) else { return }

        if state.order.isEmpty {
            // Older saves only retained the unplayed suffix. Preserve that part of the old cycle.
            var seen = Set<TerminalSaverSource>()
            let suffix = state.remaining.filter { selected.contains($0) && seen.insert($0).inserted }
            guard !suffix.isEmpty else { return }
            var prefix = self.pool.filter { !seen.contains($0) && $0 != lastDelivered }
            if let lastDelivered, !seen.contains(lastDelivered) { prefix.append(lastDelivered) }
            order = prefix + suffix
            nextIndex = prefix.count
        } else {
            guard state.order.count == previousPool.count, Set(state.order) == previousPool,
                  state.remaining.count <= state.order.count,
                  state.order.suffix(state.remaining.count).elementsEqual(state.remaining) else { return }
            order = state.order.filter { selected.contains($0) }
            let unplayedCount = state.remaining.filter { selected.contains($0) }.count
            nextIndex = unplayedCount == 0 ? 0 : order.count - unplayedCount
        }

        if order.count > 1, order[nextIndex] == lastDelivered {
            advanceCursor()
        }
    }

    public var poolCount: Int { pool.count }

    public var state: TerminalSaverRotationState {
        TerminalSaverRotationState(
            pool: pool,
            remaining: Array(order[nextIndex...]),
            lastDelivered: lastDelivered,
            order: order
        )
    }

    public mutating func reshuffle() {
        var generator = SystemRandomNumberGenerator()
        reshuffle(using: &generator)
    }

    public mutating func reshuffle<G: RandomNumberGenerator>(using generator: inout G) {
        order = pool.shuffled(using: &generator)
        if order.count > 1, let lastDelivered, order.first == lastDelivered {
            let swapIndex = Int.random(in: 1..<order.count, using: &generator)
            order.swapAt(0, swapIndex)
        }
        nextIndex = 0
    }

    public mutating func next() -> TerminalSaverSource {
        var generator = SystemRandomNumberGenerator()
        return next(using: &generator)
    }

    public mutating func next<G: RandomNumberGenerator>(using generator: inout G) -> TerminalSaverSource {
        if order.isEmpty { reshuffle(using: &generator) }
        let picked = order[nextIndex]
        lastDelivered = picked
        advanceCursor()
        return picked
    }

    fileprivate mutating func select<G: RandomNumberGenerator>(_ source: TerminalSaverSource, using generator: inout G) {
        if order.isEmpty { reshuffle(using: &generator) }
        guard let index = order.firstIndex(of: source) else { return }
        lastDelivered = source
        nextIndex = index
        advanceCursor()
    }

    fileprivate mutating func previous(before source: TerminalSaverSource) -> TerminalSaverSource {
        let index = order.firstIndex(of: source) ?? nextIndex
        let previous = order[(index + order.count - 1) % order.count]
        lastDelivered = previous
        nextIndex = index
        return previous
    }

    private mutating func advanceCursor() {
        nextIndex = (nextIndex + 1) % order.count
    }
}

public enum TerminalSaverInputAction: Equatable {
    case none
    case next
    case previous
    case wake
}

public struct TerminalSaverInputParseResult: Equatable {
    public let action: TerminalSaverInputAction
    public let receivedDSRAck: Bool

    public init(action: TerminalSaverInputAction, receivedDSRAck: Bool) {
        self.action = action
        self.receivedDSRAck = receivedDSRAck
    }
}

/// Classifies raw terminal stdin byte sequences into navigation, DSR ack, or wake actions without mutating state.
public enum TerminalSaverInputParser {
    private enum ParsedToken {
        case key(TerminalSaverKey)
        case dsrAck
        case ignored
        case incomplete
        case unknown
    }

    /// Collects an available input batch. A terminal may deliver an escape sequence in several reads.
    public static func readAction(
        from descriptor: Int32,
        previousKey: TerminalSaverKey,
        nextKey: TerminalSaverKey
    ) -> TerminalSaverInputAction {
        let deadline = ProcessInfo.processInfo.systemUptime + TerminalSaverPolicy.inputSequenceTimeout
        let limit = TerminalSaverPolicy.maxInputBytes
        var bytes: [UInt8] = []
        bytes.reserveCapacity(limit)
        var buffer = [UInt8](repeating: 0, count: limit)
        var input = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        var timeout: Int32 = 0

        repeat {
            let ready = Darwin.poll(&input, 1, timeout)
            if ready > 0, (input.revents & Int16(POLLIN)) != 0 {
                let count = Darwin.read(descriptor, &buffer, limit - bytes.count)
                if count > 0 {
                    bytes.append(contentsOf: buffer.prefix(count))
                    guard bytes.count < limit, needsMoreBytes(bytes) else { break }
                } else if count == 0 || errno != EINTR {
                    break
                }
            } else if ready >= 0 || errno != EINTR {
                break
            }

            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            timeout = Int32((remaining * 1000).rounded(.up))
        } while true

        return classify(bytes: bytes, previousKey: previousKey, nextKey: nextKey)
    }

    public static func needsMoreBytes(_ bytes: [UInt8]) -> Bool {
        var idx = 0
        while idx < bytes.count {
            if case .incomplete = parseNextToken(in: bytes, index: &idx) {
                return true
            }
        }
        return false
    }

    public static func parse(
        bytes: [UInt8],
        previousKey: TerminalSaverKey,
        nextKey: TerminalSaverKey
    ) -> TerminalSaverInputParseResult {
        guard !bytes.isEmpty else {
            return TerminalSaverInputParseResult(action: .none, receivedDSRAck: false)
        }
        let prev = TerminalSaverKey.sanitized(previousKey, fallback: .leftArrow)
        let next = TerminalSaverKey.sanitized(nextKey, fallback: .rightArrow)

        var idx = 0
        var action: TerminalSaverInputAction = .none
        var receivedDSRAck = false
        while idx < bytes.count {
            switch parseNextToken(in: bytes, index: &idx) {
            case .key(let parsed):
                guard action != .wake else { continue }
                if parsed == prev {
                    action = .previous
                } else if parsed == next {
                    action = .next
                } else {
                    action = .wake
                }
            case .dsrAck:
                receivedDSRAck = true
            case .ignored:
                continue
            case .incomplete, .unknown:
                action = .wake
            }
        }
        return TerminalSaverInputParseResult(action: action, receivedDSRAck: receivedDSRAck)
    }

    public static func classify(
        bytes: [UInt8],
        previousKey: TerminalSaverKey,
        nextKey: TerminalSaverKey
    ) -> TerminalSaverInputAction {
        parse(bytes: bytes, previousKey: previousKey, nextKey: nextKey).action
    }

    private static func parseNextToken(in bytes: [UInt8], index: inout Int) -> ParsedToken {
        let first = bytes[index]
        if first == 0x1B {
            guard index + 1 < bytes.count else {
                index = bytes.count
                return .incomplete
            }
            let second = bytes[index + 1]
            if second == 0x4F { // SS3: ESC O <final>
                guard index + 2 < bytes.count else {
                    index = bytes.count
                    return .incomplete
                }
                let finalByte = bytes[index + 2]
                index += 3
                if let arrow = arrowKey(for: finalByte) {
                    return .key(arrow)
                }
                return .unknown
            } else if second == 0x5B { // CSI: ESC [ <params...> <final>
                var j = index + 2
                var paramBytes: [UInt8] = []
                while j < bytes.count && paramBytes.count <= 10 {
                    let b = bytes[j]
                    if b >= 0x20 && b <= 0x3F {
                        if paramBytes.count == 10 {
                            index = j + 1
                            return .unknown
                        }
                        paramBytes.append(b)
                        j += 1
                    } else if b >= 0x40 && b <= 0x7E {
                        index = j + 1
                        if paramBytes.isEmpty {
                            if let arrow = arrowKey(for: b) {
                                return .key(arrow)
                            }
                            if b == 0x5A {
                                return .key(.shiftTab)
                            }
                            if b == 0x49 || b == 0x4F { // Focus in (ESC [ I) / Focus out (ESC [ O)
                                return .ignored
                            }
                        } else if b == 0x7E && paramBytes.count == 1 {
                            if paramBytes[0] == 0x35 { return .key(.pageUp) }
                            if paramBytes[0] == 0x36 { return .key(.pageDown) }
                        } else if b == 0x6E && paramBytes == [0x30] { // DSR OK reply (ESC [ 0 n)
                            return .dsrAck
                        }
                        return .unknown
                    } else {
                        index = j + 1
                        return .unknown
                    }
                }
                index = bytes.count
                return .incomplete
            } else {
                index += 2
                return .unknown
            }
        }

        index += 1
        switch first {
        case 0x09:
            return .key(.tab)
        case 0x20:
            return .key(.space)
        case 0x21...0x7E:
            let scalar = UnicodeScalar(first)
            return .key(.character(String(scalar).lowercased()))
        default:
            return .unknown
        }
    }

    private static func arrowKey(for byte: UInt8) -> TerminalSaverKey? {
        switch byte {
        case 0x41: return .upArrow
        case 0x42: return .downArrow
        case 0x43: return .rightArrow
        case 0x44: return .leftArrow
        default: return nil
        }
    }
}

/// Browses the same repeating order in either direction during a screensaver session.
public struct TerminalSaverSessionNavigator {
    private var queue: TerminalSaverRotationQueue
    public private(set) var current: TerminalSaverSource

    public init(
        pool: [TerminalSaverSource],
        state: TerminalSaverRotationState? = nil,
        initialSource: TerminalSaverSource? = nil
    ) {
        var generator = SystemRandomNumberGenerator()
        self.init(pool: pool, state: state, initialSource: initialSource, using: &generator)
    }

    public init<G: RandomNumberGenerator>(
        pool: [TerminalSaverSource],
        state: TerminalSaverRotationState? = nil,
        initialSource: TerminalSaverSource? = nil,
        using generator: inout G
    ) {
        var queue = TerminalSaverRotationQueue(pool: pool, state: state)
        if let initialSource {
            queue.select(initialSource, using: &generator)
            current = initialSource
        } else {
            current = queue.next(using: &generator)
        }
        self.queue = queue
    }

    public var state: TerminalSaverRotationState { queue.state }

    public mutating func stepForward() -> TerminalSaverSource? {
        guard queue.poolCount > 1 else { return nil }
        current = queue.next()
        return current
    }

    public mutating func stepBackward() -> TerminalSaverSource? {
        guard queue.poolCount > 1 else { return nil }
        current = queue.previous(before: current)
        return current
    }
}

/// Deterministic, allocation-free hash noise in `[0, 1)` used by scenes and wake animations.
public enum TerminalSaverNoise {
    @inline(__always)
    public static func value(_ x: Int, _ y: Int, _ z: Int = 0) -> Double {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= UInt64(bitPattern: Int64(z)) &* 0x1656_67B1_9E37_79F9
        h ^= h >> 33
        h = h &* 0xFF51_AFD7_ED55_8CCD
        h ^= h >> 33
        h = h &* 0xC4CE_B9FE_1A85_EC53
        h ^= h >> 33
        return Double(h >> 11) / Double(UInt64(1) << 53)
    }
}
