import Foundation
import AppKit
import Combine

/// Lightweight observable-free model holding the live ASCII preview frame so 15–30 fps
/// preview updates redraw only the preview NSView instead of triggering SwiftUI view-tree diffing.
public final class TerminalSaverPreviewModel {
    public private(set) var frame: ASCIIFrame
    public var onFrameChanged: ((ASCIIFrame) -> Void)?

    public init(frame: ASCIIFrame) {
        self.frame = frame
    }

    public func update(_ newFrame: ASCIIFrame) {
        guard newFrame != frame else { return }
        frame = newFrame
        onFrameChanged?(newFrame)
    }
}

/// Main-thread coordinator for TerminalSaver config, bounded media library, shell hooks, and fast live preview.
public final class TerminalSaverManager: ObservableObject {
    public static let shared = TerminalSaverManager(
        store: .shared,
        shellHomeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
    )

    public static let previewColumns = 70
    public static let previewRows = 20

    @Published public private(set) var config: TerminalSaverConfig
    @Published public private(set) var shellStatuses: [TerminalShellTarget: TerminalShellStatus] = [:]
    @Published public var lastError: String?
    @Published public private(set) var previewedSource: TerminalSaverSource
    @Published public private(set) var isDecodingPreview: Bool = false
    @Published public private(set) var processingCutoutMediaIDs: Set<UUID> = []

    public let previewModel: TerminalSaverPreviewModel
    public var previewFrame: ASCIIFrame { previewModel.frame }
    public private(set) var isPreviewPlayingStartAnimation: Bool = false
    public private(set) var isPreviewPlayingWakeAnimation: Bool = false
    public private(set) var isPreviewPlayingTransitionAnimation: Bool = false

    private let store: TerminalSaverMediaStore
    private let shellHomeDirectoryURL: URL
    private let configurationLoadError: String?
    private var persistedConfig: TerminalSaverConfig
    private var configurationWriteError: String?
    private let decodeQueue = DispatchQueue(label: "de.trst.yeoman.terminalsaver.decode", qos: .userInitiated)
    private var previewTimer: Timer?
    private var lastPreviewTickTime: CFAbsoluteTime = 0
    private var lastSteadyProceduralRenderTime: CFAbsoluteTime = 0
    private var proceduralPreviewTime: Double = 0
    private var mediaFrameAccumulator: Double = 0
    private var cachedPreviewFrames: [(grid: ASCIIPixelGrid, delaySeconds: Double)] = []
    private var cachedRenderedPreviewFrames: [ASCIIFrame?] = []
    private var cachedPreviewRenderSettings: ASCIIRenderSettings?
    private var cachedPreviewSource: TerminalSaverSource?
    private var cachedPreviewFitMode: ASCIIFitMode?
    private var cachedPreviewRemoveBackground: Bool?
    private var decodeGeneration: Int = 0
    private var previewMediaCursor = TerminalSaverMediaCursor()
    private var startPreviewStartedAt: CFAbsoluteTime = 0
    private var startPreviewSeed: Int = 0
    private var wakePreviewStartedAt: CFAbsoluteTime = 0
    private var wakePreviewBaseFrame: ASCIIFrame?
    private var wakePreviewSeed: Int = 0
    private var transitionPreviewStartedAt: CFAbsoluteTime = 0
    private var transitionPreviewFromFrame: ASCIIFrame?
    private var transitionPreviewSeed: Int = 0
    private var transitionPreviewDirection: TerminalTransitionDirection = .forward
    private var lastSyncedTimeout: Int
    private var pendingSaveWorkItem: DispatchWorkItem?

    public init(store: TerminalSaverMediaStore, shellHomeDirectoryURL: URL) {
        self.store = store
        self.shellHomeDirectoryURL = shellHomeDirectoryURL
        let result = Result { try store.loadConfig() }
        let loaded = (try? result.get()) ?? TerminalSaverConfig()
        if case .failure(let error) = result {
            configurationLoadError = error.localizedDescription
        } else {
            configurationLoadError = nil
        }
        self.config = loaded
        self.persistedConfig = loaded
        self.previewedSource = loaded.selectedSource
        self.lastSyncedTimeout = loaded.idleTimeoutSeconds
        let initialFrame: ASCIIFrame
        if case .builtIn(let scene) = loaded.selectedSource {
            initialFrame = TerminalSaverProceduralScenes.frame(
                scene: scene,
                columns: Self.previewColumns,
                rows: Self.previewRows,
                time: 0,
                settings: loaded[settingsFor: scene]
            )
        } else {
            initialFrame = ASCIIFrame(columns: Self.previewColumns, rows: Self.previewRows)
        }
        self.previewModel = TerminalSaverPreviewModel(frame: initialFrame)
        lastError = configurationLoadError
        refreshShellStatuses()
    }

