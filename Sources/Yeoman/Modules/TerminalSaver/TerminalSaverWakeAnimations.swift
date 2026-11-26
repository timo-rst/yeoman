import Foundation

/// Closing animations played over the last screensaver frame after the waking keypress.
/// Every animation is a pure function of `progress` and is fully blank at `progress >= 1`.
public enum TerminalSaverWakeAnimations {
    private static let decayRamp: [Character] = ["@", "*", "+", ":", "."]
    private static let glitchGlyphs: [Character] = ["/", "\\", "|", "-", "~", "=", "+", ":"]
    private static let densityRamp: [Character] = [" ", ".", ",", "-", "~", ":", ";", "=", "!", "*", "#", "$", "@"]
    private static let cipherGlyphs: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&/=+?~")
    private static let tumbleGlyphs: [Character] = ["/", "|", "\\", "-", "+", ":", "."]
    private static let rainGlyphs: [Character] = ["0", "1", ":", "|", "/", "\\", "+", "*", "=", "#"]
    private static let waveGlyphs: [Character] = ["@", "#", "*", "+", "~", ":", "."]

    /// Maps printable 7-bit ASCII scalar values (`0...127`) to `0...(densityRamp.count - 1)`.
    private static let asciiDensityTable: [UInt8] = {
        var table = Array<UInt8>(repeating: 6, count: 128)
        for code in 0...0x20 { table[code] = 0 }
        table[0x7F] = 0

        let buckets: [(String, UInt8)] = [
            (".", 1),
            (",'`_", 2),
            ("-^", 3),
            ("~<>", 4),
            (":il", 5),
            (";|/\\()[]{}", 6),
            ("=rvcjt+?1!", 7),
            ("7xyzsuonfILJ", 8),
            ("*oakbdpqehmw23569", 9),
            ("#048ACDEFGHKOPQRSTUVXYZ&%", 10),
            ("$BMWN", 11),
            ("@", 12)
        ]
        for (chars, level) in buckets {
            for scalar in chars.unicodeScalars where scalar.value < 128 {
                table[Int(scalar.value)] = level
            }
        }
        return table
    }()

    public static func frame(base: ASCIIFrame, animation: TerminalWakeAnimation, progress rawProgress: Double, seed: Int = 0) -> ASCIIFrame {
        let progress = rawProgress.isFinite ? min(1, max(0, rawProgress)) : 1
        if animation == .instant || progress >= 1 {
            return ASCIIFrame(columns: base.columns, rows: base.rows)
        }
        if progress <= 0 { return base }

        switch animation.resolved(seed: seed) {
        case .swarm: return swarmWake(base, progress, seed)
        case .decode: return decodeWake(base, progress, seed)
        case .morph: return morphWake(base, progress, seed)
        case .shatter: return shatterWake(base, progress, seed, entering: false)
        case .rain: return rainWake(base, progress, seed, entering: false)
        case .ripple: return rippleWake(base, progress, seed, entering: false)
        case .dissolve: return dissolve(base, progress, seed)
        case .curtain: return curtain(base, progress)
        case .cascade: return cascade(base, progress, seed)
        case .glitch: return glitch(base, progress, seed)
        case .iris: return iris(base, progress)
        case .random, .instant: return ASCIIFrame(columns: base.columns, rows: base.rows)
        }
    }

    /// Number of frames to render for a given duration at roughly 60 fps (at least one frame).
    public static func frameCount(animation: TerminalWakeAnimation, durationMilliseconds: Int) -> Int {
        guard animation != .instant else { return 1 }
        let duration = TerminalSaverPolicy.clamp(durationMilliseconds, TerminalSaverPolicy.wakeDurationRange)
        return max(1, duration / 16)
    }

    /// Opening build-up animations played over the first frame when entering the screensaver.
    /// Fully blank at `progress <= 0` (except `.instant`) and equals `target` at `progress >= 1`.
    public static func entryFrame(
        target: ASCIIFrame,
        animation: TerminalWakeAnimation,
        progress rawProgress: Double,
        seed: Int = 0
    ) -> ASCIIFrame {
        let progress = rawProgress.isFinite ? min(1, max(0, rawProgress)) : 1
        if animation == .instant || progress >= 1 {
            return target
        }
        if progress <= 0 {
            return ASCIIFrame(columns: target.columns, rows: target.rows)
        }
        let effective = animation.resolved(seed: seed)
        switch effective {
        case .shatter:
            return shatterWake(target, progress, seed, entering: true)
        case .rain:
            return rainWake(target, progress, seed, entering: true)
        case .ripple:
            return rippleWake(target, progress, seed, entering: true)
        default:
            return frame(base: target, animation: effective, progress: 1.0 - progress, seed: seed)
        }
    }

    public static func entryFrameCount(animation: TerminalWakeAnimation, durationMilliseconds: Int) -> Int {
        guard animation != .instant else { return 1 }
        let duration = TerminalSaverPolicy.clamp(durationMilliseconds, TerminalSaverPolicy.startDurationRange)
        return max(1, duration / 16)
    }

    /// Directional transition animations played when switching between screensaver sources.
    public static func transitionFrame(
        from: ASCIIFrame,
        to: ASCIIFrame,
        animation: TerminalTransitionAnimation,
        direction: TerminalTransitionDirection,
        progress rawProgress: Double,
        seed: Int = 0
    ) -> ASCIIFrame {
        let progress = rawProgress.isFinite ? min(1, max(0, rawProgress)) : 1
        if animation == .instant || progress >= 1 {
            return to
        }
        let fittedFrom = resizedFrame(from, columns: to.columns, rows: to.rows)
        if progress <= 0 {
            return fittedFrom
        }

        switch animation.resolved(seed: seed) {
        case .swarm:
            return swarmTransition(fittedFrom, to, direction: direction, progress: progress, seed: seed)
        case .decode:
            return decodeTransition(fittedFrom, to, direction: direction, progress: progress, seed: seed)
        case .morph:
            return morphTransition(fittedFrom, to, direction: direction, progress: progress, seed: seed)
        case .shatter:
            return shatterTransition(fittedFrom, to, direction: direction, progress: progress, seed: seed)
        case .rain:
            return rainTransition(fittedFrom, to, direction: direction, progress: progress, seed: seed)
        case .ripple:
            return rippleTransition(fittedFrom, to, direction: direction, progress: progress, seed: seed)
        case .slide:
            return slideTransition(fittedFrom, to, direction: direction, progress: progress)
        case .dissolve:
            return dissolveTransition(fittedFrom, to, progress: progress, seed: seed)
        case .wipe:
            return wipeTransition(fittedFrom, to, direction: direction, progress: progress, seed: seed)
        case .glitch:
            return glitchTransition(fittedFrom, to, direction: direction, progress: progress, seed: seed)
        case .random, .instant:
            return to
        }
    }

