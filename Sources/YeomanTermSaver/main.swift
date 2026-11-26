import Foundation
import Darwin
import YeomanCore

private var gShouldExit: sig_atomic_t = 0
private var gDidResize: sig_atomic_t = 0

private func handleExitSignal(_: Int32) {
    gShouldExit = 1
}

private func handleResizeSignal(_: Int32) {
    gDidResize = 1
}

private func writeAll(_ string: String) {
    guard !string.isEmpty else { return }
    let bytes = Array(string.utf8)
    var written = 0
    while written < bytes.count {
        let n = bytes.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            return Darwin.write(STDOUT_FILENO, base.advanced(by: written), bytes.count - written)
        }
        if n < 0 && errno == EINTR { continue }
        if n <= 0 { break }
        written += n
    }
}

private func isBufferedTerminal(environment: [String: String]) -> Bool {
    let termProgram = (environment["TERM_PROGRAM"] ?? "").lowercased()
    let nativePrograms = ["ghostty", "apple_terminal", "iterm.app", "wezterm", "alacritty", "kitty", "warpterminal"]
    if nativePrograms.contains(termProgram) {
        return false
    }
    if termProgram.contains("vscode")
        || termProgram.contains("cursor")
        || termProgram.contains("windsurf")
        || termProgram.contains("antigravity") {
        return true
    }
    if environment["GHOSTTY_RESOURCES_DIR"] != nil { return false }
    return environment.keys.contains { $0.hasPrefix("VSCODE_") }
}

private struct TerminalDisplay {
    let useSyncOutput: Bool
    let colorMode: ASCIIColorMode
    private(set) var lastFrame: ASCIIFrame?
    private var needsClear = false

    init(useSyncOutput: Bool, colorMode: ASCIIColorMode) {
        self.useSyncOutput = useSyncOutput
        self.colorMode = colorMode
    }

    mutating func invalidate() {
        lastFrame = nil
        needsClear = true
    }

    mutating func draw(_ frame: ASCIIFrame) -> Bool {
        guard gDidResize == 0, gShouldExit == 0 else { return false }
        if !needsClear, lastFrame == frame { return true }
        let encoded = ASCIIANSIEncoder.encode(frame, previous: lastFrame, mode: colorMode)
        let output = (needsClear ? "\u{1B}[0m\u{1B}[2J" : "") + encoded
        guard gDidResize == 0, gShouldExit == 0 else { return false }
        if !output.isEmpty {
            writeAll(useSyncOutput ? ("\u{1B}[?2026h" + output + "\u{1B}[?2026l") : output)
        }
        lastFrame = frame
        needsClear = false
        return true
    }
}

private func pacedTransitionStepCount(
    durationMilliseconds: Int,
    nominalSteps: Int,
    isBuffered: Bool
) -> Int {
    guard isBuffered else { return nominalSteps }
    return max(6, min(nominalSteps, Int((Double(durationMilliseconds) / 40.0).rounded())))
}

private func terminalGrid() -> (columns: Int, rows: Int)? {
    var ws = winsize()
    guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0,
          ws.ws_col >= TerminalSaverPolicy.columnRange.lowerBound,
          ws.ws_row >= TerminalSaverPolicy.rowRange.lowerBound else { return nil }
    return TerminalSaverPolicy.clampedGrid(columns: Int(ws.ws_col), rows: Int(ws.ws_row))
}

private enum PlaybackContent {
    case procedural(TerminalSaverBuiltInScene)
    case images(TerminalSaverDecodedMedia, ASCIIRenderSettings, speed: Double, pingPong: Bool)

    var hasMediaLoop: Bool {
        if case .images(let media, _, _, _) = self { return media.frames.count > 1 }
        return false
    }

    func advance(_ cursor: inout TerminalSaverMediaCursor) -> Bool {
        guard case .images(let media, _, _, let pingPong) = self else { return false }
        return cursor.advance(frameCount: media.frames.count, pingPong: pingPong)
    }
}