    public var helperExecutablePath: String {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("YeomanTermSaver")
            .path
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        return "/Applications/Yeoman.app/Contents/Helpers/YeomanTermSaver"
    }

    public func setEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        guard canEditConfiguration, config.isEnabled != enabled else { return }
        config.isEnabled = enabled
        flushConfiguration()
    }

    public func updateConfig(_ mutate: (inout TerminalSaverConfig) -> Void) {
        precondition(Thread.isMainThread)
        guard canEditConfiguration else { return }
        let previousLoop = config.mediaItem(for: previewedSource)?.pingPongLoop
        var next = config
        mutate(&next)
        next = next.sanitized()
        guard next != config else { return }
        config = next
        scheduleDebouncedSave()

        let currentItem = next.mediaItem(for: previewedSource)
        let currentFitMode = currentItem?.fitMode
        let currentRemoveBG = currentItem?.removeBackground
        if previewedSource != cachedPreviewSource || currentFitMode != cachedPreviewFitMode || currentRemoveBG != cachedPreviewRemoveBackground {
            invalidatePreviewCache()
        } else if currentItem?.pingPongLoop != previousLoop {
            previewMediaCursor = TerminalSaverMediaCursor()
            mediaFrameAccumulator = 0
            lastPreviewTickTime = 0
        }
        lastSteadyProceduralRenderTime = 0
        renderPreviewStep()
    }

    public func previewSource(_ source: TerminalSaverSource) {
        precondition(Thread.isMainThread)
        previewedSource = source
        let currentItem = config.mediaItem(for: source)
        let currentFitMode = currentItem?.fitMode
        let currentRemoveBG = currentItem?.removeBackground
        if source != cachedPreviewSource || currentFitMode != cachedPreviewFitMode || currentRemoveBG != cachedPreviewRemoveBackground {
            invalidatePreviewCache()
        }
        lastSteadyProceduralRenderTime = 0
        renderPreviewStep()
    }

    public func updateMediaItem(id: UUID, _ mutate: (inout TerminalSaverMediaItem) -> Void) {
        precondition(Thread.isMainThread)
        updateConfig { cfg in
            guard let idx = cfg.mediaItems.firstIndex(where: { $0.id == id }) else { return }
            previewedSource = .media(id)
            mutate(&cfg.mediaItems[idx])
        }
    }

    public func renameMedia(id: UUID, displayName: String) {
        precondition(Thread.isMainThread)
        let sanitized = TerminalSaverMediaItem.sanitizedDisplayName(displayName)
        updateMediaItem(id: id) { item in
            item.displayName = sanitized
        }
    }

    public func toggleSource(_ source: TerminalSaverSource) {
        updateConfig { cfg in
            var pool = cfg.effectiveSelectedSources
            if let idx = pool.firstIndex(of: source) {
                guard pool.count > 1 else {
                    cfg.selectedSource = source
                    previewedSource = source
                    return
                }
                pool.remove(at: idx)
                cfg.selectedSources = pool
                if cfg.selectedSource == source, let replacement = pool.first {
                    cfg.selectedSource = replacement
                }
            } else {
                pool.append(source)
                cfg.selectedSources = pool
                cfg.selectedSource = source
                previewedSource = source
            }
        }
    }

    @discardableResult
    public func importMedia(urls: [URL]) -> UUID? {
        precondition(Thread.isMainThread)
        guard canEditConfiguration else { return nil }
        lastError = nil
        var working = config
        var lastImportedID: UUID?
        for url in urls {
            do {
                let result = try store.importMedia(from: url, currentConfig: working)
                working = result.config
                lastImportedID = result.item.id
            } catch {
                lastError = error.localizedDescription
            }
        }
        if working != config {
            persistedConfig = working
            config = working
            flushConfiguration()
            previewedSource = working.selectedSource
            invalidatePreviewCache()
            renderPreviewStep()
            return lastImportedID
        }
        return nil
    }

    public func deleteMedia(id: UUID) {
        precondition(Thread.isMainThread)
        guard canEditConfiguration, config.mediaItems.contains(where: { $0.id == id }) else { return }
        lastError = nil
        do {
            let updated = try store.deleteMedia(id: id, currentConfig: config)
            persistedConfig = updated
            config = updated
            flushConfiguration()
            if previewedSource == .media(id) {
                previewedSource = config.selectedSource
            }
            invalidatePreviewCache()
            renderPreviewStep()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func refreshShellStatuses() {
        precondition(Thread.isMainThread)
        var next: [TerminalShellTarget: TerminalShellStatus] = [:]
        for target in TerminalShellTarget.allCases {
            next[target] = TerminalSaverShellIntegrator.status(for: target, homeDirectoryURL: shellHomeDirectoryURL)
        }
        shellStatuses = next
    }

    public func installShell(_ target: TerminalShellTarget) {
        precondition(Thread.isMainThread)
        guard flushConfiguration() else { return }
        lastError = nil
        do {
            try TerminalSaverShellIntegrator.install(
                target: target,
                helperPath: helperExecutablePath,
                timeoutSeconds: config.idleTimeoutSeconds,
                homeDirectoryURL: shellHomeDirectoryURL
            )
            refreshShellStatuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func uninstallShell(_ target: TerminalShellTarget) {
        precondition(Thread.isMainThread)
        lastError = nil
        do {
            try TerminalSaverShellIntegrator.uninstall(target: target, homeDirectoryURL: shellHomeDirectoryURL)
            refreshShellStatuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func snippet(for target: TerminalShellTarget) -> String {
        (try? TerminalSaverShellIntegrator.snippet(
            for: target,
            helperPath: helperExecutablePath,
            timeoutSeconds: config.idleTimeoutSeconds
        )) ?? ""
    }

    public func copySnippet(for target: TerminalShellTarget) {
        precondition(Thread.isMainThread)
        let text = snippet(for: target)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func copyPreviewTestCommand() {
        precondition(Thread.isMainThread)
        guard flushConfiguration() else { return }
        let clean = helperExecutablePath.replacingOccurrences(of: "'", with: "")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("'\(clean)' --preview", forType: .string)
    }

    // MARK: - Live Settings Preview (0% CPU when settings window is closed)

    public func startPreview() {
        precondition(Thread.isMainThread)
        guard previewTimer == nil else { return }
        lastPreviewTickTime = CFAbsoluteTimeGetCurrent()
        mediaFrameAccumulator = 0
        renderPreviewStep()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.renderPreviewStep()
        }
        RunLoop.main.add(timer, forMode: .common)
        previewTimer = timer
    }

    public func stopPreview() {
        precondition(Thread.isMainThread)
        previewTimer?.invalidate()
        previewTimer = nil
        isPreviewPlayingStartAnimation = false
        isPreviewPlayingWakeAnimation = false
        isPreviewPlayingTransitionAnimation = false
        wakePreviewBaseFrame = nil
        transitionPreviewFromFrame = nil
        invalidatePreviewCache()
        flushConfiguration()
    }

    public func triggerStartPreview() {
        precondition(Thread.isMainThread)
        isPreviewPlayingWakeAnimation = false
        isPreviewPlayingTransitionAnimation = false
        wakePreviewBaseFrame = nil
        transitionPreviewFromFrame = nil
        startPreviewStartedAt = CFAbsoluteTimeGetCurrent()
        startPreviewSeed = Int.random(in: 1...9999)
        isPreviewPlayingStartAnimation = true
        renderPreviewStep()
    }

    public func triggerWakePreview() {
        precondition(Thread.isMainThread)
        isPreviewPlayingStartAnimation = false
        isPreviewPlayingTransitionAnimation = false
        transitionPreviewFromFrame = nil
        wakePreviewBaseFrame = previewFrame
        wakePreviewStartedAt = CFAbsoluteTimeGetCurrent()
        wakePreviewSeed = Int.random(in: 1...9999)
        isPreviewPlayingWakeAnimation = true
        renderPreviewStep()
    }

    public func triggerTransitionPreview(direction: TerminalTransitionDirection = .forward) {
        precondition(Thread.isMainThread)
        isPreviewPlayingStartAnimation = false
        isPreviewPlayingWakeAnimation = false
        wakePreviewBaseFrame = nil
        let contrastingScene: TerminalSaverBuiltInScene = (previewedSource == .builtIn(.bonfire)) ? .bouncingDVD : .bonfire
        let settings = config[settingsFor: contrastingScene]
        transitionPreviewFromFrame = TerminalSaverProceduralScenes.frame(
            scene: contrastingScene,
            columns: Self.previewColumns,
            rows: Self.previewRows,
            time: settings.animationTime(proceduralPreviewTime, advancingBy: 1.2),
            settings: settings
        )
        transitionPreviewDirection = direction
        transitionPreviewStartedAt = CFAbsoluteTimeGetCurrent()
        transitionPreviewSeed = Int.random(in: 1...9999)
        isPreviewPlayingTransitionAnimation = true
        renderPreviewStep()
    }

    private func invalidatePreviewCache() {
        decodeGeneration &+= 1
        cachedPreviewFrames = []
        cachedRenderedPreviewFrames = []
        cachedPreviewRenderSettings = nil
        cachedPreviewSource = nil
        cachedPreviewFitMode = nil
        cachedPreviewRemoveBackground = nil
        previewMediaCursor = TerminalSaverMediaCursor()
        mediaFrameAccumulator = 0
        lastSteadyProceduralRenderTime = 0
        isDecodingPreview = false
        isPreviewPlayingStartAnimation = false
        isPreviewPlayingWakeAnimation = false
        isPreviewPlayingTransitionAnimation = false
        wakePreviewBaseFrame = nil
        transitionPreviewFromFrame = nil
    }

    private func scheduleDebouncedSave() {
        pendingSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushConfiguration()
        }
        pendingSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private var canEditConfiguration: Bool {
        guard let configurationLoadError else { return true }
        lastError = configurationLoadError
        return false
    }

    @discardableResult
    public func flushConfiguration() -> Bool {
        precondition(Thread.isMainThread)
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        guard canEditConfiguration else { return false }

        if config != persistedConfig {
            do {
                try store.saveConfig(config)
                persistedConfig = config
            } catch {
                configurationWriteError = error.localizedDescription
                lastError = configurationWriteError
                return false
            }
        }

        if lastSyncedTimeout != config.idleTimeoutSeconds {
            do {
                try TerminalSaverShellIntegrator.syncInstalledTargets(
                    helperPath: helperExecutablePath,
                    timeoutSeconds: config.idleTimeoutSeconds,
                    homeDirectoryURL: shellHomeDirectoryURL
                )
                lastSyncedTimeout = config.idleTimeoutSeconds
                refreshShellStatuses()
            } catch {
                configurationWriteError = error.localizedDescription
                lastError = configurationWriteError
                return true
            }
        }
        if let configurationWriteError, lastError == configurationWriteError {
            lastError = nil
        }
        configurationWriteError = nil
        return true
    }

    private func renderPreviewStep() {
        precondition(Thread.isMainThread)
        let now = CFAbsoluteTimeGetCurrent()
        let dt = lastPreviewTickTime > 0 ? min(0.25, max(0, now - lastPreviewTickTime)) : 0
        lastPreviewTickTime = now

        if isPreviewPlayingWakeAnimation, let base = wakePreviewBaseFrame {
            let clampedWake = TerminalSaverPolicy.clamp(
                config.wakeDurationMilliseconds,
                TerminalSaverPolicy.wakeDurationRange
            )
            let durationSeconds = Double(clampedWake) / 1000.0
            let progress = (now - wakePreviewStartedAt) / durationSeconds
            if progress < 1.0 && config.wakeAnimation != .instant {
                previewModel.update(TerminalSaverWakeAnimations.frame(
                    base: base,
                    animation: config.wakeAnimation,
                    progress: progress,
                    seed: wakePreviewSeed
                ))
                return
            } else {
                isPreviewPlayingWakeAnimation = false
                wakePreviewBaseFrame = nil
            }
        }

        let isTransitionActive = isPreviewPlayingTransitionAnimation || isPreviewPlayingStartAnimation
        let targetFrame: ASCIIFrame
        switch previewedSource {
        case .builtIn(let scene):
            if !isTransitionActive {
                let minInterval = 1.0 / Double(TerminalSaverPolicy.clamp(config.framesPerSecond, TerminalSaverPolicy.framesPerSecondRange))
                if lastSteadyProceduralRenderTime > 0 && (now - lastSteadyProceduralRenderTime) < minInterval {
                    return
                }
            }
            let elapsed = lastSteadyProceduralRenderTime > 0 ? min(0.25, max(0, now - lastSteadyProceduralRenderTime)) : dt
            lastSteadyProceduralRenderTime = now
            targetFrame = renderProceduralPreview(scene, elapsed: elapsed)
        case .media(let id):
            if let item = config.mediaItems.first(where: { $0.id == id }) {
                let fitMode = item.fitMode
                let removeBG = item.removeBackground
                if cachedPreviewSource != previewedSource
                    || cachedPreviewFitMode != fitMode
                    || cachedPreviewRemoveBackground != removeBG {
                    startAsyncMediaDecode(
                        id: id,
                        source: previewedSource,
                        fitMode: fitMode,
                        removeBackground: removeBG,
                        fps: config.framesPerSecond
                    )
                }
                if !cachedPreviewFrames.isEmpty {
                    if cachedPreviewFrames.count > 1 {
                        let speed = TerminalSaverPolicy.clampedSpeed(item.playbackSpeed)
                        mediaFrameAccumulator += dt * speed
                        var steps = 0
                        while steps < 4 {
                            let frameDelay = max(
                                TerminalSaverPolicy.minimumFrameDelay,
                                cachedPreviewFrames[previewMediaCursor.frameIndex].delaySeconds
                            )
                            guard mediaFrameAccumulator >= frameDelay else { break }
                            mediaFrameAccumulator -= frameDelay
                            previewMediaCursor.advance(frameCount: cachedPreviewFrames.count, pingPong: item.pingPongLoop)
                            steps += 1
                        }
                        if mediaFrameAccumulator > 1.0 {
                            mediaFrameAccumulator = 0
                        }
                    }
                    let settings = ASCIIRenderSettings(mediaItem: item, config: config)
                    if cachedPreviewRenderSettings != settings || cachedRenderedPreviewFrames.count != cachedPreviewFrames.count {
                        cachedPreviewRenderSettings = settings
                        cachedRenderedPreviewFrames = Array(repeating: nil, count: cachedPreviewFrames.count)
                    }
                    let frameIndex = previewMediaCursor.frameIndex
                    if let cachedFrame = cachedRenderedPreviewFrames[frameIndex] {
                        targetFrame = cachedFrame
                    } else {
                        let rendered = ASCIIRenderEngine.render(
                            grid: cachedPreviewFrames[frameIndex].grid,
                            settings: settings
                        )
                        cachedRenderedPreviewFrames[frameIndex] = rendered
                        targetFrame = rendered
                    }
                } else {
                    targetFrame = ASCIIFrame(columns: Self.previewColumns, rows: Self.previewRows)
                }
            } else {
                targetFrame = renderProceduralPreview(.bonfire, elapsed: dt)
            }
        }

        if isPreviewPlayingTransitionAnimation, let fromFrame = transitionPreviewFromFrame {
            let clampedTransition = TerminalSaverPolicy.clamp(
                config.transitionDurationMilliseconds,
                TerminalSaverPolicy.transitionDurationRange
            )
            let durationSeconds = Double(clampedTransition) / 1000.0
            let progress = (now - transitionPreviewStartedAt) / durationSeconds
            if progress < 1.0 && config.transitionAnimation != .instant {
                previewModel.update(TerminalSaverWakeAnimations.transitionFrame(
                    from: fromFrame,
                    to: targetFrame,
                    animation: config.transitionAnimation,
                    direction: transitionPreviewDirection,
                    progress: progress,
                    seed: transitionPreviewSeed
                ))
                return
            } else {
                isPreviewPlayingTransitionAnimation = false
                transitionPreviewFromFrame = nil
            }
        }

        if isPreviewPlayingStartAnimation {
            let clampedStart = TerminalSaverPolicy.clamp(
                config.startDurationMilliseconds,
                TerminalSaverPolicy.startDurationRange
            )
            let durationSeconds = Double(clampedStart) / 1000.0
            let progress = (now - startPreviewStartedAt) / durationSeconds
            if progress < 1.0 && config.startAnimation != .instant {
                previewModel.update(TerminalSaverWakeAnimations.entryFrame(
                    target: targetFrame,
                    animation: config.startAnimation,
                    progress: progress,
                    seed: startPreviewSeed
                ))
                return
            } else {
                isPreviewPlayingStartAnimation = false
            }
        }

        previewModel.update(targetFrame)
    }

    private func renderProceduralPreview(_ scene: TerminalSaverBuiltInScene, elapsed: Double) -> ASCIIFrame {
        let settings = config[settingsFor: scene]
        proceduralPreviewTime = settings.animationTime(proceduralPreviewTime, advancingBy: elapsed)
        return TerminalSaverProceduralScenes.frame(
            scene: scene,
            columns: Self.previewColumns,
            rows: Self.previewRows,
            time: proceduralPreviewTime,
            settings: settings
        )
    }

    private func startAsyncMediaDecode(
        id: UUID,
        source: TerminalSaverSource,
        fitMode: ASCIIFitMode,
        removeBackground: Bool,
        fps: Int
    ) {
        guard let item = config.mediaItems.first(where: { $0.id == id }) else { return }
        decodeGeneration &+= 1
        let expectedGeneration = decodeGeneration
        cachedPreviewSource = source
        cachedPreviewFitMode = fitMode
        cachedPreviewRemoveBackground = removeBackground
        cachedPreviewFrames = []
        previewMediaCursor = TerminalSaverMediaCursor()
        mediaFrameAccumulator = 0
        isDecodingPreview = true

        decodeQueue.async { [weak self, store] in
            do {
                let decoded: TerminalSaverDecodedMedia
                if removeBackground {
                    if let cachedData = try? store.readCutoutData(for: item),
                       let cachedMedia = try? TerminalSaverMediaDecoder.decodeImage(data: cachedData, maxEdge: TerminalSaverPolicy.maxCutoutEdge) {
                        decoded = cachedMedia
                    } else {
                        DispatchQueue.main.async {
                            self?.processingCutoutMediaIDs.insert(id)
                        }
                        defer {
                            DispatchQueue.main.async {
                                self?.processingCutoutMediaIDs.remove(id)
                            }
                        }

                        let original: TerminalSaverDecodedMedia
                        switch item.kind {
                        case .image:
                            let data = try store.readMediaData(for: item)
                            original = try TerminalSaverMediaDecoder.decodeImage(data: data, maxEdge: TerminalSaverPolicy.maxCutoutEdge)
                        case .video:
                            let url = try store.mediaFileURL(for: item)
                            original = try TerminalSaverMediaDecoder.decodeVideo(
                                url: url,
                                targetFPS: fps,
                                maxEdge: TerminalSaverPolicy.maxCutoutEdge,
                                maxSamples: TerminalSaverPolicy.maxCutoutFrames
                            )
                        }

                        if let cutoutFrames = TerminalSaverBackgroundRemover.generateCutout(frames: original.frames) {
                            if let apng = try? TerminalSaverBackgroundRemover.encodeCutoutAPNG(frames: cutoutFrames) {
                                try? store.writeCutoutData(apng, for: item)
                            }
                            decoded = TerminalSaverDecodedMedia(frames: cutoutFrames)
                        } else {
                            decoded = original
                        }
                    }
                } else {
                    switch item.kind {
                    case .image:
                        let data = try store.readMediaData(for: item)
                        decoded = try TerminalSaverMediaDecoder.decodeImage(data: data, maxEdge: 256)
                    case .video:
                        let url = try store.mediaFileURL(for: item)
                        decoded = try TerminalSaverMediaDecoder.decodeVideo(url: url, targetFPS: fps, maxEdge: 256, maxSamples: 90)
                    }
                }

                let frames: [(grid: ASCIIPixelGrid, delaySeconds: Double)] = decoded.frames.compactMap { frame in
                    guard let grid = ASCIIRenderEngine.sample(
                        image: frame.image,
                        columns: Self.previewColumns,
                        rows: Self.previewRows,
                        fitMode: fitMode
                    ) else {
                        return nil
                    }
                    return (grid, frame.delaySeconds)
                }

                DispatchQueue.main.async {
                    guard let self, self.decodeGeneration == expectedGeneration else { return }
                    self.cachedPreviewFrames = frames
                    self.cachedRenderedPreviewFrames = Array(repeating: nil, count: frames.count)
                    self.cachedPreviewRenderSettings = nil
                    self.previewMediaCursor = TerminalSaverMediaCursor()
                    self.mediaFrameAccumulator = 0
                    self.lastPreviewTickTime = 0
                    self.isDecodingPreview = false
                    self.renderPreviewStep()
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    guard let self, self.decodeGeneration == expectedGeneration else { return }
                    self.lastError = message
                    self.isDecodingPreview = false
                }
            }
        }
    }
}
