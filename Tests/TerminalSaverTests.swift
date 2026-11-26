import Foundation
import AVFoundation
import Combine
import CoreGraphics
import Darwin
import ImageIO
import UniformTypeIdentifiers
import YeomanCore

private func makeSolidCGImage(width: Int, height: Int, fill: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage? {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = fill(x, y)
            let off = (y * width + x) * 4
            pixels[off] = r
            pixels[off + 1] = g
            pixels[off + 2] = b
            pixels[off + 3] = 255
        }
    }
    return pixels.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        return ctx.makeImage()
    }
}

private func makeSyntheticGIFData(frames: [(CGImage, Double)]) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, frames.count, nil) else {
        return nil
    }
    CGImageDestinationSetProperties(dest, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
    for (img, delay) in frames {
        CGImageDestinationAddImage(dest, img, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

private func makeSyntheticPNGData(image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

func runTerminalSaverTests() {
    let harness = TestHarness.shared

    harness.runSuite("Terminal Saver Tests") {
        harness.test("All ASCII render styles contain zero chunky solid blocks") {
            let forbidden: Set<Character> = ["█", "▓", "▒", "░"]
            for style in ASCIIRenderStyle.allCases {
                assertFalse(style.ramp.contains(where: { forbidden.contains($0) }), "Style \(style) must stay block-free")
                let edges = style.edgeGlyphs
                assertFalse(forbidden.contains(edges.vertical) || forbidden.contains(edges.horizontal) ||
                            forbidden.contains(edges.rising) || forbidden.contains(edges.falling))
            }
        }

        harness.test("ASCIIRenderEngine maps horizontal and vertical Sobel edges to directional filigree glyphs") {
            let vEdge = ASCIIRenderEngine.edgeGlyph(gx: 2.0, gy: 0.0, style: .filigree)
            let hEdge = ASCIIRenderEngine.edgeGlyph(gx: 0.0, gy: 2.0, style: .filigree)
            let rEdge = ASCIIRenderEngine.edgeGlyph(gx: 1.5, gy: 1.5, style: .filigree)
            let fEdge = ASCIIRenderEngine.edgeGlyph(gx: -1.5, gy: 1.5, style: .filigree)

            assertEqual(vEdge, "|")
            assertEqual(hEdge, "-")
            assertEqual(rEdge, "/")
            assertEqual(fEdge, "\\")

            let cols = 12, rows = 8
            var red = [Float](repeating: 0, count: cols * rows)
            var green = [Float](repeating: 0, count: cols * rows)
            var blue = [Float](repeating: 0, count: cols * rows)
            for y in 0..<rows {
                for x in 0..<cols where x >= 6 {
                    let idx = y * cols + x
                    red[idx] = 0.9
                    green[idx] = 0.9
                    blue[idx] = 0.9
                }
            }
            let grid = ASCIIPixelGrid(columns: cols, rows: rows, red: red, green: green, blue: blue)
            let frame = ASCIIRenderEngine.render(grid: grid, settings: ASCIIRenderSettings(style: .filigree, edgeDetail: 0.9, darkFloor: 0.05))
            assertTrue(frame[1, 4].isBlank, "Dark region must remain blank negative space")
            assertEqual(frame[6, 4].character, "|")
        }

        harness.test("ASCIIColorMode and xterm256 encoder select compatible fallback and diff skip unchanged rows") {
            assertEqual(ASCIIColorMode.detect(environment: ["COLORTERM": "truecolor"]), .trueColor)
            assertEqual(ASCIIColorMode.detect(environment: ["TERM": "xterm-256color"]), .palette256)

            let blackIdx = ASCIIANSIEncoder.xterm256Index(0, 0, 0)
            let whiteIdx = ASCIIANSIEncoder.xterm256Index(255, 255, 255)
            assertEqual(blackIdx, 16)
            assertEqual(whiteIdx, 231)

            var f1 = ASCIIFrame(columns: 4, rows: 2)
            f1.put(0, 0, "*", 255, 100, 50)
            f1.put(1, 1, "~", 80, 180, 255)
            let full = ASCIIANSIEncoder.encode(f1, previous: nil, mode: .trueColor)
            assertTrue(full.contains("1;1H"))
            assertTrue(full.contains("2;1H"))
            assertTrue(full.contains("\u{1B}[0m\u{1B}[K"))
            assertFalse(full.contains("   "))

            var f2 = f1
            f2.put(0, 0, "+", 255, 100, 50)
            let diff = ASCIIANSIEncoder.encode(f2, previous: f1, mode: .trueColor)
            assertTrue(diff.contains("1;1H"))
            assertFalse(diff.contains("2;1H"))

            var f3 = f2
            f3.put(0, 0, " ", 0, 0, 0)
            let blankRowDiff = ASCIIANSIEncoder.encode(f3, previous: f2, mode: .trueColor)
            assertTrue(blankRowDiff.contains("1;1H\u{1B}[0m\u{1B}[K"))
            assertFalse(blankRowDiff.contains("2;1H"))

            var f4 = ASCIIFrame(columns: 4, rows: 1)
            for x in 0..<4 { f4.put(x, 0, "#", 200, 200, 200) }
            let fullRow = ASCIIANSIEncoder.encode(f4, previous: nil, mode: .trueColor)
            assertTrue(fullRow.contains("1;1H"))
            assertTrue(fullRow.contains("\u{1B}[0m"))
            assertFalse(fullRow.contains("\u{1B}[K"))

            // Span diff skips unchanged leading and trailing columns on incremental row updates
            var widePrev = ASCIIFrame(columns: 12, rows: 1)
            for x in 0..<10 { widePrev.put(x, 0, "A", 100, 150, 200) }
            var wideNext = widePrev
            wideNext.put(8, 0, "Z", 255, 80, 40)
            let spanDiff = ASCIIANSIEncoder.encode(wideNext, previous: widePrev, mode: .trueColor)
            assertTrue(spanDiff.contains("1;9H"), "Mid-row edit at x=8 should jump directly to col 9")
            assertFalse(spanDiff.contains("1;1H"), "Unchanged leading columns must not be rewritten")
            assertFalse(spanDiff.contains("A"), "Unchanged prefix character must not be emitted")

            // Trailing shrink clears only from new lastNonBlank + 1 without rewriting unchanged prefix
            var shrunk = ASCIIFrame(columns: 12, rows: 1)
            for x in 0..<4 { shrunk.put(x, 0, "A", 100, 150, 200) }
            let shrinkDiff = ASCIIANSIEncoder.encode(shrunk, previous: widePrev, mode: .trueColor)
            assertTrue(shrinkDiff.contains("1;5H\u{1B}[0m\u{1B}[K"), "Shrunk tail should clear at col 5")
            assertFalse(shrinkDiff.contains("1;1H"), "Unchanged prefix must not be rewritten on tail shrink")
        }

        harness.test("Built-in procedural scenes and wake animations respect bounds and clear cleanly") {
            for scene in TerminalSaverBuiltInScene.allCases {
                let frame = TerminalSaverProceduralScenes.frame(scene: scene, columns: 48, rows: 16, time: 1.25)
                assertEqual(frame.columns, 48)
                assertEqual(frame.rows, 16)
                assertFalse(frame.isBlank, "Procedural scene \(scene) should draw visible cells")
            }

            let base = TerminalSaverProceduralScenes.frame(scene: .bonfire, columns: 32, rows: 12, time: 0.8)
            for anim in TerminalWakeAnimation.allCases {
                let start = TerminalSaverWakeAnimations.frame(base: base, animation: anim, progress: 0.0)
                if anim == .instant {
                    assertTrue(start.isBlank)
                } else {
                    assertEqual(start, base)
                    let mid = TerminalSaverWakeAnimations.frame(base: base, animation: anim, progress: 0.5, seed: 42)
                    assertEqual(mid.columns, base.columns)
                    assertEqual(mid.rows, base.rows)
                }
                let end = TerminalSaverWakeAnimations.frame(base: base, animation: anim, progress: 1.0, seed: 42)
                assertTrue(end.isBlank, "Wake animation \(anim) must be completely blank at progress 1.0")
            }
        }

        harness.test("Config sanitization clamps extreme inputs and removes invalid media entries") {
            let validItem = TerminalSaverMediaItem(displayName: "bad\nname\t", fileExtension: "gif", byteCount: 1024)
            let invalidExtItem = TerminalSaverMediaItem(displayName: "evil", fileExtension: "sh", byteCount: 100)
            let oversizedItem = TerminalSaverMediaItem(displayName: "huge", fileExtension: "png", byteCount: TerminalSaverPolicy.maxImageBytes + 1)

            let raw = TerminalSaverConfig(
                isEnabled: true,
                idleTimeoutSeconds: -10,
                edgeDetail: Double.nan,
                darkFloor: 9.0,
                framesPerSecond: 999,
                wakeDurationMilliseconds: 10,
                selectedSource: .media(invalidExtItem.id),
                mediaItems: [validItem, invalidExtItem, oversizedItem, validItem]
            )
            let clean = raw.sanitized()
            assertEqual(clean.idleTimeoutSeconds, TerminalSaverPolicy.idleTimeoutRange.lowerBound)
            assertEqual(clean.framesPerSecond, TerminalSaverPolicy.framesPerSecondRange.upperBound)
            assertEqual(clean.wakeDurationMilliseconds, TerminalSaverPolicy.wakeDurationRange.lowerBound)
            assertEqual(clean.edgeDetail, 0.55)
            assertEqual(clean.darkFloor, 0.65)
            assertEqual(clean.mediaItems.count, 1)
            assertEqual(clean.mediaItems.first?.displayName, "bad name")
            assertEqual(clean.selectedSource, .builtIn(.bonfire))
        }

        harness.test("Media decoder & store import synthetic GIF/PNG securely and reject malformed/symlink inputs") {
            let rootDir = try SecureDirectory.temporary()
            defer {
                try? FileManager.default.removeItem(at: rootDir.url)
            }
            let store = TerminalSaverMediaStore(rootDirectoryURL: rootDir.url)

            guard let img1 = makeSolidCGImage(width: 24, height: 16, fill: { x, _ in x < 12 ? (10, 10, 10) : (240, 180, 60) }),
                  let img2 = makeSolidCGImage(width: 24, height: 16, fill: { _, y in y < 8 ? (40, 220, 180) : (10, 10, 10) }),
                  let gifData = makeSyntheticGIFData(frames: [(img1, 0.08), (img2, 0.12)]),
                  let pngData = makeSyntheticPNGData(image: img1) else {
                assertTrue(false, "Failed to construct synthetic images")
                return
            }

            let decodedGIF = try TerminalSaverMediaDecoder.decodeImage(data: gifData)
            assertEqual(decodedGIF.frames.count, 2)
            let decodedPNG = try TerminalSaverMediaDecoder.decodeImage(data: pngData)
            assertEqual(decodedPNG.frames.count, 1)

            let gifURL = rootDir.url.appendingPathComponent("flame.gif")
            try gifData.write(to: gifURL)

            let imported = try store.importMedia(from: gifURL, currentConfig: TerminalSaverConfig())
            assertEqual(imported.config.mediaItems.count, 1)
            assertEqual(imported.item.fileExtension, "gif")
            assertTrue(imported.config.selectedSources.contains(.media(imported.item.id)))
            assertTrue(imported.config.isShuffleActive)
            let roundtrip = try store.readMediaData(for: imported.item)
            assertEqual(roundtrip, gifData)

            // Reject invalid image payload
            let corruptURL = rootDir.url.appendingPathComponent("corrupt.png")
            try Data("not-a-png".utf8).write(to: corruptURL)
            var rejectedCorrupt = false
            do {
                _ = try store.importMedia(from: corruptURL, currentConfig: imported.config)
            } catch {
                rejectedCorrupt = true
            }
            assertTrue(rejectedCorrupt)

            // Reject unsupported extension
            let badExtURL = rootDir.url.appendingPathComponent("payload.sh")
            try pngData.write(to: badExtURL)
            var rejectedExt = false
            do {
                _ = try store.importMedia(from: badExtURL, currentConfig: imported.config)
            } catch {
                rejectedExt = true
            }
            assertTrue(rejectedExt)

            // Reject symlink source file
            let linkURL = rootDir.url.appendingPathComponent("alias.gif")
            try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: gifURL)
            var rejectedSymlink = false
            do {
                _ = try store.importMedia(from: linkURL, currentConfig: imported.config)
            } catch {
                rejectedSymlink = true
            }
            assertTrue(rejectedSymlink)

            // Delete removes stored media cleanly and resets selected source
            let afterDelete = try store.deleteMedia(id: imported.item.id, currentConfig: imported.config)
            assertTrue(afterDelete.mediaItems.isEmpty)
            assertEqual(afterDelete.selectedSource, .builtIn(.bonfire))
            assertFalse(afterDelete.selectedSources.contains(.media(imported.item.id)))
            assertFalse(afterDelete.isShuffleActive)
        }

        harness.test("Shell integrator is idempotent, restores byte-for-byte on uninstall, and rejects symlinks") {
            let tempHome = try SecureDirectory.temporary()
            defer {
                try? FileManager.default.removeItem(at: tempHome.url)
            }

            let helper = "/Applications/Yeoman.app/Contents/Helpers/YeomanTermSaver"
            let originalZshrc = "export PATH=\"/usr/local/bin:$PATH\"\nalias ll='ls -la'\n"
            let zshrcURL = TerminalSaverShellIntegrator.configURL(for: .zsh, homeDirectoryURL: tempHome.url)
            try Data(originalZshrc.utf8).write(to: zshrcURL)

            try TerminalSaverShellIntegrator.install(target: .zsh, helperPath: helper, timeoutSeconds: 90, homeDirectoryURL: tempHome.url)
            assertTrue(TerminalSaverShellIntegrator.status(for: .zsh, homeDirectoryURL: tempHome.url).isInstalled)

            // Backup preserves original pre-install file and is never overwritten on second install
            let backupURL = URL(fileURLWithPath: zshrcURL.path + ".yeoman.bak")
            assertEqual(try String(contentsOf: backupURL, encoding: .utf8), originalZshrc)

            // Second install updates timeout in place without duplicating markers
            try TerminalSaverShellIntegrator.install(target: .zsh, helperPath: helper, timeoutSeconds: 180, homeDirectoryURL: tempHome.url)
            let updatedContent = try String(contentsOf: zshrcURL, encoding: .utf8)
            assertEqual(updatedContent.components(separatedBy: TerminalSaverShellIntegrator.startMarker).count - 1, 1)
            assertTrue(updatedContent.contains("TMOUT=180"))
            assertEqual(try String(contentsOf: backupURL, encoding: .utf8), originalZshrc)

            // Uninstall restores exact original content
            try TerminalSaverShellIntegrator.uninstall(target: .zsh, homeDirectoryURL: tempHome.url)
            assertFalse(TerminalSaverShellIntegrator.status(for: .zsh, homeDirectoryURL: tempHome.url).isInstalled)
            assertEqual(try String(contentsOf: zshrcURL, encoding: .utf8), originalZshrc)

            // Bash, Fish, and tmux install & uninstall cleanly
            for target in [TerminalShellTarget.bash, .fish, .tmux] {
                try TerminalSaverShellIntegrator.install(target: target, helperPath: helper, timeoutSeconds: 120, homeDirectoryURL: tempHome.url)
                assertTrue(TerminalSaverShellIntegrator.status(for: target, homeDirectoryURL: tempHome.url).isInstalled)
                try TerminalSaverShellIntegrator.uninstall(target: target, homeDirectoryURL: tempHome.url)
                assertFalse(TerminalSaverShellIntegrator.status(for: target, homeDirectoryURL: tempHome.url).isInstalled)
            }

            // Reject symlinked target config
            let realTarget = tempHome.url.appendingPathComponent("real_tmux.conf")
            try Data("set -g mouse on\n".utf8).write(to: realTarget)
            let tmuxURL = TerminalSaverShellIntegrator.configURL(for: .tmux, homeDirectoryURL: tempHome.url)
            try? FileManager.default.removeItem(at: tmuxURL)
            try FileManager.default.createSymbolicLink(at: tmuxURL, withDestinationURL: realTarget)
            var rejectedSymlink = false
            do {
                try TerminalSaverShellIntegrator.install(target: .tmux, helperPath: helper, timeoutSeconds: 120, homeDirectoryURL: tempHome.url)
            } catch {
                rejectedSymlink = true
            }
            assertTrue(rejectedSymlink)
            assertEqual(try String(contentsOf: realTarget, encoding: .utf8), "set -g mouse on\n")
        }

        harness.test("ASCIIRenderEngine respects contentBounds letterbox bars, darkFloor, and gamma without background filters") {
            let cols = 16, rows = 10
            var red = [Float](repeating: 0, count: cols * rows)
            var green = [Float](repeating: 0, count: cols * rows)
            var blue = [Float](repeating: 0, count: cols * rows)

            let bounds = ASCIIContentBounds(minX: 2, maxX: 14, minY: 0, maxY: 10)
            for y in 0..<rows {
                for x in 0..<cols {
                    let idx = y * cols + x
                    let isSubject = (x >= 6 && x <= 9 && y >= 3 && y <= 6)
                    let val: Float = isSubject ? 0.95 : 0.12
                    red[idx] = val; green[idx] = val; blue[idx] = val
                }
            }
            let grid = ASCIIPixelGrid(columns: cols, rows: rows, red: red, green: green, blue: blue, contentBounds: bounds)
            let rendered = ASCIIRenderEngine.render(
                grid: grid,
                settings: ASCIIRenderSettings(style: .filigree, edgeDetail: 0.6, darkFloor: 0.20, gamma: 2.2)
            )
            assertTrue(rendered[0, 5].isBlank, "Cells outside contentBounds remain blank")
            assertTrue(rendered[3, 1].isBlank, "Dark pixels below darkFloor become blank negative space")
            assertFalse(rendered[7, 4].isBlank, "Bright subject inside contentBounds renders cleanly")
            assertFalse(rendered[6, 4].isBlank, "Sobel boundary contour renders cleanly")
        }

        harness.test("Legacy TerminalSaverConfig JSON ignores removed filter keys and migrates playbackMode/shufflePool") {
            let legacyWithFilters = Data("""
            {"idleTimeoutSeconds":90,"isEnabled":true,"style":"unicodeStrokes","colorPreset":"amber","fitMode":"cover","backgroundFilter":"dominantColor","backgroundReduction":0.7,"playbackMode":"shuffle","mediaItems":[{"id":"11111111-1111-1111-1111-111111111111","displayName":"OldClip","fileExtension":"mp4","byteCount":2048,"addedAt":750000000},{"id":"22222222-2222-2222-2222-222222222222","displayName":"CustomClip","fileExtension":"gif","byteCount":1024,"addedAt":750000000,"style":"classicDense","colorPreset":"bloodMoon","fitMode":"contain"}]}
            """.utf8)
            let decoded = try JSONDecoder().decode(TerminalSaverConfig.self, from: legacyWithFilters)
            assertEqual(decoded.idleTimeoutSeconds, 90)
            assertEqual(decoded.selectedSources, decoded.allSources)
            assertTrue(decoded.isShuffleActive)
            assertEqual(decoded.mediaItems.count, 2)
            assertEqual(decoded.mediaItems[0].style, .unicodeStrokes)
            assertEqual(decoded.mediaItems[0].colorPreset, .amber)
            assertEqual(decoded.mediaItems[0].fitMode, .cover)
            assertEqual(decoded.mediaItems[1].style, .classicDense)
            assertEqual(decoded.mediaItems[1].colorPreset, .bloodMoon)
            assertEqual(decoded.mediaItems[1].fitMode, .contain)

            let legacyPoolJSON = Data(#"{"shufflePool":[{"builtIn":{"_0":"moonlitRain"}},{"builtIn":{"_0":"windMeadow"}}]}"#.utf8)
            let decodedPool = try JSONDecoder().decode(TerminalSaverConfig.self, from: legacyPoolJSON)
            assertEqual(decodedPool.selectedSources, [.builtIn(.bouncingDVD), .builtIn(.windMeadow)])
            assertTrue(decodedPool.isShuffleActive)

            struct LegacySingleV1: Encodable {
                let playbackMode: String
                let selectedSource: TerminalSaverSource
            }
            let legacySingleJSON = try JSONEncoder().encode(
                LegacySingleV1(playbackMode: "single", selectedSource: .builtIn(.starfield))
            )
            let decodedSingle = try JSONDecoder().decode(TerminalSaverConfig.self, from: legacySingleJSON)
            assertEqual(decodedSingle.selectedSource, .builtIn(.starfield))
            assertEqual(decodedSingle.effectiveSelectedSources, [.builtIn(.starfield)])
            assertFalse(decodedSingle.isShuffleActive)
        }

        harness.test("Multi-select sources sanitization deduplicates, prunes missing media, and falls back when empty") {
            let keptItem = TerminalSaverMediaItem(displayName: "kept", fileExtension: "gif", byteCount: 512)
            let missingID = UUID()
            let config = TerminalSaverConfig(
                selectedSource: .builtIn(.bouncingDVD),
                selectedSources: [
                    .builtIn(.bouncingDVD),
                    .media(missingID),
                    .builtIn(.bouncingDVD),
                    .media(keptItem.id),
                    .media(keptItem.id)
                ],
                mediaItems: [keptItem]
            )
            let clean = config.sanitized()
            assertEqual(clean.selectedSources, [.builtIn(.bouncingDVD), .media(keptItem.id)])
            assertEqual(clean.effectiveSelectedSources, [.builtIn(.bouncingDVD), .media(keptItem.id)])
            assertTrue(clean.isShuffleActive)

            let fallback = TerminalSaverConfig(
                selectedSource: .builtIn(.windMeadow),
                selectedSources: [.media(missingID)]
            ).sanitized()
            assertEqual(fallback.selectedSources, [.builtIn(.windMeadow)])
            assertFalse(fallback.isShuffleActive)
        }

        harness.test("TerminalSaverRotationQueue repeats the exact same permutation across cycle boundaries") {
            struct SeededLCG: RandomNumberGenerator {
                var state: UInt64
                mutating func next() -> UInt64 {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    return state
                }
            }

            let pool: [TerminalSaverSource] = [
                .builtIn(.bonfire),
                .builtIn(.bouncingDVD),
                .builtIn(.windMeadow)
            ]
            var queue = TerminalSaverRotationQueue(pool: pool + [.builtIn(.bonfire)])
            assertEqual(queue.poolCount, 3)

            var rng = SeededLCG(state: 0x1234_5678_9ABC_DEF0)
            var history: [TerminalSaverSource] = []
            for _ in 0..<30 {
                history.append(queue.next(using: &rng))
            }

            let firstCycle = Array(history.prefix(pool.count))
            assertEqual(Set(firstCycle), Set(pool))
            for cycleStart in stride(from: pool.count, to: history.count, by: pool.count) {
                assertEqual(Array(history[cycleStart..<(cycleStart + pool.count)]), firstCycle)
            }
            // No back-to-back duplicates anywhere, including across cycle boundaries
            for i in 1..<history.count {
                assertTrue(history[i] != history[i - 1], "Consecutive duplicate at index \(i)")
            }

            var emptyQueue = TerminalSaverRotationQueue(pool: [])
            assertEqual(emptyQueue.poolCount, 1)
            assertEqual(emptyQueue.next(using: &rng), .builtIn(.bonfire))
        }

        harness.test("Closing Yeoman flushes every Terminal Saver setting without switching the helper off") {
            let root = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: root.url) }
            let store = TerminalSaverMediaStore(rootDirectoryURL: root.url)
            let defaults = isolatedDefaults()
            defaults.set(true, forKey: "terminal_saver_module_is_enabled")
            defaults.set(true, forKey: "terminal_saver_shows_dedicated_status_item")

            guard let image = makeSolidCGImage(width: 12, height: 12, fill: { _, _ in (40, 120, 225) }),
                  let gif = makeSyntheticGIFData(frames: [(image, 0.08), (image, 0.1)]) else {
                throw SecurityFailure.rejected("Unable to create the settings test media")
            }
            let file = root.url.appendingPathComponent("test.gif")
            try gif.write(to: file)
            let imported = try store.importMedia(from: file, currentConfig: TerminalSaverConfig())
            var baseline = imported.config
            baseline.selectedSource = .builtIn(.bonfire)
            try store.saveConfig(baseline)

            let manager = TerminalSaverManager(store: store, shellHomeDirectoryURL: root.url)
            let module = TerminalSaverModule(manager: manager, defaults: defaults)
            assertTrue(module.isEnabled && module.showsDedicatedStatusItem)
            manager.installShell(.zsh)
            manager.updateConfig { config in
                config.idleTimeoutSeconds = 437
                config.framesPerSecond = 27
                config.edgeDetail = 0.63
                config.darkFloor = 0.22
                config.gamma = 1.9
                config.startAnimation = .iris
                config.startAnimationSpeed = 0.4
                config.wakeAnimation = .glitch
                config.wakeAnimationSpeed = 1.3
                config.transitionAnimation = .wipe
                config.transitionAnimationSpeed = 0.7
                config.previousKey = .character("h")
                config.nextKey = .character("l")
                config.autoAdvance = TerminalSaverAutoAdvanceSettings(mode: .time, durationSeconds: 45)
                config.selectedSource = .media(imported.item.id)
                config.selectedSources = [.builtIn(.spinningDonut), config.selectedSource, .builtIn(.bouncingDVD)]
                config[settingsFor: .spinningDonut] = TerminalSaverSceneSettings(playbackSpeed: 1.7, colorPreset: .amber, style: .unicodeStrokes)
                config[settingsFor: .bouncingDVD] = TerminalSaverSceneSettings(playbackSpeed: 0.5, colorPreset: .moonlit)
                config.mediaItems[0].style = .classicDense
                config.mediaItems[0].colorPreset = .bloodMoon
                config.mediaItems[0].fitMode = .contain
                config.mediaItems[0].playbackSpeed = 0.8
                config.mediaItems[0].removeBackground = true
                config.mediaItems[0].pingPongLoop = true
            }
            let expected = manager.config
            assertEqual(try store.loadConfig().idleTimeoutSeconds, baseline.idleTimeoutSeconds)
            module.stop()

            let reopened = TerminalSaverMediaStore(rootDirectoryURL: root.url)
            let saved = try reopened.loadConfig()
            assertTrue(saved.isEnabled)
            assertEqual(saved, expected)
            assertEqual(try reopened.readMediaData(for: imported.item), gif)
            assertTrue(TerminalSaverShellIntegrator.status(for: .zsh, homeDirectoryURL: root.url).isInstalled)
            let rc = TerminalSaverShellIntegrator.configURL(for: .zsh, homeDirectoryURL: root.url)
            assertTrue(try String(contentsOf: rc, encoding: .utf8).contains("TMOUT=437"))
        }

        harness.test("An unreadable Terminal Saver configuration survives edits and shutdown byte for byte") {
            let root = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: root.url) }
            let directory = try root.child("TerminalSaver", create: true)
            let malformed = Data(#"{"idleTimeoutSeconds":"broken","isEnabled":true}"#.utf8)
            try directory.write(malformed, name: "config.json")
            let store = TerminalSaverMediaStore(rootDirectoryURL: root.url)
            let manager = TerminalSaverManager(store: store, shellHomeDirectoryURL: root.url)
            let defaults = isolatedDefaults()
            defaults.set(true, forKey: "terminal_saver_module_is_enabled")
            let module = TerminalSaverModule(manager: manager, defaults: defaults)
            manager.updateConfig { $0.idleTimeoutSeconds = 999 }
            manager.stopPreview()
            module.stop()

            assertFalse(manager.flushConfiguration())
            assertTrue(manager.lastError != nil)
            assertEqual(try directory.read("config.json", limit: 1024), malformed)
        }

        harness.test("A failed Terminal Saver save retains edits for retry without replacing the prior file") {
            let root = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: root.url) }
            let store = TerminalSaverMediaStore(rootDirectoryURL: root.url)
            try store.saveConfig(TerminalSaverConfig(idleTimeoutSeconds: 86))
            let directory = try root.child("TerminalSaver")
            let previous = try directory.read("config.json", limit: 65_536)
            let manager = TerminalSaverManager(store: store, shellHomeDirectoryURL: root.url)
            let target = directory.url.appendingPathComponent("config.json")
            let saved = directory.url.appendingPathComponent("prior-config.json")
            try FileManager.default.moveItem(at: target, to: saved)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)

            manager.updateConfig { $0.idleTimeoutSeconds = 183 }
            assertFalse(manager.flushConfiguration())
            assertEqual(manager.config.idleTimeoutSeconds, 183)
            assertEqual(try directory.read("prior-config.json", limit: 65_536), previous)
            try FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: saved, to: target)

            assertTrue(manager.flushConfiguration())
            assertEqual(try store.loadConfig().idleTimeoutSeconds, 183)
            assertEqual(manager.lastError, nil)
        }

        harness.test("Per-media settings stay isolated per video/item across roundtrip and rendering") {
            let itemA = TerminalSaverMediaItem(
                displayName: "ClipA",
                fileExtension: "mp4",
                byteCount: 2048,
                style: .filigree,
                colorPreset: .original,
                fitMode: .contain,
                pingPongLoop: true
            )
            let itemB = TerminalSaverMediaItem(
                displayName: "ClipB",
                fileExtension: "gif",
                byteCount: 1024,
                style: .unicodeStrokes,
                colorPreset: .bloodMoon,
                fitMode: .cover
            )
            let config = TerminalSaverConfig(
                selectedSource: .media(itemA.id),
                selectedSources: [.media(itemA.id), .media(itemB.id)],
                mediaItems: [itemA, itemB]
            )
            let data = try JSONEncoder().encode(config)
            let roundtripped = try JSONDecoder().decode(TerminalSaverConfig.self, from: data).sanitized()
            assertEqual(roundtripped.mediaItems.count, 2)
            assertEqual(roundtripped.mediaItems[0].style, .filigree)
            assertEqual(roundtripped.mediaItems[0].colorPreset, .original)
            assertEqual(roundtripped.mediaItems[0].fitMode, .contain)
            assertTrue(roundtripped.mediaItems[0].pingPongLoop)
            assertEqual(roundtripped.mediaItems[1].style, .unicodeStrokes)
            assertEqual(roundtripped.mediaItems[1].colorPreset, .bloodMoon)
            assertEqual(roundtripped.mediaItems[1].fitMode, .cover)
            assertFalse(roundtripped.mediaItems[1].pingPongLoop)

            guard let img = makeSolidCGImage(width: 16, height: 16, fill: { x, _ in x < 8 ? (40, 200, 120) : (220, 180, 90) }) else {
                assertTrue(false, "Failed to make synthetic test image")
                return
            }
            let frameA = ASCIIRenderEngine.render(
                image: img,
                columns: 24,
                rows: 10,
                settings: ASCIIRenderSettings(mediaItem: roundtripped.mediaItems[0], config: roundtripped)
            )
            let frameB = ASCIIRenderEngine.render(
                image: img,
                columns: 24,
                rows: 10,
                settings: ASCIIRenderSettings(mediaItem: roundtripped.mediaItems[1], config: roundtripped)
            )
            assertTrue(frameA != frameB, "Distinct per-media style/color/fit settings must render distinct frames")
        }

        harness.test("Built-in scene options persist independently with bounded speeds and legacy defaults") {
            let rootDir = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: rootDir.url) }
            let store = TerminalSaverMediaStore(rootDirectoryURL: rootDir.url)
            let moduleDir = try rootDir.child("TerminalSaver", create: true)
            try moduleDir.write(Data(#"{"isEnabled":true,"framesPerSecond":20}"#.utf8), name: "config.json")

            var config = try store.loadConfig()
            assertTrue(config.isEnabled)
            assertEqual(config.framesPerSecond, 20)
            for scene in TerminalSaverBuiltInScene.allCases {
                assertEqual(config[settingsFor: scene], TerminalSaverSceneSettings())
            }

            config[settingsFor: .bonfire] = TerminalSaverSceneSettings(
                playbackSpeed: 999, colorPreset: .amber, style: .ultraFine
            )
            config[settingsFor: .spinningDonut] = TerminalSaverSceneSettings(
                playbackSpeed: -1, colorPreset: .moonlit, style: .unicodeStrokes
            )
            config[settingsFor: .matrix].playbackSpeed = .nan
            try store.saveConfig(config)
            let saved = try store.loadConfig()
            assertEqual(saved[settingsFor: .bonfire], TerminalSaverSceneSettings(playbackSpeed: 2, colorPreset: .amber))
            assertEqual(saved[settingsFor: .spinningDonut], TerminalSaverSceneSettings(
                playbackSpeed: 0.1, colorPreset: .moonlit, style: .unicodeStrokes
            ))
            assertEqual(saved[settingsFor: .matrix], TerminalSaverSceneSettings())
            assertEqual(saved.effectiveSelectedSources, [.builtIn(.bonfire)])
        }

        harness.test("Former Rain selection, options and rotation decode as the Bouncing DVD Logo") {
            let legacyConfig = Data("""
                {
                  "selectedSource": {"builtIn":{"_0":"moonlitRain"}},
                  "selectedSources": [{"builtIn":{"_0":"moonlitRain"}},{"builtIn":{"_0":"starfield"}}],
                  "sceneSettings": ["moonlitRain",{"playbackSpeed":1.5,"colorPreset":"amber"}]
                }
                """.utf8)
            let config = try JSONDecoder().decode(TerminalSaverConfig.self, from: legacyConfig).sanitized()
            assertEqual(config.selectedSource, .builtIn(.bouncingDVD))
            assertEqual(config.effectiveSelectedSources, [.builtIn(.bouncingDVD), .builtIn(.starfield)])
            assertEqual(config[settingsFor: .bouncingDVD], TerminalSaverSceneSettings(playbackSpeed: 1.5, colorPreset: .amber))
            let saved = try JSONEncoder().encode(config)
            assertFalse(String(decoding: saved, as: UTF8.self).contains("moonlitRain"))
            assertEqual(try JSONDecoder().decode(TerminalSaverConfig.self, from: saved), config)

            let legacyRotation = Data(#"{"remaining":[{"builtIn":{"_0":"moonlitRain"}}]}"#.utf8)
            let rotation = try JSONDecoder().decode(TerminalSaverRotationState.self, from: legacyRotation)
            assertEqual(rotation.remaining, [.builtIn(.bouncingDVD)])
        }

        harness.test("DVD logo reflects off both terminal edges and changes color on impact") {
            func frame(_ time: Double) -> ASCIIFrame {
                TerminalSaverProceduralScenes.frame(scene: .bouncingDVD, columns: 11, rows: 5, time: time)
            }
            func occupiedColumns(_ frame: ASCIIFrame) -> [Int] {
                frame.cells.indices.filter { !frame.cells[$0].isBlank }.map { $0 % frame.columns }
            }
            func occupiedRows(_ frame: ASCIIFrame) -> [Int] {
                frame.cells.indices.filter { !frame.cells[$0].isBlank }.map { $0 / frame.columns }
            }
            let before = frame(0.25)
            let right = frame(0.5)
            let bottom = frame(0.6)
            let after = frame(0.85)
            assertEqual(occupiedColumns(frame(0)).min(), 0)
            assertEqual(occupiedRows(frame(0)).min(), 0)
            assertEqual(occupiedColumns(right).max(), right.columns - 1)
            assertEqual(occupiedRows(bottom).max(), bottom.rows - 1)
            assertTrue((occupiedColumns(after).max() ?? 0) < right.columns - 1)
            assertTrue((occupiedRows(after).max() ?? 0) < bottom.rows - 1)
            assertEqual(before.cells.filter { !$0.isBlank }.map(\.character), after.cells.filter { !$0.isBlank }.map(\.character))
            assertTrue(before.cells.first { !$0.isBlank }?.red != right.cells.first { !$0.isBlank }?.red)
        }

        harness.test("Built-in scene speed, palette and Donut style affect rendered playback") {
            let fast = TerminalSaverSceneSettings(playbackSpeed: 2)
            for scene in TerminalSaverBuiltInScene.allCases {
                let original = TerminalSaverProceduralScenes.frame(scene: scene, columns: 64, rows: 18, time: 1.5)
                let tinted = TerminalSaverProceduralScenes.frame(
                    scene: scene, columns: 64, rows: 18, time: 1.5,
                    settings: TerminalSaverSceneSettings(colorPreset: .amber)
                )
                assertEqual(tinted.cells.map(\.character), original.cells.map(\.character))
                assertTrue(tinted != original, "Palette should change the colors of \(scene)")
                assertTrue(tinted.cells.allSatisfy { $0.isBlank || ($0.red > $0.green && $0.green > $0.blue) })

                let spedUp = TerminalSaverProceduralScenes.frame(
                    scene: scene, columns: 64, rows: 18, time: fast.animationTime(0, advancingBy: 0.75)
                )
                assertEqual(spedUp, original)
                assertTrue(spedUp != TerminalSaverProceduralScenes.frame(
                    scene: scene, columns: 64, rows: 18, time: 0.75
                ))
            }

            let donut = TerminalSaverProceduralScenes.frame(scene: .spinningDonut, columns: 64, rows: 18, time: 1.5)
            let styledDonut = TerminalSaverProceduralScenes.frame(
                scene: .spinningDonut, columns: 64, rows: 18, time: 1.5,
                settings: TerminalSaverSceneSettings(style: .unicodeStrokes)
            )
            assertEqual(styledDonut.cells.map(\.isBlank), donut.cells.map(\.isBlank))
            assertTrue(styledDonut.cells.map(\.character) != donut.cells.map(\.character))
            let ramp = Set(ASCIIRenderStyle.unicodeStrokes.ramp)
            assertTrue(styledDonut.cells.allSatisfy { ramp.contains($0.character) })
        }

        harness.test("Playback speed policy bounds, delay calculation, supportsAnimation, and config roundtrip") {
            assertEqual(TerminalSaverPolicy.clampedSpeed(1.0), 1.0)
            assertEqual(TerminalSaverPolicy.clampedSpeed(9.0), TerminalSaverPolicy.playbackSpeedRange.upperBound)
            assertEqual(TerminalSaverPolicy.clampedSpeed(Double.nan), TerminalSaverPolicy.defaultPlaybackSpeed)
            assertEqual(TerminalSaverPolicy.clampedSpeed(-5.0), TerminalSaverPolicy.playbackSpeedRange.lowerBound)

            assertEqual(TerminalSaverPolicy.adjustedFrameDelay(0.1, speed: 2.0), 0.05)
            assertEqual(TerminalSaverPolicy.adjustedFrameDelay(0.1, speed: 0.1), 1.0)

            let gifItem = TerminalSaverMediaItem(displayName: "Loop", fileExtension: "gif", byteCount: 512, playbackSpeed: 1.6)
            let mp4Item = TerminalSaverMediaItem(displayName: "Clip", fileExtension: "mp4", byteCount: 1024, playbackSpeed: 99.0)
            let pngItem = TerminalSaverMediaItem(
                displayName: "Still", fileExtension: "png", byteCount: 256, playbackSpeed: Double.nan, pingPongLoop: true
            )
            assertEqual(mp4Item.fitMode, .cover, "New media items must default to .cover fit mode")
            assertTrue(gifItem.supportsAnimation)
            assertTrue(mp4Item.supportsAnimation)
            assertFalse(pngItem.supportsAnimation)

            let dirty = TerminalSaverConfig(mediaItems: [gifItem, mp4Item, pngItem])
            let clean = dirty.sanitized()
            assertEqual(clean.mediaItems[0].playbackSpeed, 1.6)
            assertEqual(clean.mediaItems[1].playbackSpeed, TerminalSaverPolicy.playbackSpeedRange.upperBound)
            assertEqual(clean.mediaItems[2].playbackSpeed, TerminalSaverPolicy.defaultPlaybackSpeed)
            assertFalse(clean.mediaItems[2].pingPongLoop)

            // Centered slider mapping puts 1.0x at 0.0, 0.1x at -1.0, and 2.0x at +1.0.
            assertEqual(TerminalSaverPolicy.speedSliderPosition(for: 0.1), -1.0)
            assertEqual(TerminalSaverPolicy.speedSliderPosition(for: 1.0), 0.0)
            assertEqual(TerminalSaverPolicy.speedSliderPosition(for: 2.0), 1.0)
            assertEqual(TerminalSaverPolicy.speedFromSliderPosition(-1.0), 0.1)
            assertEqual(TerminalSaverPolicy.speedFromSliderPosition(0.0), 1.0)
            assertEqual(TerminalSaverPolicy.speedFromSliderPosition(1.0), 2.0)
            assertEqual(TerminalSaverPolicy.speedFromSliderPosition(Double.nan), 1.0)
            assertEqual(TerminalSaverPolicy.speedFromSliderPosition(-5.0), 0.1)
            assertEqual(TerminalSaverPolicy.speedFromSliderPosition(5.0), 2.0)
            for step in 1...20 {
                let target = Double(step) / 10.0
                let pos = TerminalSaverPolicy.speedSliderPosition(for: target)
                assertEqual(TerminalSaverPolicy.speedFromSliderPosition(pos), target)
            }

            let legacyJSON = Data("""
            {"idleTimeoutSeconds":120,"playbackSpeed":2.5,"mediaItems":[{"id":"11111111-1111-1111-1111-111111111111","displayName":"NoSpeed","fileExtension":"gif","byteCount":128,"addedAt":750000000}]}
            """.utf8)
            let decoded = try JSONDecoder().decode(TerminalSaverConfig.self, from: legacyJSON)
            assertEqual(decoded.mediaItems.first?.playbackSpeed, 1.0)
            assertEqual(decoded.mediaItems.first?.pingPongLoop, false)
            assertEqual(decoded.startAnimation, .dissolve)
            assertEqual(decoded.startDurationMilliseconds, TerminalSaverPolicy.defaultStartDuration)
        }

        harness.test("Forward and reverse media loops play each turning frame once") {
            func indices(frameCount: Int, pingPong: Bool, steps: Int) -> [Int] {
                var cursor = TerminalSaverMediaCursor()
                return (0..<steps).map { _ in
                    let index = cursor.frameIndex
                    cursor.advance(frameCount: frameCount, pingPong: pingPong)
                    return index
                }
            }

            assertEqual(indices(frameCount: 4, pingPong: true, steps: 10), [0, 1, 2, 3, 2, 1, 0, 1, 2, 3])
            assertEqual(indices(frameCount: 4, pingPong: false, steps: 6), [0, 1, 2, 3, 0, 1])
            assertEqual(indices(frameCount: 2, pingPong: true, steps: 5), [0, 1, 0, 1, 0])
            assertEqual(indices(frameCount: 1, pingPong: true, steps: 3), [0, 0, 0])
            assertEqual(indices(frameCount: 0, pingPong: true, steps: 2), [0, 0])
        }

        harness.test("Timed advancement defaults to off and migrates the previous repetition setting") {
            let legacy = try JSONDecoder().decode(TerminalSaverConfig.self, from: Data("{}".utf8))
            assertEqual(legacy.autoAdvance.mode, .off)
            assertNil(legacy.autoAdvance.timeLimit)

            let previous = Data(#"{"autoAdvance":{"mode":"repetitions","durationSeconds":45,"repetitions":4}}"#.utf8)
            let migrated = try JSONDecoder().decode(TerminalSaverConfig.self, from: previous).sanitized()
            assertEqual(migrated.autoAdvance, .init(mode: .time, durationSeconds: 45))
            let saved = try JSONDecoder().decode(TerminalSaverConfig.self, from: JSONEncoder().encode(migrated))
            assertEqual(saved.autoAdvance.timeLimit, 45)

            let short = TerminalSaverConfig(autoAdvance: .init(mode: .time, durationSeconds: -1)).sanitized()
            assertEqual(short.autoAdvance.timeLimit, 5)
            let long = TerminalSaverConfig(autoAdvance: .init(mode: .time, durationSeconds: Int.max)).sanitized()
            assertEqual(long.autoAdvance.timeLimit, 600)
        }

        harness.test("Auto-Advance cutoff option defaults to finishLoop, roundtrips hardCut, and controls loop waiting") {
            let defaults = TerminalSaverAutoAdvanceSettings()
            assertEqual(defaults.cutoff, .finishLoop)
            assertTrue(defaults.waitsForMediaLoop)

            let missingCutoff = Data(#"{"mode":"time","durationSeconds":20}"#.utf8)
            let decodedMissing = try JSONDecoder().decode(TerminalSaverAutoAdvanceSettings.self, from: missingCutoff)
            assertEqual(decodedMissing.cutoff, .finishLoop)

            let invalidCutoff = Data(#"{"mode":"time","durationSeconds":20,"cutoff":"unknown"}"#.utf8)
            let decodedInvalid = try JSONDecoder().decode(TerminalSaverAutoAdvanceSettings.self, from: invalidCutoff)
            assertEqual(decodedInvalid.cutoff, .finishLoop)

            let hard = TerminalSaverAutoAdvanceSettings(mode: .time, durationSeconds: 15, cutoff: .hardCut)
            assertFalse(hard.waitsForMediaLoop)
            let cfgData = try JSONEncoder().encode(TerminalSaverConfig(autoAdvance: hard))
            let roundtrip = try JSONDecoder().decode(TerminalSaverConfig.self, from: cfgData).sanitized()
            assertEqual(roundtrip.autoAdvance, hard)

            let disabled = TerminalSaverAutoAdvanceSettings(mode: .off, durationSeconds: 15, cutoff: .hardCut)
            assertFalse(disabled.shouldAdvance(timeElapsed: true, hasMediaLoop: false, finishedMediaCycle: true))

            let finishLoop = TerminalSaverAutoAdvanceSettings(mode: .time, durationSeconds: 15, cutoff: .finishLoop)
            assertTrue(finishLoop.shouldAdvance(timeElapsed: true, hasMediaLoop: false, finishedMediaCycle: false))
            assertFalse(finishLoop.shouldAdvance(timeElapsed: true, hasMediaLoop: true, finishedMediaCycle: false))
            assertTrue(finishLoop.shouldAdvance(timeElapsed: true, hasMediaLoop: true, finishedMediaCycle: true))

            assertTrue(hard.shouldAdvance(timeElapsed: true, hasMediaLoop: false, finishedMediaCycle: false))
            assertTrue(hard.shouldAdvance(timeElapsed: true, hasMediaLoop: true, finishedMediaCycle: false))
            assertFalse(hard.shouldAdvance(timeElapsed: false, hasMediaLoop: true, finishedMediaCycle: true))

            let locManager = LocalizationManager(defaults: isolatedDefaults())
            for lang in [AppLanguage.german, .english, .spanish, .french] {
                for key in [
                    "terminal_saver.auto_advance_cutoff",
                    "terminal_saver.auto_advance_finish_loop",
                    "terminal_saver.auto_advance_hard_cut"
                ] {
                    let translated = locManager.localized(key, for: lang)
                    assertTrue(!translated.isEmpty && translated != key, "Missing localization for \(key) in \(lang)")
                }
            }
        }

        harness.test("Media playback reports the end of forward and forward-and-reverse cycles") {
            var forward = TerminalSaverMediaCursor()
            let forwardCycles = (1...9).filter { _ in forward.advance(frameCount: 4, pingPong: false) }
            assertEqual(forwardCycles, [4, 8])

            var backAndForth = TerminalSaverMediaCursor()
            let pingPongCycles = (1...13).filter { _ in backAndForth.advance(frameCount: 4, pingPong: true) }
            assertEqual(pingPongCycles, [6, 12])

            var still = TerminalSaverMediaCursor()
            assertFalse(still.advance(frameCount: 1, pingPong: false))
            assertFalse(still.advance(frameCount: 0, pingPong: true))
        }

        harness.test("Startup entry animations build up cleanly from blank to target and sanitize duration") {
            let target = TerminalSaverProceduralScenes.frame(scene: .bonfire, columns: 32, rows: 12, time: 0.8)
            for anim in TerminalWakeAnimation.allCases {
                let start = TerminalSaverWakeAnimations.entryFrame(target: target, animation: anim, progress: 0.0, seed: 42)
                if anim == .instant {
                    assertEqual(start, target)
                } else {
                    assertTrue(start.isBlank, "Entry animation \(anim) must start blank at progress 0.0")
                    let mid = TerminalSaverWakeAnimations.entryFrame(target: target, animation: anim, progress: 0.5, seed: 42)
                    assertEqual(mid.columns, target.columns)
                    assertEqual(mid.rows, target.rows)
                }
                let end = TerminalSaverWakeAnimations.entryFrame(target: target, animation: anim, progress: 1.0, seed: 42)
                assertEqual(end, target, "Entry animation \(anim) must match target at progress 1.0")
                let nanFrame = TerminalSaverWakeAnimations.entryFrame(target: target, animation: anim, progress: Double.nan, seed: 42)
                assertEqual(nanFrame, target)
            }

            assertEqual(TerminalSaverWakeAnimations.entryFrameCount(animation: .instant, durationMilliseconds: 500), 1)
            assertTrue(TerminalSaverWakeAnimations.entryFrameCount(animation: .dissolve, durationMilliseconds: 640) >= 20)

            let low = TerminalSaverConfig(startDurationMilliseconds: 10).sanitized()
            assertEqual(low.startDurationMilliseconds, TerminalSaverPolicy.startDurationRange.lowerBound)
            let high = TerminalSaverConfig(startDurationMilliseconds: 5000).sanitized()
            assertEqual(high.startDurationMilliseconds, TerminalSaverPolicy.startDurationRange.upperBound)
        }

        harness.test("Alpha-aware rendering clears transparent background and cutout APNG cache roundtrips and cleans up on delete") {
            let w = 24, h = 16
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0..<h {
                for x in 0..<w {
                    let off = (y * w + x) * 4
                    // Transparent border background vs dark+bright foreground subject in center
                    let isSubject = (x >= 8 && x <= 15 && y >= 4 && y <= 11)
                    if isSubject {
                        let bright = (x >= 11 && x <= 13)
                        let v: UInt8 = bright ? 230 : 12
                        rgba[off] = v; rgba[off + 1] = v; rgba[off + 2] = v; rgba[off + 3] = 255
                    } else {
                        rgba[off] = 0; rgba[off + 1] = 0; rgba[off + 2] = 0; rgba[off + 3] = 0
                    }
                }
            }
            let rawCG: CGImage? = rgba.withUnsafeMutableBytes { ptr in
                guard let ctx = CGContext(
                    data: ptr.baseAddress,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }
                return ctx.makeImage()
            }
            guard let subjectCG = rawCG,
                  let grid = ASCIIRenderEngine.sample(image: subjectCG, columns: 24, rows: 16, fitMode: .contain) else {
                assertTrue(false, "Failed to sample synthetic transparent image")
                return
            }
            let rendered = ASCIIRenderEngine.render(
                grid: grid,
                settings: ASCIIRenderSettings(style: .filigree, edgeDetail: 0.6, darkFloor: 0.25, gamma: 1.5)
            )
            assertTrue(rendered[2, 2].isBlank, "Transparent background cell must stay blank")
            assertFalse(rendered[8, 6].isBlank, "Dark foreground edge must remain visible after cutout")
            assertFalse(rendered[12, 6].isBlank, "Bright foreground interior must render cleanly")

            // Temporal smoothing damps single-frame spike while preserving steady foreground
            let m0 = TerminalSaverAlphaMask(width: 4, height: 1, bytes: [0, 240, 240, 0])
            let m1 = TerminalSaverAlphaMask(width: 4, height: 1, bytes: [200, 120, 240, 0])
            let m2 = TerminalSaverAlphaMask(width: 4, height: 1, bytes: [0, 240, 240, 0])
            let smoothed = TerminalSaverBackgroundRemover.smoothMasks([m0, m1, m2])
            assertEqual(smoothed[1].bytes[0], 100)
            assertEqual(smoothed[1].bytes[1], 180)
            assertEqual(smoothed[1].bytes[2], 240)

            // Cutout APNG cache write -> read -> decode preserves frame count, delays, and alpha, and deleteMedia deletes cutout cache
            guard let opaqueImg1 = makeSolidCGImage(width: w, height: h, fill: { x, _ in x >= 8 && x <= 15 ? (220, 120, 40) : (40, 120, 220) }),
                  let opaqueImg2 = makeSolidCGImage(width: w, height: h, fill: { x, _ in x >= 8 && x <= 15 ? (40, 220, 120) : (220, 40, 120) }),
                  let pngData = makeSyntheticPNGData(image: opaqueImg1) else {
                assertTrue(false, "Failed to construct synthetic opaque images")
                return
            }
            var maskBytes = [UInt8](repeating: 0, count: w * h)
            for y in 4..<12 {
                for x in 8..<16 {
                    maskBytes[y * w + x] = 255
                }
            }
            let mask = TerminalSaverAlphaMask(width: w, height: h, bytes: maskBytes)
            guard let cut1 = TerminalSaverBackgroundRemover.applyMask(mask, to: opaqueImg1),
                  let cut2 = TerminalSaverBackgroundRemover.applyMask(mask, to: opaqueImg2) else {
                assertTrue(false, "applyMask failed")
                return
            }
            let apngData = try TerminalSaverBackgroundRemover.encodeCutoutAPNG(frames: [
                TerminalSaverDecodedFrame(image: cut1, delaySeconds: 0.08),
                TerminalSaverDecodedFrame(image: cut2, delaySeconds: 0.14)
            ])
            let rootDir = try SecureDirectory.temporary()
            defer {
                try? FileManager.default.removeItem(at: rootDir.url)
            }
            let store = TerminalSaverMediaStore(rootDirectoryURL: rootDir.url)
            let srcURL = rootDir.url.appendingPathComponent("subject.png")
            try pngData.write(to: srcURL)
            let imported = try store.importMedia(from: srcURL, currentConfig: TerminalSaverConfig())
            assertFalse(imported.item.removeBackground)

            try store.writeCutoutData(apngData, for: imported.item)
            let readBack = try store.readCutoutData(for: imported.item)
            assertEqual(readBack, apngData)
            let decodedCache = try TerminalSaverMediaDecoder.decodeImage(data: readBack)
            assertEqual(decodedCache.frames.count, 2)
            let cachedGrid = ASCIIRenderEngine.sample(image: decodedCache.frames[0].image, columns: w, rows: h, fitMode: .contain)
            assertTrue((cachedGrid?.alpha[0] ?? 1.0) < 0.1, "Cached cutout background alpha must stay transparent")
            assertTrue((cachedGrid?.alpha[6 * w + 12] ?? 0.0) > 0.9, "Cached cutout foreground alpha must stay opaque")

            _ = try store.deleteMedia(id: imported.item.id, currentConfig: imported.config)
            var cacheGone = false
            do {
                _ = try store.readCutoutData(for: imported.item)
            } catch {
                cacheGone = true
            }
            assertTrue(cacheGone, "deleteMedia must remove cutout cache alongside media file")
        }

        harness.test("Persisted rotation repeats the same order across invocations") {
            let rootDir = try SecureDirectory.temporary()
            defer {
                try? FileManager.default.removeItem(at: rootDir.url)
            }
            let pool: [TerminalSaverSource] = [
                .builtIn(.bonfire),
                .builtIn(.bouncingDVD),
                .builtIn(.windMeadow)
            ]

            var picks: [TerminalSaverSource] = []
            for _ in 0..<9 {
                let store = TerminalSaverMediaStore(rootDirectoryURL: rootDir.url)
                picks.append(store.nextSource(for: pool))
            }

            let firstCycle = Array(picks.prefix(pool.count))
            assertEqual(Set(firstCycle), Set(pool))
            for cycleStart in stride(from: pool.count, to: picks.count, by: pool.count) {
                assertEqual(Array(picks[cycleStart..<(cycleStart + pool.count)]), firstCycle)
            }
            for idx in 1..<picks.count {
                assertTrue(picks[idx] != picks[idx - 1], "Consecutive activations must not repeat index \(idx)")
            }

            // Corrupt rotation_state.json recovers safely to a valid source
            let moduleDir = try SecureDirectory.boundaryRoot(rootDir.url).child("TerminalSaver", create: true)
            try moduleDir.write(Data("{corrupt-json".utf8), name: "rotation_state.json")
            let fallbackPick = TerminalSaverMediaStore(rootDirectoryURL: rootDir.url).nextSource(for: pool)
            assertTrue(pool.contains(fallbackPick))
        }

        harness.test("Adding new sources invalidates remaining rotation batch and reshuffles without back-to-back repeats") {
            let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            let initialPool: [TerminalSaverSource] = [.builtIn(.bonfire), .media(idA), .media(idB)]
            var queue = TerminalSaverRotationQueue(pool: initialPool)
            var prng = SeededGenerator(seed: 42)
            let first = queue.next(using: &prng)
            let savedState = queue.state

            let expandedPool = initialPool + [.media(idC)]
            var expandedQueue = TerminalSaverRotationQueue(pool: expandedPool, state: savedState)
            assertEqual(expandedQueue.state.pool, expandedPool)
            assertTrue(expandedQueue.state.remaining.isEmpty)
            assertEqual(expandedQueue.state.lastDelivered, first)

            let second = expandedQueue.next(using: &prng)
            assertTrue(second != first)
            assertEqual(expandedQueue.state.remaining.count, 3)

            expandedQueue.reshuffle(using: &prng)
            assertEqual(Set(expandedQueue.state.remaining), Set(expandedPool))
            assertEqual(expandedQueue.state.remaining.count, expandedPool.count)
            assertTrue(expandedQueue.state.remaining.first != second)

            // Legacy rotation_state.json without a "pool" field decodes safely and forces a reshuffle.
            let sampleEncoded = try JSONEncoder().encode(
                TerminalSaverRotationState(
                    pool: [.builtIn(.bonfire), .media(idA)],
                    remaining: [.builtIn(.bonfire)],
                    lastDelivered: .builtIn(.bonfire)
                )
            )
            var legacyDict = try JSONSerialization.jsonObject(with: sampleEncoded) as! [String: Any]
            legacyDict.removeValue(forKey: "pool")
            let legacyJSON = try JSONSerialization.data(withJSONObject: legacyDict)
            let decodedLegacy = try JSONDecoder().decode(TerminalSaverRotationState.self, from: legacyJSON)
            assertTrue(decodedLegacy.pool.isEmpty)
            var legacyQueue = TerminalSaverRotationQueue(pool: initialPool, state: decodedLegacy)
            assertTrue(legacyQueue.state.remaining.isEmpty)
            let afterLegacy = legacyQueue.next(using: &prng)
            assertTrue(afterLegacy != .builtIn(.bonfire))
        }

        harness.test("Sequential media imports persist a freshly shuffled rotation state") {
            let rootDir = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: rootDir.url) }

            guard let imgA = makeSolidCGImage(width: 8, height: 8, fill: { _, _ in (220, 40, 40) }),
                  let imgB = makeSolidCGImage(width: 8, height: 8, fill: { _, _ in (40, 80, 220) }),
                  let imgC = makeSolidCGImage(width: 8, height: 8, fill: { _, _ in (40, 200, 80) }),
                  let pngA = makeSyntheticPNGData(image: imgA),
                  let pngB = makeSyntheticPNGData(image: imgB),
                  let pngC = makeSyntheticPNGData(image: imgC) else {
                assertTrue(false, "Failed to build synthetic PNG inputs")
                return
            }

            let imageAURL = rootDir.url.appendingPathComponent("alpha.png")
            let imageBURL = rootDir.url.appendingPathComponent("beta.png")
            let imageCURL = rootDir.url.appendingPathComponent("gamma.png")
            try pngA.write(to: imageAURL)
            try pngB.write(to: imageBURL)
            try pngC.write(to: imageCURL)

            let store = TerminalSaverMediaStore(rootDirectoryURL: rootDir.url)
            var cfg = TerminalSaverConfig()
            let (cfg1, itemA) = try store.importMedia(from: imageAURL, currentConfig: cfg)
            cfg = cfg1
            let (cfg2, itemB) = try store.importMedia(from: imageBURL, currentConfig: cfg)
            cfg = cfg2
            let (cfg3, itemC) = try store.importMedia(from: imageCURL, currentConfig: cfg)
            cfg = cfg3

            let pool = cfg.effectiveSelectedSources
            let moduleDir = try SecureDirectory.boundaryRoot(rootDir.url).child("TerminalSaver", create: false)
            let rawStateData = try moduleDir.read("rotation_state.json", limit: 64 * 1024)
            let persisted = try JSONDecoder().decode(TerminalSaverRotationState.self, from: rawStateData)
            assertEqual(Set(persisted.pool), Set(pool))
            assertEqual(Set(persisted.remaining), Set(pool))
            assertEqual(persisted.remaining.count, pool.count)

            var drawn: [TerminalSaverSource] = []
            for _ in 0..<pool.count {
                drawn.append(store.nextSource(for: pool))
            }
            assertEqual(Set(drawn), Set([.builtIn(.bonfire), .media(itemA.id), .media(itemB.id), .media(itemC.id)]))

            store.reshuffleRotation(for: [.builtIn(.bonfire)])
            assertFalse((try? moduleDir.exists("rotation_state.json")) ?? true)
        }

        harness.test("Start and wake animation speed controls roundtrip across full range and clamp invalid inputs") {
            var cfg = TerminalSaverConfig()
            assertEqual(cfg.startAnimationSpeed, TerminalSaverPolicy.defaultTransitionSpeed)
            assertEqual(cfg.wakeAnimationSpeed, TerminalSaverPolicy.defaultTransitionSpeed)

            for step in 1...20 {
                let targetSpeed = Double(step) / 10.0
                cfg.startAnimationSpeed = targetSpeed
                assertEqual(cfg.startAnimationSpeed, targetSpeed, "Start speed \(targetSpeed)x must roundtrip")
                cfg.wakeAnimationSpeed = targetSpeed
                assertEqual(cfg.wakeAnimationSpeed, targetSpeed, "Wake speed \(targetSpeed)x must roundtrip")
            }

            cfg.startAnimationSpeed = 2.0
            cfg.wakeAnimationSpeed = 2.0
            assertEqual(cfg.startDurationMilliseconds, 210)
            assertEqual(cfg.wakeDurationMilliseconds, 140)
            let fastStartCount = TerminalSaverWakeAnimations.entryFrameCount(animation: .dissolve, durationMilliseconds: cfg.startDurationMilliseconds)
            let fastWakeCount = TerminalSaverWakeAnimations.frameCount(animation: .dissolve, durationMilliseconds: cfg.wakeDurationMilliseconds)

            cfg.startAnimationSpeed = 0.1
            cfg.wakeAnimationSpeed = 0.1
            assertEqual(cfg.startDurationMilliseconds, 4200)
            assertEqual(cfg.wakeDurationMilliseconds, 2800)
            let slowStartCount = TerminalSaverWakeAnimations.entryFrameCount(animation: .dissolve, durationMilliseconds: cfg.startDurationMilliseconds)
            let slowWakeCount = TerminalSaverWakeAnimations.frameCount(animation: .dissolve, durationMilliseconds: cfg.wakeDurationMilliseconds)
            assertTrue(slowStartCount > fastStartCount)
            assertTrue(slowWakeCount > fastWakeCount)

            assertEqual(TerminalSaverPolicy.clampedTransitionSpeed(Double.nan), TerminalSaverPolicy.defaultTransitionSpeed)
            assertEqual(TerminalSaverPolicy.clampedTransitionSpeed(-1.0), TerminalSaverPolicy.transitionSpeedRange.lowerBound)
            assertEqual(TerminalSaverPolicy.clampedTransitionSpeed(9.0), TerminalSaverPolicy.transitionSpeedRange.upperBound)

            cfg.startAnimationSpeed = Double.nan
            assertEqual(cfg.startDurationMilliseconds, TerminalSaverPolicy.defaultStartDuration)
            cfg.wakeAnimationSpeed = 99.0
            assertEqual(cfg.wakeAnimationSpeed, TerminalSaverPolicy.transitionSpeedRange.upperBound)
            assertEqual(cfg.wakeDurationMilliseconds, 140)

            var custom = TerminalSaverConfig()
            custom.startAnimationSpeed = 1.8
            custom.wakeAnimationSpeed = 0.5
            let encoded = try JSONEncoder().encode(custom)
            let decoded = try JSONDecoder().decode(TerminalSaverConfig.self, from: encoded).sanitized()
            assertEqual(decoded.startDurationMilliseconds, custom.startDurationMilliseconds)
            assertEqual(decoded.wakeDurationMilliseconds, custom.wakeDurationMilliseconds)
            assertEqual(decoded.startAnimationSpeed, 1.8)
            assertEqual(decoded.wakeAnimationSpeed, 0.5)
        }

        harness.test("Navigation key sanitization, config defaults, and transition speed roundtrip") {
            assertEqual(TerminalSaverKey.sanitized(.character("K"), fallback: .leftArrow), .character("k"))
            assertEqual(TerminalSaverKey.sanitized(.character(" "), fallback: .leftArrow), .leftArrow)
            assertEqual(TerminalSaverKey.sanitized(.character("ab"), fallback: .rightArrow), .rightArrow)
            assertEqual(TerminalSaverKey.sanitized(.character("\n"), fallback: .leftArrow), .leftArrow)
            assertEqual(TerminalSaverKey.leftArrow.displayLabel, "←")
            assertEqual(TerminalSaverKey.character("n").displayLabel, "N")

            let dupes = TerminalSaverConfig(previousKey: .space, nextKey: .space).sanitized()
            assertEqual(dupes.previousKey, .space)
            assertEqual(dupes.nextKey, .rightArrow)

            let sameRight = TerminalSaverConfig(previousKey: .rightArrow, nextKey: .rightArrow).sanitized()
            assertEqual(sameRight.previousKey, .rightArrow)
            assertEqual(sameRight.nextKey, .leftArrow)

            let legacyJSON = Data("{\"idleTimeoutSeconds\":90}".utf8)
            let legacyDecoded = try JSONDecoder().decode(TerminalSaverConfig.self, from: legacyJSON).sanitized()
            assertEqual(legacyDecoded.transitionAnimation, .slide)
            assertEqual(legacyDecoded.transitionDurationMilliseconds, TerminalSaverPolicy.defaultTransitionDuration)
            assertEqual(legacyDecoded.previousKey, .leftArrow)
            assertEqual(legacyDecoded.nextKey, .rightArrow)

            var speedCfg = TerminalSaverConfig()
            for step in 1...20 {
                let targetSpeed = Double(step) / 10.0
                speedCfg.transitionAnimationSpeed = targetSpeed
                assertEqual(speedCfg.transitionAnimationSpeed, targetSpeed, "Transition speed \(targetSpeed)x must roundtrip")
            }
            speedCfg.transitionDurationMilliseconds = 10
            assertEqual(speedCfg.sanitized().transitionDurationMilliseconds, TerminalSaverPolicy.transitionDurationRange.lowerBound)
            speedCfg.transitionDurationMilliseconds = 5000
            assertEqual(speedCfg.sanitized().transitionDurationMilliseconds, TerminalSaverPolicy.transitionDurationRange.upperBound)
        }

        harness.test("TerminalSaverInputParser classifies navigation keys vs wake sequences") {
            assertEqual(TerminalSaverInputParser.classify(bytes: [], previousKey: .leftArrow, nextKey: .rightArrow), .none)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x44], previousKey: .leftArrow, nextKey: .rightArrow), .previous)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x4F, 0x44], previousKey: .leftArrow, nextKey: .rightArrow), .previous)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x43], previousKey: .leftArrow, nextKey: .rightArrow), .next)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x4F, 0x43], previousKey: .leftArrow, nextKey: .rightArrow), .next)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x43, 0x1B, 0x5B, 0x44], previousKey: .leftArrow, nextKey: .rightArrow), .previous)

            // Up/down/PageUp/PageDown/Tab/Shift-Tab/Space/Characters
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x35, 0x7E], previousKey: .pageUp, nextKey: .pageDown), .previous)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x36, 0x7E], previousKey: .pageUp, nextKey: .pageDown), .next)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x5A], previousKey: .shiftTab, nextKey: .tab), .previous)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x09], previousKey: .shiftTab, nextKey: .tab), .next)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x4E], previousKey: .character("p"), nextKey: .character("n")), .next)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x70], previousKey: .character("p"), nextKey: .character("n")), .previous)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x20], previousKey: .leftArrow, nextKey: .space), .next)

            // Escape, Enter, Ctrl+C, unbound key, or mixed wake + nav -> wake
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B], previousKey: .leftArrow, nextKey: .rightArrow), .wake)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x0D], previousKey: .leftArrow, nextKey: .rightArrow), .wake)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x03], previousKey: .leftArrow, nextKey: .rightArrow), .wake)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x61], previousKey: .leftArrow, nextKey: .rightArrow), .wake)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x43, 0x20], previousKey: .leftArrow, nextKey: .rightArrow), .wake)

            // Terminal focus events are ignored so Electron/xterm focus changes do not wake or block navigation
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x49], previousKey: .leftArrow, nextKey: .rightArrow), .none)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x4F], previousKey: .leftArrow, nextKey: .rightArrow), .none)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x49, 0x1B, 0x5B, 0x43], previousKey: .leftArrow, nextKey: .rightArrow), .next)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x43, 0x1B, 0x5B, 0x4F], previousKey: .leftArrow, nextKey: .rightArrow), .next)
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x49, 0x20], previousKey: .leftArrow, nextKey: .rightArrow), .wake)

            // DSR acknowledgement (ESC [ 0 n) sets receivedDSRAck without waking or overriding navigation
            let dsrOnly = TerminalSaverInputParser.parse(bytes: [0x1B, 0x5B, 0x30, 0x6E], previousKey: .leftArrow, nextKey: .rightArrow)
            assertEqual(dsrOnly, TerminalSaverInputParseResult(action: .none, receivedDSRAck: true))
            assertEqual(TerminalSaverInputParser.classify(bytes: [0x1B, 0x5B, 0x30, 0x6E], previousKey: .leftArrow, nextKey: .rightArrow), .none)
            let dsrWithNext = TerminalSaverInputParser.parse(bytes: [0x1B, 0x5B, 0x30, 0x6E, 0x1B, 0x5B, 0x43], previousKey: .leftArrow, nextKey: .rightArrow)
            assertEqual(dsrWithNext, TerminalSaverInputParseResult(action: .next, receivedDSRAck: true))
            let dsrWithWake = TerminalSaverInputParser.parse(bytes: [0x1B, 0x5B, 0x30, 0x6E, 0x20], previousKey: .leftArrow, nextKey: .rightArrow)
            assertEqual(dsrWithWake, TerminalSaverInputParseResult(action: .wake, receivedDSRAck: true))
            assertTrue(TerminalSaverInputParser.needsMoreBytes([0x1B, 0x5B, 0x30]))
            assertFalse(TerminalSaverInputParser.needsMoreBytes([0x1B, 0x5B, 0x30, 0x6E]))

            // Incomplete escape detection
            assertTrue(TerminalSaverInputParser.needsMoreBytes([0x1B]))
            assertTrue(TerminalSaverInputParser.needsMoreBytes([0x1B, 0x5B]))
            assertTrue(TerminalSaverInputParser.needsMoreBytes([0x1B, 0x4F]))
            assertTrue(TerminalSaverInputParser.needsMoreBytes([0x1B, 0x5B, 0x35]))
            assertFalse(TerminalSaverInputParser.needsMoreBytes([0x1B, 0x5B, 0x35, 0x7E]))
            assertFalse(TerminalSaverInputParser.needsMoreBytes([0x1B, 0x5B, 0x44]))
            assertFalse(TerminalSaverInputParser.needsMoreBytes([]))
        }

        harness.test("Terminal input reads three or more fragments without waking on a navigation key") {
            var sockets = [Int32](repeating: -1, count: 2)
            guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &sockets) == 0 else {
                throw SecurityFailure.rejected("Could not create terminal input fixture")
            }
            defer { sockets.forEach { _ = close($0) } }

            func sendFragments(_ bytes: [UInt8]) throws {
                // Each datagram stays separate, so the reader needs one read per byte.
                for var byte in bytes {
                    guard Darwin.write(sockets[1], &byte, 1) == 1 else {
                        throw SecurityFailure.rejected("Could not send terminal input fragment")
                    }
                }
            }

            try sendFragments([0x1B, 0x5B, 0x43])
            assertEqual(TerminalSaverInputParser.readAction(from: sockets[0], previousKey: .leftArrow, nextKey: .rightArrow), .next)
            try sendFragments([0x1B, 0x4F, 0x44])
            assertEqual(TerminalSaverInputParser.readAction(from: sockets[0], previousKey: .leftArrow, nextKey: .rightArrow), .previous)
            try sendFragments([0x1B, 0x5B, 0x36, 0x7E])
            assertEqual(TerminalSaverInputParser.readAction(from: sockets[0], previousKey: .pageUp, nextKey: .pageDown), .next)
            try sendFragments([0x1B])
            assertEqual(TerminalSaverInputParser.readAction(from: sockets[0], previousKey: .leftArrow, nextKey: .rightArrow), .wake)
        }

        harness.test("Terminal Saver navigation wraps in both directions without changing the activation order") {
            let pool: [TerminalSaverSource] = [.builtIn(.bonfire), .builtIn(.bouncingDVD), .builtIn(.starfield), .builtIn(.windMeadow)]
            var generator = SeededGenerator(seed: 1337)
            var nav = TerminalSaverSessionNavigator(pool: pool, using: &generator)
            let first = nav.current
            let last = nav.stepBackward()
            assertEqual(nav.stepForward(), first)
            let rest = (1..<pool.count).compactMap { _ in nav.stepForward() }
            let cycle = [first] + rest
            assertEqual(Set(cycle), Set(pool))
            assertEqual(last, cycle.last)
            for _ in 0..<40 {
                for source in cycle { assertEqual(nav.stepForward(), source) }
            }
            assertEqual(nav.stepBackward(), cycle[cycle.count - 2])
            let resumed = TerminalSaverSessionNavigator(pool: pool, state: nav.state)
            assertEqual(resumed.current, cycle.last)

            var single = TerminalSaverSessionNavigator(pool: [.builtIn(.bonfire)], using: &generator)
            assertEqual(single.stepForward(), nil)
            assertEqual(single.stepBackward(), nil)
        }

        harness.test("Rotation preserves a legacy suffix and filters a removed scene without reordering survivors") {
            let a = TerminalSaverSource.builtIn(.bonfire)
            let b = TerminalSaverSource.builtIn(.bouncingDVD)
            let c = TerminalSaverSource.builtIn(.starfield)
            let d = TerminalSaverSource.builtIn(.matrix)
            let legacy = TerminalSaverRotationState(pool: [a, b, c, d], remaining: [d, a], lastDelivered: c)
            var migrated = TerminalSaverRotationQueue(pool: [a, b, c, d], state: legacy)
            assertEqual((0..<8).map { _ in migrated.next() }, [d, a, b, c, d, a, b, c])

            var reduced = TerminalSaverRotationQueue(pool: [a, b, c], state: migrated.state)
            assertEqual((0..<6).map { _ in reduced.next() }, [a, b, c, a, b, c])

            let malformed = TerminalSaverRotationState(pool: [a, b, c], remaining: [b, b], lastDelivered: a, order: [a, b, b])
            var recovered = TerminalSaverRotationQueue(pool: [a, b, c], state: malformed)
            let recoveredCycle = (0..<3).map { _ in recovered.next() }
            assertEqual(Set(recoveredCycle), Set([a, b, c]))
            assertTrue(recoveredCycle.first != a)
            assertEqual((0..<3).map { _ in recovered.next() }, recoveredCycle)
        }

        harness.test("A stale session cannot overwrite another activation's rotation progress") {
            let rootDir = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: rootDir.url) }
            let store = TerminalSaverMediaStore(rootDirectoryURL: rootDir.url)
            let pool: [TerminalSaverSource] = [.builtIn(.bonfire), .builtIn(.bouncingDVD), .builtIn(.starfield)]
            var first = store.startRotationSession(for: pool)
            let second = store.startRotationSession(for: pool)
            guard let original = first.savedState, let newer = second.savedState else {
                throw SecurityFailure.rejected("Expected persisted rotation states")
            }
            assertTrue(first.navigator.current != second.navigator.current)
            let preview = store.startRotationSession(for: pool, previewing: first.navigator.current)
            assertEqual(preview.savedState, nil)
            assertEqual(preview.navigator.state.order, newer.order)
            _ = first.navigator.stepBackward()
            assertFalse(store.saveRotationProgress(first.navigator.state, replacing: original))
            let third = store.startRotationSession(for: pool)
            assertEqual(Set([first.navigator.state.order[0], second.navigator.current, third.navigator.current]), Set(pool))
            assertEqual(third.navigator.state.order, newer.order)
        }

        harness.test("Transition animations respect direction, bounds, and instant completion") {
            let fromFrame = TerminalSaverProceduralScenes.frame(scene: .bonfire, columns: 30, rows: 12, time: 0.4)
            let toFrame = TerminalSaverProceduralScenes.frame(scene: .bouncingDVD, columns: 30, rows: 12, time: 1.1)

            for anim in TerminalTransitionAnimation.allCases {
                let startForward = TerminalSaverWakeAnimations.transitionFrame(
                    from: fromFrame,
                    to: toFrame,
                    animation: anim,
                    direction: .forward,
                    progress: 0.0,
                    seed: 7
                )
                let endForward = TerminalSaverWakeAnimations.transitionFrame(
                    from: fromFrame,
                    to: toFrame,
                    animation: anim,
                    direction: .forward,
                    progress: 1.0,
                    seed: 7
                )
                assertEqual(endForward, toFrame)
                assertEqual(
                    TerminalSaverWakeAnimations.transitionFrame(
                        from: fromFrame,
                        to: toFrame,
                        animation: anim,
                        direction: .forward,
                        progress: Double.nan,
                        seed: 7
                    ),
                    toFrame
                )
                if anim == .instant {
                    assertEqual(startForward, toFrame)
                } else {
                    assertEqual(startForward, fromFrame)
                }
            }

            let slideForwardMid = TerminalSaverWakeAnimations.transitionFrame(
                from: fromFrame,
                to: toFrame,
                animation: .slide,
                direction: .forward,
                progress: 0.5,
                seed: 7
            )
            let slideBackwardMid = TerminalSaverWakeAnimations.transitionFrame(
                from: fromFrame,
                to: toFrame,
                animation: .slide,
                direction: .backward,
                progress: 0.5,
                seed: 7
            )
            assertTrue(slideForwardMid != slideBackwardMid)

            let smallFrom = TerminalSaverProceduralScenes.frame(scene: .starfield, columns: 18, rows: 8, time: 0.2)
            let resizedMid = TerminalSaverWakeAnimations.transitionFrame(
                from: smallFrom,
                to: toFrame,
                animation: .wipe,
                direction: .forward,
                progress: 0.4,
                seed: 7
            )
            assertEqual(resizedMid.columns, toFrame.columns)
            assertEqual(resizedMid.rows, toFrame.rows)

            assertEqual(TerminalSaverWakeAnimations.transitionFrameCount(animation: .instant, durationMilliseconds: 400), 1)
            assertTrue(TerminalSaverWakeAnimations.transitionFrameCount(animation: .slide, durationMilliseconds: 480) >= 20)
        }

        harness.test("ASCII-interactive transitions mutate glyphs cleanly, stay directional, and stay printable ASCII") {
            let fromFrame = TerminalSaverProceduralScenes.frame(scene: .bonfire, columns: 30, rows: 12, time: 0.4)
            let toFrame = TerminalSaverProceduralScenes.frame(scene: .bouncingDVD, columns: 30, rows: 12, time: 1.1)
            let blankFrame = ASCIIFrame(columns: 30, rows: 12)
            let interactiveAnims: [TerminalTransitionAnimation] = [.swarm, .decode, .morph, .shatter, .rain, .ripple]

            for anim in interactiveAnims {
                let forwardMid = TerminalSaverWakeAnimations.transitionFrame(
                    from: fromFrame,
                    to: toFrame,
                    animation: anim,
                    direction: .forward,
                    progress: 0.5,
                    seed: 13
                )
                let backwardMid = TerminalSaverWakeAnimations.transitionFrame(
                    from: fromFrame,
                    to: toFrame,
                    animation: anim,
                    direction: .backward,
                    progress: 0.5,
                    seed: 13
                )
                assertFalse(forwardMid.isBlank, "\(anim.rawValue) midpoint should not be blank")
                assertTrue(forwardMid != fromFrame, "\(anim.rawValue) midpoint should differ from source frame")
                assertTrue(forwardMid != toFrame, "\(anim.rawValue) midpoint should differ from target frame")
                assertTrue(forwardMid != backwardMid, "\(anim.rawValue) forward and backward should differ")

                for p in [0.25, 0.5, 0.75] {
                    let frame = TerminalSaverWakeAnimations.transitionFrame(
                        from: fromFrame,
                        to: toFrame,
                        animation: anim,
                        direction: .forward,
                        progress: p,
                        seed: 13
                    )
                    for cell in frame.cells {
                        let scalars = Array(cell.character.unicodeScalars)
                        assertEqual(scalars.count, 1, "\(anim.rawValue) glyph must be a single scalar")
                        if let scalar = scalars.first {
                            assertTrue(
                                scalar.value >= 0x20 && scalar.value <= 0x7E,
                                "\(anim.rawValue) emitted non-printable-ASCII scalar \(scalar.value)"
                            )
                        }
                    }
                }

                let fromBlank = TerminalSaverWakeAnimations.transitionFrame(
                    from: blankFrame,
                    to: toFrame,
                    animation: anim,
                    direction: .forward,
                    progress: 0.5,
                    seed: 13
                )
                assertEqual(fromBlank.columns, toFrame.columns)
                assertEqual(fromBlank.rows, toFrame.rows)

                let toBlank = TerminalSaverWakeAnimations.transitionFrame(
                    from: fromFrame,
                    to: blankFrame,
                    animation: anim,
                    direction: .forward,
                    progress: 0.5,
                    seed: 13
                )
                assertEqual(toBlank.columns, blankFrame.columns)
                assertEqual(toBlank.rows, blankFrame.rows)

                let bothBlank = TerminalSaverWakeAnimations.transitionFrame(
                    from: blankFrame,
                    to: blankFrame,
                    animation: anim,
                    direction: .forward,
                    progress: 0.5,
                    seed: 13
                )
                assertTrue(bothBlank.isBlank, "\(anim.rawValue) between blank frames should stay blank")

                let smallFrom = TerminalSaverProceduralScenes.frame(scene: .starfield, columns: 18, rows: 8, time: 0.2)
                let resizedMid = TerminalSaverWakeAnimations.transitionFrame(
                    from: smallFrom,
                    to: toFrame,
                    animation: anim,
                    direction: .forward,
                    progress: 0.5,
                    seed: 13
                )
                assertEqual(resizedMid.columns, toFrame.columns)
                assertEqual(resizedMid.rows, toFrame.rows)
            }

            let transitionKeys = [
                "terminal_saver.transition_swarm",
                "terminal_saver.transition_decode",
                "terminal_saver.transition_morph",
                "terminal_saver.transition_shatter",
                "terminal_saver.transition_rain",
                "terminal_saver.transition_ripple"
            ]
            let locManager = LocalizationManager(defaults: isolatedDefaults())
            for lang in [AppLanguage.german, .english, .spanish, .french] {
                for key in transitionKeys {
                    let translated = locManager.localized(key, for: lang)
                    assertTrue(!translated.isEmpty && translated != key, "Missing localization for \(key) in \(lang)")
                }
            }
        }

        harness.test("Random mode and expanded ASCII-interactive start/wake animations work cleanly") {
            let base = TerminalSaverProceduralScenes.frame(scene: .bonfire, columns: 32, rows: 12, time: 0.8)
            let target = TerminalSaverProceduralScenes.frame(scene: .bouncingDVD, columns: 32, rows: 12, time: 1.4)
            let blank = ASCIIFrame(columns: 32, rows: 12)

            var transitionPicks: Set<TerminalTransitionAnimation> = []
            var wakePicks: Set<TerminalWakeAnimation> = []
            for s in 1...50 {
                let pickedTrans = TerminalTransitionAnimation.random.resolved(seed: s)
                assertTrue(TerminalTransitionAnimation.randomPool.contains(pickedTrans))
                assertTrue(pickedTrans != .random && pickedTrans != .instant)
                assertEqual(pickedTrans, TerminalTransitionAnimation.random.resolved(seed: s))
                transitionPicks.insert(pickedTrans)

                let pickedWake = TerminalWakeAnimation.random.resolved(seed: s)
                assertTrue(TerminalWakeAnimation.randomPool.contains(pickedWake))
                assertTrue(pickedWake != .random && pickedWake != .instant)
                assertEqual(pickedWake, TerminalWakeAnimation.random.resolved(seed: s))
                wakePicks.insert(pickedWake)
            }
            assertTrue(transitionPicks.count >= 4, "Expected Random transition pool variety, got \(transitionPicks.count)")
            assertTrue(wakePicks.count >= 4, "Expected Random wake pool variety, got \(wakePicks.count)")

            let newWakeCases: [TerminalWakeAnimation] = [.swarm, .decode, .morph, .shatter, .rain, .ripple, .random]
            for anim in newWakeCases {
                let wakeMid = TerminalSaverWakeAnimations.frame(base: base, animation: anim, progress: 0.5, seed: 19)
                assertFalse(wakeMid.isBlank, "Wake \(anim.rawValue) midpoint should not be blank")
                assertTrue(wakeMid != base, "Wake \(anim.rawValue) midpoint should mutate base frame")

                let entryMid = TerminalSaverWakeAnimations.entryFrame(target: target, animation: anim, progress: 0.5, seed: 19)
                assertFalse(entryMid.isBlank, "Entry \(anim.rawValue) midpoint should not be blank")
                assertTrue(entryMid != target, "Entry \(anim.rawValue) midpoint should differ from target frame")

                for p in [0.25, 0.5, 0.75] {
                    for frame in [
                        TerminalSaverWakeAnimations.frame(base: base, animation: anim, progress: p, seed: 19),
                        TerminalSaverWakeAnimations.entryFrame(target: target, animation: anim, progress: p, seed: 19)
                    ] {
                        for cell in frame.cells {
                            let scalars = Array(cell.character.unicodeScalars)
                            assertEqual(scalars.count, 1)
                            if let scalar = scalars.first {
                                assertTrue(
                                    scalar.value >= 0x20 && scalar.value <= 0x7E,
                                    "\(anim.rawValue) emitted non-printable-ASCII scalar \(scalar.value)"
                                )
                            }
                        }
                    }
                }

                assertTrue(
                    TerminalSaverWakeAnimations.frame(base: blank, animation: anim, progress: 0.5, seed: 19).isBlank,
                    "Wake \(anim.rawValue) on blank frame must stay blank"
                )
                assertTrue(
                    TerminalSaverWakeAnimations.entryFrame(target: blank, animation: anim, progress: 0.5, seed: 19).isBlank,
                    "Entry \(anim.rawValue) on blank frame must stay blank"
                )
            }

            var cfg = TerminalSaverConfig()
            cfg.startAnimation = .random
            cfg.wakeAnimation = .shatter
            cfg.transitionAnimation = .random
            let encoded = try JSONEncoder().encode(cfg)
            let decoded = try JSONDecoder().decode(TerminalSaverConfig.self, from: encoded)
            assertEqual(decoded.startAnimation, .random)
            assertEqual(decoded.wakeAnimation, .shatter)
            assertEqual(decoded.transitionAnimation, .random)

            let locManager = LocalizationManager(defaults: isolatedDefaults())
            for lang in [AppLanguage.german, .english, .spanish, .french] {
                let label = locManager.localized("terminal_saver.animation_random", for: lang)
                assertTrue(!label.isEmpty && label != "terminal_saver.animation_random", "Missing random localization in \(lang)")
            }
        }

        harness.test("MP4 video decoding succeeds within bounds and rejects corrupt payloads") {
            let rootDir = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: rootDir.url) }

            let mp4URL = try makeSyntheticMP4URL(in: rootDir.url, width: 64, height: 64, frameCount: 10, fps: 10)
            let decoded = try TerminalSaverMediaDecoder.decodeVideo(url: mp4URL, targetFPS: 10, maxEdge: 64, maxSamples: 30)
            assertTrue(decoded.frames.count >= 5, "Expected at least 5 decoded MP4 frames, got \(decoded.frames.count)")
            for frame in decoded.frames {
                assertTrue(frame.image.width <= 64 && frame.image.height <= 64)
            }
            let redLevels = try decoded.frames.map { frame in
                guard let grid = ASCIIRenderEngine.sample(image: frame.image, columns: 12, rows: 8, fitMode: .cover) else {
                    throw SecurityFailure.rejected("Unable to sample the synthetic video frame")
                }
                return grid.red[4 * 12 + 6]
            }
            assertTrue((redLevels.last ?? 0) - (redLevels.first ?? 0) > 0.4)
            assertTrue(zip(redLevels, redLevels.dropFirst()).allSatisfy { $0 <= $1 + 0.03 }, "Video frames must follow the requested timeline")

            let mp4Data = try Data(contentsOf: mp4URL)
            try TerminalSaverMediaDecoder.validate(data: mp4Data, fileExtension: "mp4")

            let corruptURL = rootDir.url.appendingPathComponent("corrupt.mp4")
            try Data("not-a-valid-mp4-stream".utf8).write(to: corruptURL)
            var corruptRejected = false
            do {
                _ = try TerminalSaverMediaDecoder.decodeVideo(url: corruptURL, targetFPS: 10, maxEdge: 64, maxSamples: 10)
            } catch {
                corruptRejected = true
            }
            assertTrue(corruptRejected, "Corrupt MP4 must fail closed")
        }

        harness.test("Bonfire flame stays centered without horizontal bars across outer screen edges") {
            let sizes = [(70, 20), (120, 36), (160, 45)]
            let times = [0.0, 0.7, 2.3]
            for (cols, rows) in sizes {
                for t in times {
                    let frame = TerminalSaverProceduralScenes.frame(scene: .bonfire, columns: cols, rows: rows, time: t)
                    for y in 0..<(rows - 1) {
                        assertTrue(frame[0, y].isBlank, "Left edge x=0 row \(y) must stay blank for \(cols)x\(rows) t=\(t)")
                        assertTrue(frame[1, y].isBlank, "Left edge x=1 row \(y) must stay blank for \(cols)x\(rows) t=\(t)")
                        assertTrue(frame[cols - 2, y].isBlank, "Right edge x=\(cols - 2) row \(y) must stay blank for \(cols)x\(rows) t=\(t)")
                        assertTrue(frame[cols - 1, y].isBlank, "Right edge x=\(cols - 1) row \(y) must stay blank for \(cols)x\(rows) t=\(t)")
                    }
                    let baseRow = rows - 2
                    let center = cols / 2
                    let hasCenterFlame = ((center - 2)...(center + 2)).contains { !frame[$0, baseRow].isBlank }
                    assertTrue(hasCenterFlame, "Bonfire core should render glyphs at base center for \(cols)x\(rows) t=\(t)")
                }
            }
        }

        harness.test("Endless classic scenes (Matrix, Game of Life, Pipes, 3D Donut) animate, stay bounded, and avoid block glyphs") {
            let newScenes: [TerminalSaverBuiltInScene] = [.matrix, .gameOfLife, .pipes, .spinningDonut]
            let gridSizes = [(10, 5), (64, 18), (120, 36)]
            let solidBlocks: Set<Character> = ["█", "▓", "▒", "░"]

            for scene in newScenes {
                for (cols, rows) in gridSizes {
                    for time in [0.0, 1.25, 5.0] {
                        let frame = TerminalSaverProceduralScenes.frame(scene: scene, columns: cols, rows: rows, time: time)
                        assertEqual(frame.columns, cols)
                        assertEqual(frame.rows, rows)
                        assertFalse(frame.isBlank, "\(scene) must be non-blank at \(cols)x\(rows) t=\(time)")
                    }
                    for invalidTime in [-1.0, Double.nan, Double.infinity, 1e12] {
                        let frame = TerminalSaverProceduralScenes.frame(scene: scene, columns: cols, rows: rows, time: invalidTime)
                        assertEqual(frame.columns, cols)
                        assertEqual(frame.rows, rows)
                        assertFalse(frame.isBlank, "\(scene) must handle t=\(invalidTime) at \(cols)x\(rows)")
                    }
                }

                let startFrame = TerminalSaverProceduralScenes.frame(scene: scene, columns: 64, rows: 18, time: 0.0)
                let laterFrame = TerminalSaverProceduralScenes.frame(scene: scene, columns: 64, rows: 18, time: 1.5)
                assertTrue(startFrame != laterFrame, "\(scene) must visually animate over time")
            }

            // Ensure zero solid block characters across all built-in scenes.
            for scene in TerminalSaverBuiltInScene.allCases {
                let frame = TerminalSaverProceduralScenes.frame(scene: scene, columns: 80, rows: 24, time: 2.2)
                for cell in frame.cells {
                    assertFalse(solidBlocks.contains(cell.character), "Built-in scene \(scene) must not emit block glyph \(cell.character)")
                }
            }

            // Verify Game of Life remains active across 80 sequential generations without dying out.
            for gen in 0..<80 {
                let lifeFrame = TerminalSaverProceduralScenes.frame(
                    scene: .gameOfLife,
                    columns: 40,
                    rows: 14,
                    time: Double(gen) / 8.0
                )
                assertFalse(lifeFrame.isBlank, "Game of Life must stay alive at generation \(gen)")
            }

            // Verify concurrent Game of Life and Pipes rendering across multiple grid sizes is race-free.
            let concurrentSizes = [(24, 10), (48, 16), (64, 18), (80, 22), (96, 26)]
            DispatchQueue.concurrentPerform(iterations: 32) { iter in
                let size = concurrentSizes[iter % concurrentSizes.count]
                let scene: TerminalSaverBuiltInScene = (iter % 2 == 0) ? .gameOfLife : .pipes
                let frame = TerminalSaverProceduralScenes.frame(
                    scene: scene,
                    columns: size.0,
                    rows: size.1,
                    time: Double(iter) * 0.125
                )
                assertEqual(frame.columns, size.0)
                assertEqual(frame.rows, size.1)
                assertFalse(frame.isBlank)
            }

            // Verify localizations for all 4 new scene keys.
            let l10nManager = LocalizationManager(defaults: isolatedDefaults())
            let sceneKeys = [
                "terminal_saver.scene_matrix",
                "terminal_saver.scene_game_of_life",
                "terminal_saver.scene_pipes",
                "terminal_saver.scene_spinning_donut"
            ]
            for lang in [AppLanguage.german, .english, .spanish, .french] {
                for key in sceneKeys {
                    let text = l10nManager.localized(key, for: lang)
                    assertFalse(text.isEmpty || text == key, "Missing localization for \(key) in \(lang)")
                }
            }
        }

        harness.test("TerminalSaverManager.importMedia returns imported ID and previews new media") {
            let root = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: root.url) }
            let store = TerminalSaverMediaStore(rootDirectoryURL: root.url)
            let manager = TerminalSaverManager(store: store, shellHomeDirectoryURL: root.url)

            guard let image = makeSolidCGImage(width: 12, height: 12, fill: { _, _ in (90, 180, 240) }),
                  let gif = makeSyntheticGIFData(frames: [(image, 0.08), (image, 0.08)]) else {
                throw SecurityFailure.rejected("Unable to create synthetic GIF")
            }
            let validURL = root.url.appendingPathComponent("newly-added.gif")
            try gif.write(to: validURL)

            let importedID = manager.importMedia(urls: [validURL])
            assertTrue(importedID != nil, "importMedia should return the newly added media ID")
            assertEqual(importedID, manager.config.mediaItems.last?.id)
            if let importedID {
                assertEqual(manager.previewedSource, .media(importedID))
            }

            let invalidURL = root.url.appendingPathComponent("bad.sh")
            try Data("echo bad".utf8).write(to: invalidURL)
            let rejectedID = manager.importMedia(urls: [invalidURL])
            assertEqual(rejectedID, nil, "Invalid media import should return nil")
            if let importedID {
                assertEqual(manager.previewedSource, .media(importedID))
            }
            assertTrue(manager.lastError != nil)
        }

        harness.test("TerminalSaverPreviewModel decouples preview ticks from manager objectWillChange and deduplicates identical frames") {
            let root = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: root.url) }
            let store = TerminalSaverMediaStore(rootDirectoryURL: root.url)
            let manager = TerminalSaverManager(store: store, shellHomeDirectoryURL: root.url)

            var objectChangeCount = 0
            let cancellable = manager.objectWillChange.sink { _ in
                objectChangeCount += 1
            }

            var callbackFrames: [ASCIIFrame] = []
            manager.previewModel.onFrameChanged = { frame in
                callbackFrames.append(frame)
            }

            var frame1 = ASCIIFrame(columns: 16, rows: 6)
            frame1.put(3, 2, "*", 120, 220, 255)
            var frame2 = frame1
            frame2.put(4, 2, "+", 255, 160, 80)

            manager.previewModel.update(frame1)
            assertEqual(callbackFrames.count, 1)
            assertEqual(objectChangeCount, 0)

            manager.previewModel.update(frame1)
            assertEqual(callbackFrames.count, 1, "Identical frames must not trigger redundant redraws")
            assertEqual(objectChangeCount, 0)

            manager.previewModel.update(frame2)
            assertEqual(callbackFrames.count, 2)
            assertEqual(manager.previewFrame, frame2)
            assertEqual(objectChangeCount, 0)
            cancellable.cancel()
        }

        harness.test("TerminalSaverManager supports sanitized clip renaming, stable preview on toggle, and inspector localizations") {
            let root = try SecureDirectory.temporary()
            defer { try? FileManager.default.removeItem(at: root.url) }
            let store = TerminalSaverMediaStore(rootDirectoryURL: root.url)
            let manager = TerminalSaverManager(store: store, shellHomeDirectoryURL: root.url)

            guard let image = makeSolidCGImage(width: 10, height: 10, fill: { _, _ in (120, 200, 140) }),
                  let gif = makeSyntheticGIFData(frames: [(image, 0.08), (image, 0.08)]) else {
                throw SecurityFailure.rejected("Unable to create synthetic GIF")
            }
            let fileURL = root.url.appendingPathComponent("rename-source.gif")
            try gif.write(to: fileURL)
            guard let id = manager.importMedia(urls: [fileURL]) else {
                throw SecurityFailure.rejected("Expected imported media ID")
            }

            manager.renameMedia(id: id, displayName: "  Cool\nClip\t01  ")
            assertEqual(manager.config.mediaItems.first(where: { $0.id == id })?.displayName, "Cool Clip 01")
            assertTrue(manager.flushConfiguration())
            assertEqual(try store.loadConfig().mediaItems.first(where: { $0.id == id })?.displayName, "Cool Clip 01")

            manager.renameMedia(id: id, displayName: "   \n\t ")
            assertEqual(manager.config.mediaItems.first(where: { $0.id == id })?.displayName, "Media")

            // Toggling the inspected media off keeps previewedSource on that media so editing continues seamlessly
            if !manager.config.effectiveSelectedSources.contains(.builtIn(.starfield)) {
                manager.toggleSource(.builtIn(.starfield))
            }
            manager.previewSource(.media(id))
            manager.toggleSource(.media(id))
            assertFalse(manager.config.effectiveSelectedSources.contains(.media(id)))
            assertEqual(manager.previewedSource, .media(id))

            let l10nManager = LocalizationManager(defaults: isolatedDefaults())
            for key in ["terminal_saver.search_media", "terminal_saver.no_search_results", "terminal_saver.rename_clip_placeholder"] {
                for lang in [AppLanguage.german, .english, .spanish, .french] {
                    let localized = l10nManager.localized(key, for: lang)
                    assertFalse(localized.isEmpty || localized == key, "Missing localization for \(key) in \(lang)")
                }
            }
        }
    }
}

private func makeSyntheticMP4URL(
    in directory: URL,
    width: Int,
    height: Int,
    frameCount: Int,
    fps: Int32
) throws -> URL {
    let url = directory.appendingPathComponent("synthetic-\(UUID().uuidString).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
    )
    assertTrue(writer.canAdd(input))
    writer.add(input)
    assertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)

    for i in 0..<frameCount {
        let deadline = Date().addingTimeInterval(2.0)
        while !input.isReadyForMoreMediaData && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw SecurityFailure.rejected("Failed to create CVPixelBuffer for synthetic MP4")
        }
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let off = y * bpr + x * 4
                    ptr[off] = 255
                    ptr[off + 1] = UInt8((i * 25) % 255)
                    ptr[off + 2] = UInt8((x * 4) % 255)
                    ptr[off + 3] = UInt8((y * 4) % 255)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        let pts = CMTime(value: CMTimeValue(i), timescale: fps)
        assertTrue(adaptor.append(pb, withPresentationTime: pts))
    }

    input.markAsFinished()
    let sema = DispatchSemaphore(value: 0)
    writer.finishWriting { sema.signal() }
    assertEqual(sema.wait(timeout: .now() + 5.0), .success)
    assertEqual(writer.status, .completed)
    return url
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