private final class CachedPlayback {
    let source: TerminalSaverSource
    let playback: PlaybackContent
    var sampledGrids: [ASCIIPixelGrid?]
    var renderedFrames: [ASCIIFrame?]
    var sampledSize: (columns: Int, rows: Int)?

    init(
        source: TerminalSaverSource,
        playback: PlaybackContent,
        sampledGrids: [ASCIIPixelGrid?],
        sampledSize: (columns: Int, rows: Int)?
    ) {
        self.source = source
        self.playback = playback
        self.sampledGrids = sampledGrids
        self.renderedFrames = Array(repeating: nil, count: sampledGrids.count)
        self.sampledSize = sampledSize
    }
}

private func loadPlayback(for source: TerminalSaverSource, config: TerminalSaverConfig) -> PlaybackContent {
    switch source {
    case .builtIn(let scene):
        return .procedural(scene)
    case .media(let id):
        guard let item = config.mediaItems.first(where: { $0.id == id }) else {
            return .procedural(.bonfire)
        }
        do {
            let decoded: TerminalSaverDecodedMedia
            if item.removeBackground,
               let cachedData = try? TerminalSaverMediaStore.shared.readCutoutData(for: item),
               let cachedMedia = try? TerminalSaverMediaDecoder.decodeImage(data: cachedData, maxEdge: TerminalSaverPolicy.maxCutoutEdge) {
                decoded = cachedMedia
            } else {
                let original: TerminalSaverDecodedMedia
                switch item.kind {
                case .image:
                    let data = try TerminalSaverMediaStore.shared.readMediaData(for: item)
                    original = try TerminalSaverMediaDecoder.decodeImage(data: data)
                case .video:
                    let url = try TerminalSaverMediaStore.shared.mediaFileURL(for: item)
                    if item.removeBackground {
                        original = try TerminalSaverMediaDecoder.decodeVideo(
                            url: url,
                            targetFPS: config.framesPerSecond,
                            maxEdge: TerminalSaverPolicy.maxCutoutEdge,
                            maxSamples: TerminalSaverPolicy.maxCutoutFrames
                        )
                    } else {
                        original = try TerminalSaverMediaDecoder.decodeVideo(
                            url: url,
                            targetFPS: config.framesPerSecond,
                            maxEdge: 256,
                            maxSamples: 120
                        )
                    }
                }

                if item.removeBackground,
                   let cutoutFrames = TerminalSaverBackgroundRemover.generateCutout(frames: original.frames) {
                    if let apng = try? TerminalSaverBackgroundRemover.encodeCutoutAPNG(frames: cutoutFrames) {
                        try? TerminalSaverMediaStore.shared.writeCutoutData(apng, for: item)
                    }
                    decoded = TerminalSaverDecodedMedia(frames: cutoutFrames)
                } else {
                    decoded = original
                }
            }
            let itemSettings = ASCIIRenderSettings(mediaItem: item, config: config)
            let speed = TerminalSaverPolicy.clampedSpeed(item.playbackSpeed)
            return decoded.frames.isEmpty
                ? .procedural(.bonfire)
                : .images(decoded, itemSettings, speed: speed, pingPong: item.pingPongLoop)
        } catch {
            return .procedural(.bonfire)
        }
    }
}

private func samplePlaybackGrids(
    _ playback: PlaybackContent,
    gridSize: (columns: Int, rows: Int)
) -> [ASCIIPixelGrid?] {
    guard case .images(let media, let settings, _, _) = playback else {
        return []
    }
    return media.frames.map {
        ASCIIRenderEngine.sample(image: $0.image, columns: gridSize.columns, rows: gridSize.rows, fitMode: settings.fitMode)
    }
}