    public static func transitionFrameCount(animation: TerminalTransitionAnimation, durationMilliseconds: Int) -> Int {
        guard animation != .instant else { return 1 }
        let duration = TerminalSaverPolicy.clamp(durationMilliseconds, TerminalSaverPolicy.transitionDurationRange)
        return max(1, duration / 16)
    }

    private static func resizedFrame(_ source: ASCIIFrame, columns: Int, rows: Int) -> ASCIIFrame {
        if source.columns == columns && source.rows == rows {
            return source
        }
        var output = ASCIIFrame(columns: columns, rows: rows)
        let copyCols = min(source.columns, columns)
        let copyRows = min(source.rows, rows)
        for y in 0..<copyRows {
            for x in 0..<copyCols {
                output[x, y] = source[x, y]
            }
        }
        return output
    }

    private static func slideTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }
        let eased = progress * progress * (3.0 - 2.0 * progress)
        let shift = Int((eased * Double(cols)).rounded())
        var output = ASCIIFrame(columns: cols, rows: rows)

        for y in 0..<rows {
            for x in 0..<cols {
                switch direction {
                case .forward:
                    let cut = cols - shift
                    if x < cut {
                        output[x, y] = from[x + shift, y]
                    } else {
                        output[x, y] = to[x - cut, y]
                    }
                case .backward:
                    if x >= shift {
                        output[x, y] = from[x - shift, y]
                    } else {
                        output[x, y] = to[cols - shift + x, y]
                    }
                }
            }
        }
        return output
    }

    private static func dissolveTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }
        var output = ASCIIFrame(columns: cols, rows: rows)
        for y in 0..<rows {
            for x in 0..<cols {
                let threshold = TerminalSaverNoise.value(x, y, seed &+ 131)
                let cell = progress >= threshold ? to[x, y] : from[x, y]
                let dist = abs(progress - threshold)
                if dist < 0.06, !cell.isBlank {
                    let glyph = decayRamp[min(decayRamp.count - 1, Int((dist / 0.06) * Double(decayRamp.count)))]
                    var spark = dim(cell, 0.75)
                    spark.character = glyph
                    output[x, y] = spark
                } else {
                    output[x, y] = cell
                }
            }
        }
        return output
    }

    private static func wipeTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }
        let eased = progress * progress * (3.0 - 2.0 * progress)
        let seamWidth = max(2, min(5, cols / 16))
        var output = ASCIIFrame(columns: cols, rows: rows)

        for y in 0..<rows {
            let jitter = Int(((TerminalSaverNoise.value(y, seed &+ 157) - 0.5) * 3.0).rounded())
            let front = Int((eased * Double(cols + seamWidth)).rounded()) + jitter
            for x in 0..<cols {
                let pos = (direction == .forward) ? x : (cols - 1 - x)
                if pos < front - seamWidth {
                    output[x, y] = to[x, y]
                } else if pos < front {
                    let seamCell = !to[x, y].isBlank ? to[x, y] : from[x, y]
                    if !seamCell.isBlank {
                        let glyph = decayRamp[min(decayRamp.count - 1, abs(front - pos) % decayRamp.count)]
                        var faded = dim(seamCell, 0.65)
                        faded.character = glyph
                        output[x, y] = faded
                    }
                } else {
                    output[x, y] = from[x, y]
                }
            }
        }
        return output
    }

    private static func glitchTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }
        let step = Int(progress * 24)
        let dirSign = (direction == .forward) ? 1 : -1
        var output = ASCIIFrame(columns: cols, rows: rows)

        for y in 0..<rows {
            let envelope = 1.0 - abs(progress - 0.5) * 2.0
            let shift = Int(((TerminalSaverNoise.value(y, step, seed &+ 179) - 0.5) * envelope * Double(cols) * 0.4).rounded()) * dirSign
            for x in 0..<cols {
                let roll = TerminalSaverNoise.value(x, y, step &+ seed &* 19)
                let useTarget = roll < progress
                let cell = useTarget ? to[x - shift, y] : from[x + shift, y]
                guard !cell.isBlank else { continue }
                if abs(roll - progress) < 0.08 {
                    let glyph = glitchGlyphs[Int(roll * 997) % glitchGlyphs.count]
                    output[x, y] = ASCIICell(glyph, cell.red, cell.green, cell.blue)
                } else {
                    output[x, y] = cell
                }
            }
        }
        return output
    }

    private static func swarmTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }

        var fromPoints: [(x: Int, y: Int, cell: ASCIICell)] = []
        var toPoints: [(x: Int, y: Int, cell: ASCIICell)] = []
        for y in 0..<rows {
            for x in 0..<cols {
                let src = from[x, y]
                if !src.isBlank { fromPoints.append((x, y, src)) }
                let dst = to[x, y]
                if !dst.isBlank { toPoints.append((x, y, dst)) }
            }
        }
        guard !fromPoints.isEmpty || !toPoints.isEmpty else { return to }

        var output = ASCIIFrame(columns: cols, rows: rows)
        let dirSign = (direction == .forward) ? 1.0 : -1.0

        if fromPoints.isEmpty {
            for i in 0..<toPoints.count {
                let dst = toPoints[i]
                let delay = TerminalSaverNoise.value(i, 0, seed &+ 191) * 0.24
                let localT = min(1.0, max(0.0, (progress - delay) / 0.76))
                let eased = localT * localT * (3.0 - 2.0 * localT)
                let arc = sin(localT * .pi)
                let startX = Double(dst.x) - dirSign * Double(cols) * (0.25 + TerminalSaverNoise.value(i, 3, seed &+ 189) * 0.25)
                let startY = Double(dst.y) + (TerminalSaverNoise.value(i, 4, seed &+ 187) - 0.5) * Double(rows) * 0.35
                let px = Int((startX + (Double(dst.x) - startX) * eased).rounded())
                let py = Int((startY + (Double(dst.y) - startY) * eased).rounded())
                guard output.contains(px, py) else { continue }
                let glyph = localT > 0.65
                    ? dst.cell.character
                    : tumbleGlyphs[safeIndex(TerminalSaverNoise.value(i, Int(localT * 12), seed &+ 199), count: tumbleGlyphs.count)]
                let faded = dim(ASCIICell(glyph, dst.cell.red, dst.cell.green, dst.cell.blue), 0.2 + 0.8 * eased)
                output[px, py] = boost(faded, 0.15 * arc)
            }
            return output
        }

        if toPoints.isEmpty {
            for i in 0..<fromPoints.count {
                let src = fromPoints[i]
                let delay = TerminalSaverNoise.value(i, 0, seed &+ 191) * 0.24
                let localT = min(1.0, max(0.0, (progress - delay) / 0.76))
                let eased = localT * localT * (3.0 - 2.0 * localT)
                let endX = Double(src.x) + dirSign * Double(cols) * (0.25 + TerminalSaverNoise.value(i, 3, seed &+ 189) * 0.25)
                let endY = Double(src.y) + (TerminalSaverNoise.value(i, 4, seed &+ 187) - 0.5) * Double(rows) * 0.35
                let px = Int((Double(src.x) + (endX - Double(src.x)) * eased).rounded())
                let py = Int((Double(src.y) + (endY - Double(src.y)) * eased).rounded())
                guard output.contains(px, py), eased < 0.96 else { continue }
                let glyph = localT < 0.3
                    ? src.cell.character
                    : decayRamp[safeIndex(min(0.99, localT), count: decayRamp.count)]
                output[px, py] = dim(ASCIICell(glyph, src.cell.red, src.cell.green, src.cell.blue), 1.0 - eased)
            }
            return output
        }

        let count = max(fromPoints.count, toPoints.count)
        let step = Int(progress * 12.0)
        for i in 0..<count {
            let src = fromPoints[(i * fromPoints.count) / count]
            let dst = toPoints[(i * toPoints.count) / count]
            let delay = TerminalSaverNoise.value(i, 0, seed &+ 191) * 0.24
            let localT = min(1.0, max(0.0, (progress - delay) / 0.76))
            let eased = localT * localT * (3.0 - 2.0 * localT)
            let arc = sin(localT * .pi)
            let swirlX = dirSign * arc * (TerminalSaverNoise.value(i, 1, seed &+ 193) - 0.3) * Double(cols) * 0.16
            let swirlY = arc * (TerminalSaverNoise.value(i, 2, seed &+ 197) - 0.5) * Double(rows) * 0.28
            let pxF = Double(src.x) + Double(dst.x - src.x) * eased + swirlX
            let pyF = Double(src.y) + Double(dst.y - src.y) * eased + swirlY
            let px = Int(pxF.rounded())
            let py = Int(pyF.rounded())

            let glyph: Character
            if localT < 0.35 {
                glyph = src.cell.character
            } else if localT > 0.65 {
                glyph = dst.cell.character
            } else {
                glyph = tumbleGlyphs[safeIndex(TerminalSaverNoise.value(i, step, seed &+ 199), count: tumbleGlyphs.count)]
            }
            let rgb = lerpColor(src.cell, dst.cell, eased)

            if arc > 0.2 {
                let trailX = px - Int(dirSign)
                let trailY = py
                if output.contains(trailX, trailY), output[trailX, trailY].isBlank {
                    output[trailX, trailY] = dim(ASCIICell(".", rgb.0, rgb.1, rgb.2), 0.35)
                }
            }
            if output.contains(px, py) {
                output[px, py] = boost(ASCIICell(glyph, rgb.0, rgb.1, rgb.2), 0.18 * arc)
            }
        }
        return output
    }

    private static func decodeTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }

        var output = ASCIIFrame(columns: cols, rows: rows)
        let denomX = Double(max(1, cols - 1))
        let spinStep = Int(progress * 30.0)

        for y in 0..<rows {
            for x in 0..<cols {
                let src = from[x, y]
                let dst = to[x, y]
                if src.isBlank && dst.isBlank { continue }

                let normX = (direction == .forward) ? (Double(x) / denomX) : (1.0 - Double(x) / denomX)
                let jitter = TerminalSaverNoise.value(x, y, seed &+ 211)
                let start = normX * 0.25 + jitter * 0.20
                let end = min(0.98, start + 0.35 + jitter * 0.15)

                if progress < start {
                    output[x, y] = src
                } else if progress >= end {
                    if !dst.isBlank && progress < end + 0.08 {
                        let glow = 0.45 * (1.0 - (progress - end) / 0.08)
                        output[x, y] = boost(dst, glow)
                    } else {
                        output[x, y] = dst
                    }
                } else {
                    let localT = (progress - start) / max(0.01, end - start)
                    let glyphNoise = TerminalSaverNoise.value(x, y, spinStep &+ seed &+ 223)
                    let glyph = cipherGlyphs[safeIndex(glyphNoise, count: cipherGlyphs.count)]
                    if dst.isBlank {
                        if localT < 0.5 {
                            output[x, y] = dim(ASCIICell(glyph, src.red, src.green, src.blue), 1.0 - localT * 0.7)
                        } else {
                            let tailGlyph: Character = localT < 0.75 ? ":" : "."
                            output[x, y] = dim(ASCIICell(tailGlyph, src.red, src.green, src.blue), max(0.0, (1.0 - localT) * 0.9))
                        }
                    } else {
                        let rgb = lerpColor(src, dst, localT)
                        let highlight = sin(localT * .pi) * 0.35
                        output[x, y] = boost(ASCIICell(glyph, rgb.0, rgb.1, rgb.2), highlight)
                    }
                }
            }
        }
        return output
    }

    private static func morphTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }

        var output = ASCIIFrame(columns: cols, rows: rows)
        let denomX = Double(max(1, cols - 1))

        for y in 0..<rows {
            for x in 0..<cols {
                let src = from[x, y]
                let dst = to[x, y]
                if src.isBlank && dst.isBlank { continue }

                let normX = (direction == .forward) ? (Double(x) / denomX) : (1.0 - Double(x) / denomX)
                let jitter = TerminalSaverNoise.value(x, y, seed &+ 241) * 0.18
                let windowStart = normX * 0.30 + jitter
                let localT = min(1.0, max(0.0, (progress - windowStart) / 0.52))
                let eased = localT * localT * (3.0 - 2.0 * localT)

                if eased < 0.15 && !src.isBlank {
                    output[x, y] = src
                    continue
                }
                if eased > 0.85 && !dst.isBlank {
                    output[x, y] = dst
                    continue
                }

                let srcLevel = Double(densityLevel(of: src.character))
                let dstLevel = Double(densityLevel(of: dst.character))
                var interp = srcLevel + (dstLevel - srcLevel) * eased
                if !src.isBlank && !dst.isBlank && abs(srcLevel - dstLevel) < 1.5 {
                    interp = max(1.0, interp - sin(eased * .pi) * 2.5)
                }
                let idx = min(densityRamp.count - 1, max(0, Int(interp.rounded())))
                if idx > 0 {
                    let rgb = lerpColor(src, dst, eased)
                    output[x, y] = ASCIICell(densityRamp[idx], rgb.0, rgb.1, rgb.2)
                }
            }
        }
        return output
    }

    private static func shatterTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }

        var output = ASCIIFrame(columns: cols, rows: rows)
        let denomX = Double(max(1, cols - 1))
        let denomY = Double(max(1, rows - 1))

        for y in 0..<rows {
            let bottomFactor = 1.0 - Double(y) / denomY
            for x in 0..<cols {
                let src = from[x, y]
                guard !src.isBlank else { continue }
                let normX = (direction == .forward) ? (Double(x) / denomX) : (1.0 - Double(x) / denomX)
                let delay = normX * 0.18 + bottomFactor * 0.14 + TerminalSaverNoise.value(x, y, seed &+ 263) * 0.12
                let fallT = (progress - delay) / 0.48
                if fallT <= 0 {
                    output[x, y] = src
                } else if fallT < 1.0 {
                    let dy = Int((fallT * fallT * Double(rows + 4)).rounded())
                    let drift = (TerminalSaverNoise.value(x, y, seed &+ 269) - 0.5) * fallT * 6.0
                    let nx = x + Int(drift.rounded())
                    let ny = y + dy
                    guard output.contains(nx, ny) else { continue }
                    let glyph = fallT > 0.25
                        ? tumbleGlyphs[safeIndex(TerminalSaverNoise.value(x, y, Int(fallT * 10) &+ seed), count: tumbleGlyphs.count)]
                        : src.character
                    output[nx, ny] = dim(ASCIICell(glyph, src.red, src.green, src.blue), 1.0 - fallT * 0.7)
                }
            }
        }

        for y in 0..<rows {
            let bottomFactor = 1.0 - Double(y) / denomY
            for x in 0..<cols {
                let dst = to[x, y]
                guard !dst.isBlank else { continue }
                let normX = (direction == .forward) ? (Double(x) / denomX) : (1.0 - Double(x) / denomX)
                let start = 0.22 + normX * 0.18 + bottomFactor * 0.14 + TerminalSaverNoise.value(x, y, seed &+ 277) * 0.10
                let landT = (progress - start) / 0.36
                if landT >= 1.0 {
                    output[x, y] = dst
                } else if landT > 0 {
                    let rem = 1.0 - landT
                    let dy = Int((rem * rem * Double(y + 4)).rounded())
                    let ny = y - dy
                    guard output.contains(x, ny) else { continue }
                    let glyph = landT > 0.75
                        ? dst.character
                        : tumbleGlyphs[safeIndex(TerminalSaverNoise.value(x, y, Int(landT * 10) &+ seed &+ 17), count: tumbleGlyphs.count)]
                    output[x, ny] = dim(ASCIICell(glyph, dst.red, dst.green, dst.blue), 0.55 + 0.45 * landT)
                }
            }
        }
        return output
    }

    private static func rainTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0, !(from.isBlank && to.isBlank) else { return to }

        var output = ASCIIFrame(columns: cols, rows: rows)
        let denomX = Double(max(1, cols - 1))
        let trailLen = max(3, min(7, rows / 4))
        let tick = Int(progress * 24.0)

        for x in 0..<cols {
            var colHasContent = false
            for y in 0..<rows where !from[x, y].isBlank || !to[x, y].isBlank {
                colHasContent = true
                break
            }
            let sparseAccent = TerminalSaverNoise.value(x, 1, seed &+ 311) < 0.14
            let normX = (direction == .forward) ? (Double(x) / denomX) : (1.0 - Double(x) / denomX)
            let colDelay = normX * 0.28 + TerminalSaverNoise.value(x, 0, seed &+ 307) * 0.22
            let colT = min(1.0, max(0.0, (progress - colDelay) / 0.50))

            if colT <= 0 {
                for y in 0..<rows { output[x, y] = from[x, y] }
                continue
            }
            if colT >= 1.0 {
                for y in 0..<rows { output[x, y] = to[x, y] }
                continue
            }

            let headY = Int((colT * Double(rows + trailLen)).rounded()) - 1
            for y in 0..<rows {
                let distAboveHead = headY - y
                let dst = to[x, y]
                let src = from[x, y]

                if distAboveHead < 0 {
                    output[x, y] = src
                } else if distAboveHead == 0 {
                    guard colHasContent || sparseAccent else { continue }
                    let glyph = rainGlyphs[safeIndex(TerminalSaverNoise.value(x, y, tick &+ seed), count: rainGlyphs.count)]
                    let base = !dst.isBlank ? dst : src
                    if !base.isBlank {
                        output[x, y] = boost(ASCIICell(glyph, base.red, base.green, base.blue), 0.7)
                    } else if colHasContent {
                        output[x, y] = ASCIICell(glyph, 190, 235, 200)
                    } else {
                        output[x, y] = ASCIICell(glyph, 90, 140, 110)
                    }
                } else if distAboveHead <= trailLen {
                    let t = Double(distAboveHead) / Double(trailLen)
                    if !dst.isBlank {
                        if t < 0.35 {
                            let glyph = rainGlyphs[safeIndex(TerminalSaverNoise.value(x, y, tick &+ seed &+ 5), count: rainGlyphs.count)]
                            output[x, y] = boost(ASCIICell(glyph, dst.red, dst.green, dst.blue), 0.35 * (1.0 - t))
                        } else {
                            output[x, y] = dst
                        }
                    } else if !src.isBlank {
                        let glyph = decayRamp[safeIndex(min(0.99, t), count: decayRamp.count)]
                        output[x, y] = dim(ASCIICell(glyph, src.red, src.green, src.blue), 1.0 - t * 0.8)
                    } else if colHasContent {
                        let glyph = rainGlyphs[safeIndex(TerminalSaverNoise.value(x, y, seed &+ 313), count: rainGlyphs.count)]
                        output[x, y] = dim(ASCIICell(glyph, 80, 175, 115), max(0.0, (1.0 - t) * 0.45))
                    }
                } else {
                    output[x, y] = dst
                }
            }
        }
        return output
    }

    private static func rippleTransition(
        _ from: ASCIIFrame,
        _ to: ASCIIFrame,
        direction: TerminalTransitionDirection,
        progress: Double,
        seed: Int
    ) -> ASCIIFrame {
        let cols = to.columns
        let rows = to.rows
        guard cols > 0, rows > 0 else { return to }

        var output = ASCIIFrame(columns: cols, rows: rows)
        let originX = (direction == .forward) ? Double(cols) * 0.18 : Double(cols) * 0.82
        let originY = Double(rows) * 0.5
        let eased = progress * progress * (3.0 - 2.0 * progress)
        let maxRadius = hypot(Double(cols) * 0.85 * 0.5, Double(rows) * 0.55) + 3.0
        let ringWidth = max(2.2, Double(min(cols / 2, rows)) * 0.22)
        let waveRadius = eased * (maxRadius + ringWidth) - ringWidth * 0.5

        for y in 0..<rows {
            for x in 0..<cols {
                let rx = Double(x) + 0.5 - originX
                let ry = Double(y) + 0.5 - originY
                let dist = hypot(rx * 0.5, ry)
                let delta = dist - waveRadius

                if delta < -ringWidth {
                    output[x, y] = to[x, y]
                } else if delta > ringWidth {
                    output[x, y] = from[x, y]
                } else {
                    let u = max(0.0, 1.0 - abs(delta) / ringWidth)
                    let crest = 0.5 - 0.5 * cos(u * .pi)
                    let rLen = max(0.001, hypot(rx, ry))
                    let push = crest * 2.5
                    let offX = Int((rx / rLen * push).rounded())
                    let offY = Int((ry / rLen * push * 0.6).rounded())

                    let useTarget = delta <= 0
                    let displaced = useTarget ? to[x - offX, y - offY] : from[x + offX, y + offY]
                    let sampled = !displaced.isBlank ? displaced : (useTarget ? to[x, y] : from[x, y])
                    guard !sampled.isBlank else { continue }

                    if crest > 0.45 {
                        let glyph = waveGlyphs[safeIndex(TerminalSaverNoise.value(x, y, Int(crest * 10) &+ seed &+ 331), count: waveGlyphs.count)]
                        output[x, y] = boost(ASCIICell(glyph, sampled.red, sampled.green, sampled.blue), crest * 0.55)
                    } else {
                        output[x, y] = boost(sampled, crest * 0.25)
                    }
                }
            }
        }
        return output
    }

    @inline(__always)
    private static func densityLevel(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first, scalar.isASCII, scalar.value < 128 else {
            return character == " " ? 0 : 6
        }
        return Int(asciiDensityTable[Int(scalar.value)])
    }

    @inline(__always)
    private static func safeIndex(_ noise: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, Int(noise * Double(count))))
    }

    @inline(__always)
    private static func lerpColor(_ a: ASCIICell, _ b: ASCIICell, _ t: Double) -> (UInt8, UInt8, UInt8) {
        let u = min(1.0, max(0.0, t))
        if a.isBlank && b.isBlank { return (0, 0, 0) }
        if a.isBlank {
            return (
                UInt8((Double(b.red) * u).rounded()),
                UInt8((Double(b.green) * u).rounded()),
                UInt8((Double(b.blue) * u).rounded())
            )
        }
        if b.isBlank {
            let inv = 1.0 - u
            return (
                UInt8((Double(a.red) * inv).rounded()),
                UInt8((Double(a.green) * inv).rounded()),
                UInt8((Double(a.blue) * inv).rounded())
            )
        }
        let inv = 1.0 - u
        return (
            UInt8((Double(a.red) * inv + Double(b.red) * u).rounded()),
            UInt8((Double(a.green) * inv + Double(b.green) * u).rounded()),
            UInt8((Double(a.blue) * inv + Double(b.blue) * u).rounded())
        )
    }

    @inline(__always)
    private static func boost(_ cell: ASCIICell, _ amount: Double) -> ASCIICell {
        let f = max(0, min(1, amount))
        return ASCIICell(
            cell.character,
            UInt8(min(255, Int((Double(cell.red) + (255.0 - Double(cell.red)) * f).rounded()))),
            UInt8(min(255, Int((Double(cell.green) + (255.0 - Double(cell.green)) * f).rounded()))),
            UInt8(min(255, Int((Double(cell.blue) + (255.0 - Double(cell.blue)) * f).rounded())))
        )
    }

    @inline(__always)
    private static func dim(_ cell: ASCIICell, _ factor: Double) -> ASCIICell {
        let f = max(0, min(1, factor))
        return ASCIICell(cell.character, UInt8(Double(cell.red) * f), UInt8(Double(cell.green) * f), UInt8(Double(cell.blue) * f))
    }

    private static func dissolve(_ base: ASCIIFrame, _ progress: Double, _ seed: Int) -> ASCIIFrame {
        var output = ASCIIFrame(columns: base.columns, rows: base.rows)
        for y in 0..<base.rows {
            for x in 0..<base.columns {
                let cell = base[x, y]
                guard !cell.isBlank else { continue }
                let threshold = TerminalSaverNoise.value(x, y, seed &+ 71)
                let decay = (progress - threshold * 0.6) / 0.4
                if decay <= 0 {
                    output[x, y] = cell
                } else if decay < 1 {
                    let index = min(decayRamp.count - 1, Int(decay * Double(decayRamp.count)))
                    var faded = dim(cell, 1 - decay * 0.7)
                    faded.character = decayRamp[index]
                    output[x, y] = faded
                }
            }
        }
        return output
    }

    private static func curtain(_ base: ASCIIFrame, _ progress: Double) -> ASCIIFrame {
        var output = ASCIIFrame(columns: base.columns, rows: base.rows)
        let half = Double(base.columns) / 2
        let offset = Int((progress * progress * (half + 1)).rounded(.up))
        let center = base.columns / 2
        for y in 0..<base.rows {
            for x in 0..<base.columns {
                let source = x < center ? x + offset : x - offset
                let sameSide = x < center ? source < center : source >= center
                if sameSide { output[x, y] = base[source, y] }
            }
        }
        return output
    }

    private static func cascade(_ base: ASCIIFrame, _ progress: Double, _ seed: Int) -> ASCIIFrame {
        var output = ASCIIFrame(columns: base.columns, rows: base.rows)
        for x in 0..<base.columns {
            let delay = TerminalSaverNoise.value(x, seed &+ 83) * 0.4
            let local = max(0, (progress - delay) / 0.6)
            let fall = Int((local * local * Double(base.rows + 1)).rounded(.up))
            for y in 0..<base.rows {
                let source = y - fall
                guard source >= 0 else { continue }
                let cell = base[x, source]
                if !cell.isBlank { output[x, y] = dim(cell, 1 - local * 0.5) }
            }
        }
        return output
    }

    private static func glitch(_ base: ASCIIFrame, _ progress: Double, _ seed: Int) -> ASCIIFrame {
        var output = ASCIIFrame(columns: base.columns, rows: base.rows)
        let step = Int(progress * 20)
        for y in 0..<base.rows {
            let shift = Int(((TerminalSaverNoise.value(y, step, seed &+ 97) - 0.5) * progress * Double(base.columns) * 0.5).rounded())
            for x in 0..<base.columns {
                let roll = TerminalSaverNoise.value(x, y, step &+ seed &* 31)
                guard roll >= progress else { continue }
                let cell = base[x - shift, y]
                guard !cell.isBlank else { continue }
                if roll < progress + 0.08 {
                    let glyph = glitchGlyphs[Int(roll * 997) % glitchGlyphs.count]
                    output[x, y] = ASCIICell(glyph, cell.red, cell.green, cell.blue)
                } else {
                    output[x, y] = cell
                }
            }
        }
        return output
    }

    private static func iris(_ base: ASCIIFrame, _ progress: Double) -> ASCIIFrame {
        var output = ASCIIFrame(columns: base.columns, rows: base.rows)
        let cx = Double(base.columns) / 2
        let cy = Double(base.rows) / 2
        let maxRadius = ((cx / 2) * (cx / 2) + cy * cy).squareRoot() + 1
        let radius = (1 - progress) * maxRadius
        for y in 0..<base.rows {
            for x in 0..<base.columns {
                let dx = (Double(x) + 0.5 - cx) / 2
                let dy = Double(y) + 0.5 - cy
                if (dx * dx + dy * dy).squareRoot() < radius { output[x, y] = base[x, y] }
            }
        }
        return output
    }

    private static func swarmWake(_ base: ASCIIFrame, _ progress: Double, _ seed: Int) -> ASCIIFrame {
        let cols = base.columns
        let rows = base.rows
        var output = ASCIIFrame(columns: cols, rows: rows)
        guard cols > 0, rows > 0, !base.isBlank else { return output }

        var points: [(x: Int, y: Int, cell: ASCIICell)] = []
        for y in 0..<rows {
            for x in 0..<cols {
                let c = base[x, y]
                if !c.isBlank { points.append((x, y, c)) }
            }
        }
        let cx = Double(cols) * 0.5
        let cy = Double(rows) * 0.5
        let maxSpread = hypot(cx, Double(rows))
        let step = Int(progress * 14.0)

        for i in 0..<points.count {
            let p = points[i]
            let delay = TerminalSaverNoise.value(i, 0, seed &+ 401) * 0.28
            let localT = min(1.0, max(0.0, (progress - delay) / 0.72))
            let eased = localT * localT * (3.0 - 2.0 * localT)
            guard eased < 0.96 else { continue }

            let arc = sin(localT * .pi)
            let baseAngle = atan2(Double(p.y) - cy, (Double(p.x) - cx) * 0.5)
            let angle = baseAngle + (TerminalSaverNoise.value(i, 1, seed &+ 403) - 0.5) * 1.4
            let dist = (0.35 + TerminalSaverNoise.value(i, 2, seed &+ 407) * 0.45) * maxSpread
            let swirlX = arc * (TerminalSaverNoise.value(i, 3, seed &+ 409) - 0.5) * Double(cols) * 0.14
            let swirlY = arc * (TerminalSaverNoise.value(i, 4, seed &+ 413) - 0.5) * Double(rows) * 0.22
            let px = Int((Double(p.x) + cos(angle) * dist * eased + swirlX).rounded())
            let py = Int((Double(p.y) + sin(angle) * dist * 0.65 * eased + swirlY).rounded())

            let glyph: Character
            if localT < 0.30 {
                glyph = p.cell.character
            } else if localT < 0.70 {
                glyph = tumbleGlyphs[safeIndex(TerminalSaverNoise.value(i, step, seed &+ 415), count: tumbleGlyphs.count)]
            } else {
                glyph = decayRamp[safeIndex(min(0.99, localT), count: decayRamp.count)]
            }

            let lit = boost(dim(ASCIICell(glyph, p.cell.red, p.cell.green, p.cell.blue), 1.0 - eased), 0.2 * arc)
            if arc > 0.25 {
                let trailX = px - Int((cos(angle) * 1.2).rounded())
                let trailY = py - Int((sin(angle) * 0.8).rounded())
                if output.contains(trailX, trailY), output[trailX, trailY].isBlank {
                    output[trailX, trailY] = dim(ASCIICell(".", p.cell.red, p.cell.green, p.cell.blue), max(0.0, (1.0 - eased) * 0.4))
                }
            }
            if output.contains(px, py) {
                output[px, py] = lit
            }
        }
        return output
    }

    private static func decodeWake(_ base: ASCIIFrame, _ progress: Double, _ seed: Int) -> ASCIIFrame {
        let cols = base.columns
        let rows = base.rows
        var output = ASCIIFrame(columns: cols, rows: rows)
        guard cols > 0, rows > 0, !base.isBlank else { return output }

        let denomX = Double(max(1, cols - 1))
        let spinStep = Int(progress * 30.0)

        for y in 0..<rows {
            for x in 0..<cols {
                let cell = base[x, y]
                guard !cell.isBlank else { continue }
                let normX = Double(x) / denomX
                let jitter = TerminalSaverNoise.value(x, y, seed &+ 419)
                let start = normX * 0.25 + jitter * 0.22
                let end = min(0.98, start + 0.38 + jitter * 0.14)

                if progress < start {
                    if progress >= start - 0.07 {
                        let glow = 0.42 * (1.0 - min(1.0, max(0.0, (start - progress) / 0.07)))
                        output[x, y] = boost(cell, glow)
                    } else {
                        output[x, y] = cell
                    }
                } else if progress < end {
                    let localT = (progress - start) / max(0.01, end - start)
                    if localT < 0.65 {
                        let glyph = cipherGlyphs[safeIndex(TerminalSaverNoise.value(x, y, spinStep &+ seed &+ 421), count: cipherGlyphs.count)]
                        let highlight = sin(localT * .pi) * 0.32
                        output[x, y] = boost(dim(ASCIICell(glyph, cell.red, cell.green, cell.blue), 1.0 - localT * 0.45), highlight)
                    } else {
                        let tailGlyph: Character = localT < 0.82 ? ":" : "."
                        output[x, y] = dim(ASCIICell(tailGlyph, cell.red, cell.green, cell.blue), max(0.0, (1.0 - localT) * 1.4))
                    }
                }
            }
        }
        return output
    }

    private static func morphWake(_ base: ASCIIFrame, _ progress: Double, _ seed: Int) -> ASCIIFrame {
        let cols = base.columns
        let rows = base.rows
        var output = ASCIIFrame(columns: cols, rows: rows)
        guard cols > 0, rows > 0, !base.isBlank else { return output }

        let denomX = Double(max(1, cols - 1))
        for y in 0..<rows {
            for x in 0..<cols {
                let cell = base[x, y]
                guard !cell.isBlank else { continue }
                let normX = Double(x) / denomX
                let start = normX * 0.26 + TerminalSaverNoise.value(x, y, seed &+ 433) * 0.22
                let localT = min(1.0, max(0.0, (progress - start) / 0.52))
                let eased = localT * localT * (3.0 - 2.0 * localT)

                if eased < 0.12 {
                    output[x, y] = cell
                    continue
                }
                let srcLevel = Double(densityLevel(of: cell.character))
                let level = srcLevel * (1.0 - eased)
                let idx = min(densityRamp.count - 1, max(0, Int(level.rounded())))
                if idx > 0 {
                    output[x, y] = dim(ASCIICell(densityRamp[idx], cell.red, cell.green, cell.blue), 1.0 - eased * 0.75)
                }
            }
        }
        return output
    }

    private static func shatterWake(_ base: ASCIIFrame, _ progress: Double, _ seed: Int, entering: Bool) -> ASCIIFrame {
        let cols = base.columns
        let rows = base.rows
        var output = ASCIIFrame(columns: cols, rows: rows)
        guard cols > 0, rows > 0, !base.isBlank else { return output }

        let denomX = Double(max(1, cols - 1))
        let denomY = Double(max(1, rows - 1))

        for y in 0..<rows {
            let bottomFactor = 1.0 - Double(y) / denomY
            for x in 0..<cols {
                let cell = base[x, y]
                guard !cell.isBlank else { continue }
                let normX = Double(x) / denomX
                let delay = normX * 0.18 + bottomFactor * 0.16 + TerminalSaverNoise.value(x, y, seed &+ 443) * 0.14

                if entering {
                    let landT = (progress - delay) / 0.52
                    if landT >= 1.0 {
                        output[x, y] = cell
                    } else if landT > 0 {
                        let rem = 1.0 - landT
                        let dy = Int((rem * rem * Double(y + 4)).rounded())
                        let ny = y - dy
                        guard output.contains(x, ny) else { continue }
                        let glyph = landT > 0.75
                            ? cell.character
                            : tumbleGlyphs[safeIndex(TerminalSaverNoise.value(x, y, Int(landT * 10) &+ seed &+ 449), count: tumbleGlyphs.count)]
                        output[x, ny] = dim(ASCIICell(glyph, cell.red, cell.green, cell.blue), 0.5 + 0.5 * landT)
                    }
                } else {
                    let fallT = (progress - delay) / 0.52
                    if fallT <= 0 {
                        output[x, y] = cell
                    } else if fallT < 1.0 {
                        let dy = Int((fallT * fallT * Double(rows + 4)).rounded())
                        let drift = (TerminalSaverNoise.value(x, y, seed &+ 451) - 0.5) * fallT * 6.0
                        let nx = x + Int(drift.rounded())
                        let ny = y + dy
                        guard output.contains(nx, ny) else { continue }
                        let glyph = fallT > 0.22
                            ? tumbleGlyphs[safeIndex(TerminalSaverNoise.value(x, y, Int(fallT * 10) &+ seed &+ 453), count: tumbleGlyphs.count)]
                            : cell.character
                        output[nx, ny] = dim(ASCIICell(glyph, cell.red, cell.green, cell.blue), 1.0 - fallT * 0.72)
                    }
                }
            }
        }
        return output
    }

    private static func rainWake(_ base: ASCIIFrame, _ progress: Double, _ seed: Int, entering: Bool) -> ASCIIFrame {
        let cols = base.columns
        let rows = base.rows
        var output = ASCIIFrame(columns: cols, rows: rows)
        guard cols > 0, rows > 0, !base.isBlank else { return output }

        let denomX = Double(max(1, cols - 1))
        let trailLen = max(3, min(7, rows / 4))
        let tick = Int(progress * 24.0)

        for x in 0..<cols {
            var colHasContent = false
            for y in 0..<rows where !base[x, y].isBlank {
                colHasContent = true
                break
            }
            let sparseAccent = TerminalSaverNoise.value(x, 1, seed &+ 461) < 0.12
            let normX = Double(x) / denomX
            let colDelay = normX * 0.24 + TerminalSaverNoise.value(x, 0, seed &+ 457) * 0.24
            let colT = min(1.0, max(0.0, (progress - colDelay) / 0.52))

            if colT <= 0 {
                if !entering {
                    for y in 0..<rows { output[x, y] = base[x, y] }
                }
                continue
            }
            if colT >= 1.0 {
                if entering {
                    for y in 0..<rows { output[x, y] = base[x, y] }
                }
                continue
            }

            let headY = Int((colT * Double(rows + trailLen)).rounded()) - 1
            for y in 0..<rows {
                let distAboveHead = headY - y
                let cell = base[x, y]

                if distAboveHead < 0 {
                    if !entering { output[x, y] = cell }
                } else if distAboveHead == 0 {
                    guard colHasContent || sparseAccent else { continue }
                    let glyph = rainGlyphs[safeIndex(TerminalSaverNoise.value(x, y, tick &+ seed &+ 463), count: rainGlyphs.count)]
                    if !cell.isBlank {
                        output[x, y] = boost(ASCIICell(glyph, cell.red, cell.green, cell.blue), 0.7)
                    } else if colHasContent {
                        output[x, y] = ASCIICell(glyph, 190, 235, 200)
                    } else {
                        output[x, y] = ASCIICell(glyph, 90, 140, 110)
                    }
                } else if distAboveHead <= trailLen {
                    let t = Double(distAboveHead) / Double(trailLen)
                    if entering {
                        if !cell.isBlank {
                            if t < 0.35 {
                                let glyph = rainGlyphs[safeIndex(TerminalSaverNoise.value(x, y, tick &+ seed &+ 467), count: rainGlyphs.count)]
                                output[x, y] = boost(ASCIICell(glyph, cell.red, cell.green, cell.blue), 0.35 * (1.0 - t))
                            } else {
                                output[x, y] = cell
                            }
                        } else if colHasContent {
                            let glyph = rainGlyphs[safeIndex(TerminalSaverNoise.value(x, y, seed &+ 471), count: rainGlyphs.count)]
                            output[x, y] = dim(ASCIICell(glyph, 80, 175, 115), max(0.0, (1.0 - t) * 0.45))
                        }
                    } else {
                        if !cell.isBlank {
                            let glyph = decayRamp[safeIndex(min(0.99, t), count: decayRamp.count)]
                            output[x, y] = dim(ASCIICell(glyph, cell.red, cell.green, cell.blue), 1.0 - t * 0.8)
                        } else if colHasContent {
                            let glyph = rainGlyphs[safeIndex(TerminalSaverNoise.value(x, y, seed &+ 473), count: rainGlyphs.count)]
                            output[x, y] = dim(ASCIICell(glyph, 80, 175, 115), max(0.0, (1.0 - t) * 0.45))
                        }
                    }
                } else if entering {
                    output[x, y] = cell
                }
            }
        }
        return output
    }

    private static func rippleWake(_ base: ASCIIFrame, _ progress: Double, _ seed: Int, entering: Bool) -> ASCIIFrame {
        let cols = base.columns
        let rows = base.rows
        var output = ASCIIFrame(columns: cols, rows: rows)
        guard cols > 0, rows > 0, !base.isBlank else { return output }

        let cx = Double(cols) * 0.5
        let cy = Double(rows) * 0.5
        let maxRadius = hypot(cx * 0.5, cy) + 3.0
        let ringWidth = max(2.2, Double(min(cols / 2, rows)) * 0.22)
        let eased = progress * progress * (3.0 - 2.0 * progress)
        let waveRadius = eased * (maxRadius + ringWidth) - ringWidth * 0.5

        for y in 0..<rows {
            for x in 0..<cols {
                let rx = Double(x) + 0.5 - cx
                let ry = Double(y) + 0.5 - cy
                let dist = hypot(rx * 0.5, ry)
                let delta = dist - waveRadius

                if delta < -ringWidth {
                    if entering { output[x, y] = base[x, y] }
                } else if delta > ringWidth {
                    if !entering { output[x, y] = base[x, y] }
                } else {
                    let u = max(0.0, 1.0 - abs(delta) / ringWidth)
                    let crest = 0.5 - 0.5 * cos(u * .pi)
                    let rLen = max(0.001, hypot(rx, ry))
                    let push = crest * 2.5
                    let offX = Int((rx / rLen * push).rounded())
                    let offY = Int((ry / rLen * push * 0.6).rounded())

                    let displaced = entering ? base[x - offX, y - offY] : base[x + offX, y + offY]
                    let sampled = !displaced.isBlank ? displaced : base[x, y]
                    guard !sampled.isBlank else { continue }

                    if crest > 0.45 {
                        let glyph = waveGlyphs[safeIndex(TerminalSaverNoise.value(x, y, Int(crest * 10) &+ seed &+ 479), count: waveGlyphs.count)]
                        output[x, y] = boost(ASCIICell(glyph, sampled.red, sampled.green, sampled.blue), crest * 0.55)
                    } else {
                        output[x, y] = boost(sampled, crest * 0.25)
                    }
                }
            }
        }
        return output
    }
}