private func cachedEntry(
    for source: TerminalSaverSource,
    cache: inout [CachedPlayback],
    gridSize: (columns: Int, rows: Int)?,
    config: TerminalSaverConfig
) -> CachedPlayback {
    if let idx = cache.firstIndex(where: { $0.source == source }) {
        let entry = cache.remove(at: idx)
        if let gridSize, case .images = entry.playback,
           entry.sampledSize?.columns != gridSize.columns || entry.sampledSize?.rows != gridSize.rows {
            entry.sampledGrids = samplePlaybackGrids(entry.playback, gridSize: gridSize)
            entry.renderedFrames = Array(repeating: nil, count: entry.sampledGrids.count)
            entry.sampledSize = gridSize
        }
        cache.append(entry)
        return entry
    }

    let playback = loadPlayback(for: source, config: config)
    let grids = gridSize.map { samplePlaybackGrids(playback, gridSize: $0) } ?? []
    let entry = CachedPlayback(
        source: source,
        playback: playback,
        sampledGrids: grids,
        sampledSize: grids.isEmpty ? nil : gridSize
    )
    if cache.count >= TerminalSaverPolicy.maxCachedSessionPlaybacks {
        cache.removeFirst(cache.count - TerminalSaverPolicy.maxCachedSessionPlaybacks + 1)
    }
    cache.append(entry)
    return entry
}

private func renderPlaybackFrame(
    entry: CachedPlayback,
    gridSize: (columns: Int, rows: Int),
    config: TerminalSaverConfig,
    proceduralTime: Double,
    mediaFrameIndex: Int
) -> (frame: ASCIIFrame, delaySeconds: Double) {
    switch entry.playback {
    case .procedural(let scene):
        let frame = TerminalSaverProceduralScenes.frame(
            scene: scene,
            columns: gridSize.columns,
            rows: gridSize.rows,
            time: proceduralTime,
            settings: config[settingsFor: scene]
        )
        let delay = 1.0 / Double(TerminalSaverPolicy.clamp(config.framesPerSecond, TerminalSaverPolicy.framesPerSecondRange))
        return (frame, delay)
    case .images(let media, let itemSettings, let speed, _):
        if entry.sampledSize?.columns != gridSize.columns || entry.sampledSize?.rows != gridSize.rows {
            entry.sampledGrids = samplePlaybackGrids(entry.playback, gridSize: gridSize)
            entry.renderedFrames = Array(repeating: nil, count: entry.sampledGrids.count)
            entry.sampledSize = gridSize
        }
        let frame: ASCIIFrame
        if mediaFrameIndex < entry.renderedFrames.count, let cached = entry.renderedFrames[mediaFrameIndex] {
            frame = cached
        } else if let grid = entry.sampledGrids[mediaFrameIndex] {
            let rendered = ASCIIRenderEngine.render(grid: grid, settings: itemSettings)
            if mediaFrameIndex < entry.renderedFrames.count {
                entry.renderedFrames[mediaFrameIndex] = rendered
            }
            frame = rendered
        } else {
            frame = ASCIIFrame(columns: gridSize.columns, rows: gridSize.rows)
        }
        let decoded = media.frames[mediaFrameIndex]
        let delay = media.frames.count > 1 ? TerminalSaverPolicy.adjustedFrameDelay(decoded.delaySeconds, speed: speed) : 5.0
        return (frame, delay)
    }
}

private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

private func pollInputAction(
    pfd: inout pollfd,
    timeoutMs: Int32,
    previousKey: TerminalSaverKey,
    nextKey: TerminalSaverKey
) -> TerminalSaverInputAction {
    guard Darwin.poll(&pfd, 1, timeoutMs) > 0 else { return .none }
    if (pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) != 0 { return .wake }
    if (pfd.revents & Int16(POLLIN)) != 0 {
        return TerminalSaverInputParser.readAction(from: pfd.fd, previousKey: previousKey, nextKey: nextKey)
    }
    return .none
}

private func paceAfterFrame(
    stepDeadline: TimeInterval,
    minPaintSeconds: Double,
    pfd: inout pollfd,
    previousKey: TerminalSaverKey,
    nextKey: TerminalSaverKey,
    deferNavigation: Bool = false
) -> TerminalSaverInputAction {
    let deadline = max(stepDeadline, uptime + minPaintSeconds)
    var pending: TerminalSaverInputAction = .none
    while gShouldExit == 0 {
        if gDidResize != 0 { return pending }
        let remaining = deadline - uptime
        if remaining <= 0 { return pending }
        let action = pollInputAction(
            pfd: &pfd,
            timeoutMs: Int32(min(50, (remaining * 1000).rounded(.up))),
            previousKey: previousKey,
            nextKey: nextKey
        )
        if action == .wake { return .wake }
        if action != .none {
            if !deferNavigation { return action }
            pending = action
        }
    }
    return .wake
}

private func playEntryAnimation(
    target: ASCIIFrame,
    animation: TerminalWakeAnimation,
    durationMilliseconds: Int,
    isBuffered: Bool,
    previousKey: TerminalSaverKey,
    nextKey: TerminalSaverKey,
    pfd: inout pollfd,
    display: inout TerminalDisplay
) -> TerminalSaverInputAction {
    let clampedDuration = TerminalSaverPolicy.clamp(durationMilliseconds, TerminalSaverPolicy.startDurationRange)
    let nominalSteps = TerminalSaverWakeAnimations.entryFrameCount(
        animation: animation,
        durationMilliseconds: clampedDuration
    )
    let totalSteps = pacedTransitionStepCount(
        durationMilliseconds: clampedDuration,
        nominalSteps: nominalSteps,
        isBuffered: isBuffered
    )
    let stepSeconds = Double(clampedDuration) / 1000.0 / Double(max(1, totalSteps))
    let animStart = uptime
    let seed = Int(Date().timeIntervalSince1970) &+ Int.random(in: 1...999)
    for step in 1...totalSteps {
        if gShouldExit != 0 { return .wake }
        if gDidResize != 0 { return .none }
        let progress = Double(step) / Double(totalSteps)
        let frame = TerminalSaverWakeAnimations.entryFrame(
            target: target,
            animation: animation,
            progress: progress,
            seed: seed
        )
        guard display.draw(frame) else { return .none }
        let action = paceAfterFrame(
            stepDeadline: animStart + (Double(step) * stepSeconds),
            minPaintSeconds: isBuffered ? 0.024 : 0,
            pfd: &pfd,
            previousKey: previousKey,
            nextKey: nextKey
        )
        if action != .none { return action }
    }
    return .none
}

private func playTransitionAnimation(
    to: ASCIIFrame,
    animation: TerminalTransitionAnimation,
    direction: TerminalTransitionDirection,
    durationMilliseconds: Int,
    isBuffered: Bool,
    previousKey: TerminalSaverKey,
    nextKey: TerminalSaverKey,
    pfd: inout pollfd,
    display: inout TerminalDisplay
) -> TerminalSaverInputAction {
    guard let from = display.lastFrame, animation != .instant else {
        _ = display.draw(to)
        return .none
    }
    let clampedDuration = TerminalSaverPolicy.clamp(durationMilliseconds, TerminalSaverPolicy.transitionDurationRange)
    let nominalSteps = TerminalSaverWakeAnimations.transitionFrameCount(
        animation: animation,
        durationMilliseconds: clampedDuration
    )
    let totalSteps = pacedTransitionStepCount(
        durationMilliseconds: clampedDuration,
        nominalSteps: nominalSteps,
        isBuffered: isBuffered
    )
    let stepSeconds = Double(clampedDuration) / 1000.0 / Double(max(1, totalSteps))
    let animStart = uptime
    let seed = Int(Date().timeIntervalSince1970) &+ Int.random(in: 1...999)
    var pending: TerminalSaverInputAction = .none
    for step in 1...totalSteps {
        if gShouldExit != 0 { return .wake }
        if gDidResize != 0 { return pending }
        let progress = Double(step) / Double(totalSteps)
        let frame = TerminalSaverWakeAnimations.transitionFrame(
            from: from,
            to: to,
            animation: animation,
            direction: direction,
            progress: progress,
            seed: seed
        )
        guard display.draw(frame) else { return pending }
        let action = paceAfterFrame(
            stepDeadline: animStart + (Double(step) * stepSeconds),
            minPaintSeconds: isBuffered ? 0.024 : 0,
            pfd: &pfd,
            previousKey: previousKey,
            nextKey: nextKey,
            deferNavigation: true
        )
        if action == .wake { return .wake }
        if action != .none { pending = action }
    }
    return pending
}

private func runMain() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    var isPreview = false
    var printHookTarget: TerminalShellTarget?
    var forcedScene: TerminalSaverBuiltInScene?
    var forcedMedia: UUID?
    var forcedStart: TerminalWakeAnimation?
    var forcedWake: TerminalWakeAnimation?
    var forcedTransition: TerminalTransitionAnimation?

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--preview":
            isPreview = true
        case "--run":
            break
        case "--source":
            i += 1
        case "--print-hook":
            if i + 1 < args.count {
                printHookTarget = TerminalShellTarget(rawValue: args[i + 1])
                i += 1
            }
        case "--scene":
            if i + 1 < args.count {
                forcedScene = TerminalSaverBuiltInScene(identifier: args[i + 1])
                i += 1
            }
        case "--media":
            if i + 1 < args.count {
                forcedMedia = UUID(uuidString: args[i + 1])
                i += 1
            }
        case "--start":
            if i + 1 < args.count {
                forcedStart = TerminalWakeAnimation(rawValue: args[i + 1])
                i += 1
            }
        case "--wake":
            if i + 1 < args.count {
                forcedWake = TerminalWakeAnimation(rawValue: args[i + 1])
                i += 1
            }
        case "--transition":
            if i + 1 < args.count {
                forcedTransition = TerminalTransitionAnimation(rawValue: args[i + 1])
                i += 1
            }
        default:
            break
        }
        i += 1
    }

    let config = (try? TerminalSaverMediaStore.shared.loadConfig()) ?? TerminalSaverConfig()

    if let printHookTarget {
        if let snippet = try? TerminalSaverShellIntegrator.snippet(
            for: printHookTarget,
            helperPath: CommandLine.arguments[0],
            timeoutSeconds: config.idleTimeoutSeconds
        ) {
            print(snippet)
            return 0
        }
        return 1
    }

    guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
        return 0
    }
    guard config.isEnabled || isPreview else {
        return 0
    }

    var originalTermios = termios()
    guard tcgetattr(STDIN_FILENO, &originalTermios) == 0 else {
        return 0
    }

    signal(SIGINT, handleExitSignal)
    signal(SIGTERM, handleExitSignal)
    signal(SIGHUP, handleExitSignal)
    signal(SIGWINCH, handleResizeSignal)

    var rawTermios = originalTermios
    rawTermios.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
    rawTermios.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
    rawTermios.c_cflag &= ~tcflag_t(CSIZE | PARENB)
    rawTermios.c_cflag |= tcflag_t(CS8)
    rawTermios.c_cc.16 = 0 // VMIN = 0
    rawTermios.c_cc.17 = 0 // VTIME = 0
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &rawTermios)

    writeAll("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J\u{1B}[H")
    defer {
        writeAll("\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    }

    let env = ProcessInfo.processInfo.environment
    let isBuffered = isBufferedTerminal(environment: env)
    // Rapid TrueColor changes produce many glyph/color combinations in IDE glyph atlases.
    let colorMode: ASCIIColorMode = isBuffered ? .palette256 : ASCIIColorMode.detect(environment: env)
    let activePool = config.effectiveSelectedSources
    let forcedSource: TerminalSaverSource? = forcedScene.map { .builtIn($0) } ?? forcedMedia.map { .media($0) }
    let autoAdvance = activePool.count > 1 && forcedSource == nil ? config.autoAdvance : TerminalSaverAutoAdvanceSettings()
    let store = TerminalSaverMediaStore.shared
    var (navigator, savedRotationState) = store.startRotationSession(for: activePool, previewing: forcedSource)

    let startAnimation = forcedStart ?? config.startAnimation
    let wakeAnimation = forcedWake ?? config.wakeAnimation
    let transitionAnimation = forcedTransition ?? config.transitionAnimation
    let previousKey = config.previousKey
    let nextKey = config.nextKey

    var gridSize = terminalGrid()
    var playbackCache: [CachedPlayback] = []
    var activeEntry = cachedEntry(
        for: navigator.current,
        cache: &playbackCache,
        gridSize: gridSize,
        config: config
    )

    var display = TerminalDisplay(useSyncOutput: !isBuffered, colorMode: colorMode)
    var lastTickTime = uptime
    var proceduralTime: Double = 0
    var mediaCursor = TerminalSaverMediaCursor()
    var autoAdvanceDeadline: TimeInterval?
    var finishedMediaCycle = false
    var needsEntryAnimation = (startAnimation != .instant)
    var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)

    func switchScene(
        _ action: TerminalSaverInputAction,
        automatically: Bool,
        gridSize: (columns: Int, rows: Int)
    ) -> TerminalSaverInputAction {
        let direction: TerminalTransitionDirection = action == .next ? .forward : .backward
        let nextTarget = direction == .forward ? navigator.stepForward() : navigator.stepBackward()
        guard let nextSource = nextTarget else { return .none }

        if let expectedState = savedRotationState {
            let state = navigator.state
            savedRotationState = store.saveRotationProgress(state, replacing: expectedState) ? state : nil
        }
        activeEntry = cachedEntry(for: nextSource, cache: &playbackCache, gridSize: gridSize, config: config)
        mediaCursor = TerminalSaverMediaCursor()
        autoAdvanceDeadline = nil
        finishedMediaCycle = false
        proceduralTime = 0
        let previewStep = renderPlaybackFrame(
            entry: activeEntry,
            gridSize: gridSize,
            config: config,
            proceduralTime: proceduralTime,
            mediaFrameIndex: mediaCursor.frameIndex
        )
        let transitionAction = playTransitionAnimation(
            to: previewStep.frame,
            animation: automatically && transitionAnimation == .instant ? .dissolve : transitionAnimation,
            direction: direction,
            durationMilliseconds: config.transitionDurationMilliseconds,
            isBuffered: isBuffered,
            previousKey: previousKey,
            nextKey: nextKey,
            pfd: &pfd,
            display: &display
        )
        lastTickTime = uptime
        return transitionAction
    }

    var pendingNavigation: TerminalSaverInputAction = .none

    while gShouldExit == 0 {
        if gDidResize != 0 {
            gDidResize = 0
            display.invalidate()
            // Coalesce live-resize signals before clearing and repainting the grid.
            let action = paceAfterFrame(
                stepDeadline: uptime + 0.08,
                minPaintSeconds: 0,
                pfd: &pfd,
                previousKey: previousKey,
                nextKey: nextKey,
                deferNavigation: true
            )
            if action == .wake { break }
            if action != .none { pendingNavigation = action }
            if gDidResize != 0 { continue }
            gridSize = terminalGrid()
            if gridSize == nil { writeAll("\u{1B}[0m\u{1B}[2J") }
        }

        if gridSize == nil { gridSize = terminalGrid() }
        guard let gridSize else {
            let action = pollInputAction(pfd: &pfd, timeoutMs: 50, previousKey: previousKey, nextKey: nextKey)
            if action == .wake { break }
            if action != .none { pendingNavigation = action }
            continue
        }

        let tickNow = uptime
        let dt = min(0.25, max(0, tickNow - lastTickTime))
        lastTickTime = tickNow

        let hasMediaLoop = activeEntry.playback.hasMediaLoop
        let timeElapsed = autoAdvanceDeadline.map { tickNow >= $0 } ?? false
        let automatic = pendingNavigation == .none
            && display.lastFrame != nil
            && autoAdvance.shouldAdvance(
                timeElapsed: timeElapsed,
                hasMediaLoop: hasMediaLoop,
                finishedMediaCycle: finishedMediaCycle
            )
        if automatic || pendingNavigation != .none {
            pendingNavigation = switchScene(
                automatic ? .next : pendingNavigation,
                automatically: automatic,
                gridSize: gridSize
            )
            if pendingNavigation == .wake { break }
            continue
        }

        if case .procedural(let scene) = activeEntry.playback {
            proceduralTime = config[settingsFor: scene].animationTime(proceduralTime, advancingBy: dt)
        }
        let step = renderPlaybackFrame(
            entry: activeEntry,
            gridSize: gridSize,
            config: config,
            proceduralTime: proceduralTime,
            mediaFrameIndex: mediaCursor.frameIndex
        )

        let delaySeconds = min(5, max(0.01, step.delaySeconds))

        if needsEntryAnimation {
            needsEntryAnimation = false
            let action = playEntryAnimation(
                target: step.frame,
                animation: startAnimation,
                durationMilliseconds: config.startDurationMilliseconds,
                isBuffered: isBuffered,
                previousKey: previousKey,
                nextKey: nextKey,
                pfd: &pfd,
                display: &display
            )
            lastTickTime = uptime
            if action == .wake { break }
            if action != .none {
                pendingNavigation = action
                continue
            }
        } else {
            guard display.draw(step.frame) else { continue }
        }

        guard gDidResize == 0 else { continue }
        finishedMediaCycle = false
        let frameStartedAt = uptime
        if autoAdvanceDeadline == nil, let duration = autoAdvance.timeLimit {
            autoAdvanceDeadline = frameStartedAt + duration
        }
        let waitForLoop = hasMediaLoop && autoAdvance.waitsForMediaLoop
        let frameDeadline = frameStartedAt + delaySeconds
        let inputAction = paceAfterFrame(
            stepDeadline: waitForLoop ? frameDeadline : min(frameDeadline, autoAdvanceDeadline ?? frameDeadline),
            minPaintSeconds: 0,
            pfd: &pfd,
            previousKey: previousKey,
            nextKey: nextKey
        )
        if inputAction == .wake {
            break
        }
        if inputAction == .next || inputAction == .previous {
            pendingNavigation = inputAction
        } else if gDidResize == 0 {
            finishedMediaCycle = activeEntry.playback.advance(&mediaCursor)
        }
    }

    // Skip the closing animation if the displayed raster is no longer valid.
    if gShouldExit == 0, gDidResize == 0, wakeAnimation != .instant, let lastFrame = display.lastFrame {
        let clampedWakeDuration = TerminalSaverPolicy.clamp(
            config.wakeDurationMilliseconds,
            TerminalSaverPolicy.wakeDurationRange
        )
        let nominalSteps = TerminalSaverWakeAnimations.frameCount(
            animation: wakeAnimation,
            durationMilliseconds: clampedWakeDuration
        )
        let totalSteps = pacedTransitionStepCount(
            durationMilliseconds: clampedWakeDuration,
            nominalSteps: nominalSteps,
            isBuffered: isBuffered
        )
        let stepSeconds = Double(clampedWakeDuration) / 1000.0 / Double(max(1, totalSteps))
        let animStart = uptime
        let seed = Int(Date().timeIntervalSince1970) &+ Int.random(in: 1...999)
        for step in 1...totalSteps {
            if gShouldExit != 0 || gDidResize != 0 { break }
            let isFinal = (step == totalSteps)
            let progress = Double(step) / Double(totalSteps)
            let wakeFrame = TerminalSaverWakeAnimations.frame(
                base: lastFrame,
                animation: wakeAnimation,
                progress: progress,
                seed: seed
            )
            guard display.draw(wakeFrame) else { break }

            if !isFinal {
                let action = paceAfterFrame(
                    stepDeadline: animStart + (Double(step) * stepSeconds),
                    minPaintSeconds: isBuffered ? 0.024 : 0,
                    pfd: &pfd,
                    previousKey: previousKey,
                    nextKey: nextKey
                )
                if action != .none {
                    break
                }
            }
        }
    }

    return 0
}

exit(runMain())
