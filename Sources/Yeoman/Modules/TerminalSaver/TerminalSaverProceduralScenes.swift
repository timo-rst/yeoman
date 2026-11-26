import Foundation

/// Built-in filigree scenes rendered directly into ASCII frames (no imported media required).
public enum TerminalSaverProceduralScenes {
    public static func frame(
        scene: TerminalSaverBuiltInScene,
        columns: Int,
        rows: Int,
        time: Double,
        settings: TerminalSaverSceneSettings = TerminalSaverSceneSettings()
    ) -> ASCIIFrame {
        let size = TerminalSaverPolicy.clampedGrid(columns: columns, rows: rows)
        let t = time.isFinite ? max(0, min(time, 1e9)) : 0
        var frame: ASCIIFrame
        switch scene {
        case .bonfire: frame = bonfire(size.columns, size.rows, t)
        case .bouncingDVD: frame = bouncingDVD(size.columns, size.rows, t)
        case .starfield: frame = starfield(size.columns, size.rows, t)
        case .windMeadow: frame = windMeadow(size.columns, size.rows, t)
        case .matrix: frame = matrix(size.columns, size.rows, t)
        case .gameOfLife: frame = gameOfLife(size.columns, size.rows, t)
        case .pipes: frame = pipes(size.columns, size.rows, t)
        case .spinningDonut:
            // Keep the darkest shaded cells visible, as in the scene's original ramp.
            let ramp = settings.style.map { Array($0.ramp.dropFirst()) } ?? donutRamp
            frame = spinningDonut(size.columns, size.rows, t, ramp: ramp)
        }
        guard settings.colorPreset != .original else { return frame }
        for index in frame.cells.indices {
            let cell = frame.cells[index]
            guard !cell.isBlank else { continue }
            let red = Float(cell.red) / 255
            let green = Float(cell.green) / 255
            let blue = Float(cell.blue) / 255
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let (r, g, b) = settings.colorPreset.grade(red: red, green: green, blue: blue, luminance: luminance)
            frame.cells[index] = ASCIICell(cell.character, r, g, b)
        }
        return frame
    }

    @inline(__always)
    private static func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }

    private static func noise(_ x: Int, _ y: Int, _ z: Int = 0) -> Double { TerminalSaverNoise.value(x, y, z) }

    // MARK: - Dungeon Bonfire

    private static func bonfire(_ columns: Int, _ rows: Int, _ t: Double) -> ASCIIFrame {
        var frame = ASCIIFrame(columns: columns, rows: rows)
        let cx = Double(columns) / 2
        let baseY = Double(rows - 2)
        let fireHeight = max(3.0, Double(rows) * 0.55)
        let fireWidth = max(3.0, min(Double(columns) * 0.18, fireHeight * 1.6))
        let tick = Int(t * 12)

        for y in 0..<(rows - 1) {
            let dy = (baseY - Double(y)) / fireHeight
            guard dy >= 0, dy < 1.0 else { continue }
            let sway = sin(t * 3.2 + Double(y) * 0.35) * 0.85 * dy + sin(t * 5.8 - Double(y) * 0.55) * 0.35 * dy
            let width = max(0.8, fireWidth * (1.0 - dy * 0.82))
            for x in 0..<columns {
                let dx = abs(Double(x) - cx - sway) / width
                guard dx < 1.15 else { continue }
                let flicker = noise(x, y, tick)
                let radial = max(0.0, 1.0 - dx)
                let vertical = max(0.0, 1.0 - dy)
                let baseHeat = pow(radial, 1.15) * pow(vertical, 0.85)
                let heat = baseHeat + (flicker - 0.5) * 0.32 * max(0.0, 1.0 - dx * 0.9)
                guard heat > 0.06 else { continue }

                let character: Character
                if heat > 0.62 {
                    character = flicker > 0.5 ? "^" : "*"
                } else if heat > 0.38 {
                    character = Double(x) < cx + sway ? "(" : ")"
                } else if heat > 0.2 {
                    character = "~"
                } else {
                    character = flicker > 0.5 ? "'" : "."
                }
                let h = min(1.0, heat)
                frame.put(x, y, character, 255, byte(60 + 195 * h), byte(20 + 120 * max(0.0, h - 0.55)))
            }
        }

        let emberCount = max(6, columns / 5)
        let life = max(3.0, Double(rows) * 0.9)
        for i in 0..<emberCount {
            let speed = 3 + noise(i, 1) * 4
            let rise = (t * speed + noise(i, 2) * life).truncatingRemainder(dividingBy: life)
            let py = Int(baseY - rise)
            let px = Int(cx + (noise(i, 3) - 0.5) * fireWidth * 1.8 + sin(t * 1.5 + Double(i)) * 2)
            let fade = 1 - rise / life
            frame.put(px, py, noise(i, Int(t * 4)) > 0.5 ? "." : "'", 255, byte(120 + 80 * fade), byte(40 * fade))
        }

        let logStart = max(0, Int(cx - fireWidth * 0.95))
        let logEnd = min(columns - 1, Int(cx + fireWidth * 0.95))
        if logStart <= logEnd {
            for x in logStart...logEnd {
                let glyph: Character = x % 3 == 0 ? "/" : (x % 3 == 1 ? "=" : "\\")
                frame.put(x, rows - 1, glyph, 150, 90, 45)
            }
        }
        return frame
    }

    // MARK: - Bouncing DVD

    private static let dvdLogo: [[Character]] = [
        #" ____   __   __  ____"#,
        #"|  _ \  \ \ / / |  _ \"#,
        #"| | | |  \ V /  | | | |"#,
        #"| |_| |   \ /   | |_| |"#,
        #"|____/     V    |____/"#,
        #"   .---------------."#,
        #"   '------(_)------'"#
    ].map(Array.init)

    private static let compactDVDLogo: [[Character]] = [" .-------.", " | D V D |", " '---o---'"].map(Array.init)
    private static let smallDVDLogo: [[Character]] = [" DVD ", "'-o-'"].map(Array.init)
    private static let dvdColors: [(UInt8, UInt8, UInt8)] = [
        (82, 219, 255), (255, 94, 174), (255, 216, 88),
        (129, 245, 126), (177, 143, 255), (255, 153, 93)
    ]

    private static func bouncingDVD(_ columns: Int, _ rows: Int, _ t: Double) -> ASCIIFrame {
        var frame = ASCIIFrame(columns: columns, rows: rows)
        let logo: [[Character]]
        if columns >= 36 && rows >= 11 {
            logo = dvdLogo
        } else if columns >= 16 && rows >= 7 {
            logo = compactDVDLogo
        } else {
            logo = smallDVDLogo
        }

        let width = logo.map(\.count).max() ?? 0
        let horizontal = reflectedPosition(distance: t * 12, span: columns - width)
        let vertical = reflectedPosition(distance: t * 5, span: rows - logo.count)
        let (red, green, blue) = dvdColors[(horizontal.bounces + vertical.bounces) % dvdColors.count]

        for (row, glyphs) in logo.enumerated() {
            for (column, glyph) in glyphs.enumerated() where glyph != " " {
                frame.put(horizontal.offset + column, vertical.offset + row, glyph, red, green, blue)
            }
        }
        return frame
    }

    private static func reflectedPosition(distance: Double, span: Int) -> (offset: Int, bounces: Int) {
        guard span > 0 else { return (0, 0) }
        let extent = Double(span)
        let bounces = Int(distance / extent)
        let remainder = distance.truncatingRemainder(dividingBy: extent)
        let position = bounces.isMultiple(of: 2) ? remainder : extent - remainder
        return (Int(position.rounded()), bounces)
    }

    // MARK: - Astral Drift

    private static func starfield(_ columns: Int, _ rows: Int, _ t: Double) -> ASCIIFrame {
        var frame = ASCIIFrame(columns: columns, rows: rows)
        let speeds = [0.6, 1.6, 3.4]
        let densities = [28, 60, 130]
        for layer in 0..<3 {
            let count = max(4, columns * rows / densities[layer])
            for i in 0..<count {
                let span = Double(columns)
                let raw = noise(i, layer, 1) * span - t * speeds[layer]
                let x = Int(((raw.truncatingRemainder(dividingBy: span)) + span).truncatingRemainder(dividingBy: span))
                let y = Int(noise(i, layer, 2) * Double(rows))
                let twinkle = sin(t * (1 + noise(i, layer, 3) * 3) + noise(i, layer, 4) * 6.283)
                let character: Character
                switch layer {
                case 2: character = twinkle > 0.55 ? "*" : "+"
                case 1: character = twinkle > 0.3 ? "+" : "'"
                default: character = twinkle > 0.7 ? "'" : "."
                }
                let level = 0.45 + 0.2 * Double(layer) + 0.25 * max(0, twinkle)
                let tint = noise(i, layer, 5)
                frame.put(x, y, character, byte(255 * level * (0.8 + 0.2 * tint)), byte(255 * level * 0.9), byte(255 * level))
            }
        }

        let period = 6.0
        let phase = t.truncatingRemainder(dividingBy: period) / period
        if phase < 0.25 {
            let cycle = Int(t / period)
            let startX = noise(cycle, 31) * Double(columns) * 0.6
            let startY = noise(cycle, 32) * Double(rows) * 0.4
            let progress = phase / 0.25
            for k in 0..<6 {
                let along = progress * Double(columns) * 0.5 - Double(k) * 1.5
                guard along >= 0 else { continue }
                let fade = 1 - Double(k) / 6
                frame.put(Int(startX + along), Int(startY + along / 2), "\\", byte(255 * fade), byte(240 * fade), byte(200 * fade))
            }
        }
        return frame
    }

    // MARK: - Wind Meadow

    private static func windMeadow(_ columns: Int, _ rows: Int, _ t: Double) -> ASCIIFrame {
        var frame = ASCIIFrame(columns: columns, rows: rows)

        for i in 0..<max(3, columns * rows / 120) {
            let x = Int(noise(i, 41) * Double(columns))
            let y = Int(noise(i, 42) * Double(rows) * 0.35)
            let twinkle = sin(t * 1.3 + noise(i, 43) * 6.283)
            if twinkle > -0.2 { frame.put(x, y, ".", 130, 140, 170) }
        }

        for x in 0..<columns where noise(x, 22) >= 0.15 {
            let height = max(1, Int(Double(rows) * (0.22 + 0.3 * noise(x, 21))))
            let gust = sin(Double(x) * 0.12 - t * 1.4) * 0.6 + sin(Double(x) * 0.05 - t * 0.6) * 0.4
            for k in 0..<height {
                let y = rows - 1 - k
                let fraction = Double(k) / Double(height)
                let bend = gust * fraction
                let bx = x + Int((bend * fraction * 2.5).rounded())
                let character: Character
                if k == height - 1 {
                    character = bend > 0.25 ? "'" : (bend < -0.25 ? "`" : ",")
                } else if abs(bend) < 0.2 {
                    character = "|"
                } else {
                    character = bend > 0 ? "/" : "\\"
                }
                frame.put(bx, y, character, byte(60 + 50 * fraction), byte(130 + 100 * fraction), byte(55 + 20 * fraction))
            }
        }

        for i in 0..<max(3, columns / 12) {
            let span = Double(columns)
            let drift = (noise(i, 51) * span + t * (4 + noise(i, 52) * 4)).truncatingRemainder(dividingBy: span)
            let y = Int(Double(rows) * (0.35 + 0.3 * noise(i, 53)) + sin(t * 2 + Double(i)) * 1.5)
            frame.put(Int(drift), y, ".", 235, 230, 185)
        }
        return frame
    }

    // MARK: - Matrix Rain

    private static let matrixGlyphs: [Character] = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz:.*+=<>|/-$#%&"
    )

    private static func matrix(_ columns: Int, _ rows: Int, _ t: Double) -> ASCIIFrame {
        var frame = ASCIIFrame(columns: columns, rows: rows)
        var bestFade = [Double](repeating: -1, count: columns * rows)

        for x in 0..<columns {
            for stream in 0..<2 {
                if stream == 0 {
                    if columns <= 12 {
                        guard x % 2 == 0 else { continue }
                    } else {
                        guard noise(x, 100) < 0.75 else { continue }
                    }
                } else {
                    guard noise(x, 101) < 0.38 else { continue }
                }

                let speed = 7.0 + noise(x, stream, 102) * 11.0
                let length = max(3, min(rows, Int(Double(rows) * (0.30 + 0.50 * noise(x, stream, 103)))))
                let gap = 4 + Int(noise(x, stream, 104) * Double(max(4, rows / 2)))
                let cycle = Double(rows + length + gap)
                let head = Int((t * speed + noise(x, stream, 105) * cycle).truncatingRemainder(dividingBy: cycle))

                for k in 0..<length {
                    let y = head - k
                    guard y >= 0, y < rows else { continue }
                    let fade = 1.0 - Double(k) / Double(length)
                    let priority = (k == 0) ? 2.0 : fade
                    let cellIdx = y * columns + x
                    guard priority > bestFade[cellIdx] else { continue }
                    bestFade[cellIdx] = priority

                    let tickRate = (k == 0) ? 14.0 : (4.0 + noise(x, y, 106) * 4.0)
                    let tick = Int((t * tickRate).rounded(.down))
                    let glyphIndex = min(
                        matrixGlyphs.count - 1,
                        max(0, Int(noise(x, y, tick &+ 200) * Double(matrixGlyphs.count)))
                    )
                    let ch = matrixGlyphs[glyphIndex]
                    if k == 0 {
                        frame.put(x, y, ch, 225, 255, 230)
                    } else if fade > 0.65 {
                        frame.put(x, y, ch, 45, byte(185 + 70 * fade), byte(65 + 45 * fade))
                    } else {
                        frame.put(x, y, ch, byte(10 + 25 * fade), byte(45 + 165 * fade), byte(18 + 40 * fade))
                    }
                }
            }
        }
        return frame
    }

    // MARK: - Conway's Game of Life

    private static let gameOfLifeCache = GameOfLifeCache()

    private static func gameOfLife(_ columns: Int, _ rows: Int, _ t: Double) -> ASCIIFrame {
        let targetGen = Int((t * 8.0).rounded(.down))
        let (alive, decay) = gameOfLifeCache.snapshot(columns: columns, rows: rows, targetGen: targetGen)
        var frame = ASCIIFrame(columns: columns, rows: rows)

        for y in 0..<rows {
            let rowOffset = y * columns
            for x in 0..<columns {
                let idx = rowOffset + x
                let age = alive[idx]
                if age > 0 {
                    if age == 1 {
                        frame.put(x, y, "*", 200, 255, 245)
                    } else if age <= 4 {
                        frame.put(x, y, "o", 65, 235, 190)
                    } else {
                        frame.put(x, y, "+", 55, 175, 215)
                    }
                } else {
                    let afterglow = decay[idx]
                    if afterglow == 2 {
                        frame.put(x, y, ":", 55, 95, 145)
                    } else if afterglow == 1 {
                        frame.put(x, y, ".", 35, 55, 95)
                    }
                }
            }
        }
        return frame
    }

    // MARK: - Pipes

    private static let pipesCache = PipesCache()
    private static let pipePalette: [(UInt8, UInt8, UInt8)] = [
        (80, 225, 245),
        (85, 235, 145),
        (255, 195, 75),
        (255, 115, 115),
        (185, 130, 255),
        (115, 175, 255)
    ]

    private static func pipes(_ columns: Int, _ rows: Int, _ t: Double) -> ASCIIFrame {
        let targetStep = Int((t * 18.0).rounded(.down))
        let snapshot = pipesCache.snapshot(columns: columns, rows: rows, targetStep: targetStep)
        let fadeLifetime = max(60, min(260, (columns * rows) / 6))
        var frame = ASCIIFrame(columns: columns, rows: rows)

        for y in 0..<rows {
            let rowOffset = y * columns
            for x in 0..<columns {
                let idx = rowOffset + x
                let stamp = snapshot.stampSteps[idx]
                guard stamp != Int.min else { continue }
                let age = snapshot.step - stamp
                guard age >= 0, age < fadeLifetime else { continue }
                let fade = 1.0 - Double(age) / Double(fadeLifetime)
                let brightness = 0.22 + 0.78 * fade
                let baseColor = pipePalette[Int(snapshot.colorIndices[idx]) % pipePalette.count]
                frame.put(
                    x,
                    y,
                    snapshot.glyphs[idx],
                    byte(Double(baseColor.0) * brightness),
                    byte(Double(baseColor.1) * brightness),
                    byte(Double(baseColor.2) * brightness)
                )
            }
        }

        for head in snapshot.heads {
            let baseColor = pipePalette[Int(head.colorIndex) % pipePalette.count]
            let r = byte(Double(baseColor.0) * 0.65 + 255.0 * 0.35)
            let g = byte(Double(baseColor.1) * 0.65 + 255.0 * 0.35)
            let b = byte(Double(baseColor.2) * 0.65 + 255.0 * 0.35)
            frame.put(head.x, head.y, "o", r, g, b)
        }
        return frame
    }

    // MARK: - 3D Spinning Donut

    private static let donutRamp: [Character] = Array(".,-~:;=!*#$@")

    private static func spinningDonut(_ columns: Int, _ rows: Int, _ t: Double, ramp: [Character]) -> ASCIIFrame {
        var frame = ASCIIFrame(columns: columns, rows: rows)
        let cellCount = columns * rows
        var zBuffer = [Double](repeating: 0, count: cellCount)
        var lumBuffer = [Double](repeating: -1, count: cellCount)

        let angleA = t * 1.15
        let angleB = t * 0.62
        let cosA = cos(angleA)
        let sinA = sin(angleA)
        let cosB = cos(angleB)
        let sinB = sin(angleB)

        let r1 = 1.0
        let r2 = 2.0
        let k2 = 5.0
        let k1y = Double(min(rows, max(5, columns / 2))) * 0.56
        let k1x = k1y * 2.0
        let halfCols = Double(columns) * 0.5
        let halfRows = Double(rows) * 0.5

        let thetaStep = rows > 25 ? 0.06 : 0.09
        let phiStep = rows > 25 ? 0.022 : 0.035

        var theta = 0.0
        while theta < 6.28318530718 {
            let cosT = cos(theta)
            let sinT = sin(theta)
            let circleX = r2 + r1 * cosT
            let circleY = r1 * sinT

            var phi = 0.0
            while phi < 6.28318530718 {
                let cosP = cos(phi)
                let sinP = sin(phi)

                let x3 = circleX * (cosB * cosP + sinA * sinB * sinP) - circleY * cosA * sinB
                let y3 = circleX * (sinB * cosP - sinA * cosB * sinP) + circleY * cosA * cosB
                let z3 = k2 + cosA * circleX * sinP + circleY * sinA

                if z3 > 0.1 {
                    let ooz = 1.0 / z3
                    let xp = Int(halfCols + k1x * ooz * x3)
                    let yp = Int(halfRows - k1y * ooz * y3)
                    if xp >= 0, xp < columns, yp >= 0, yp < rows {
                        let luminance = cosP * cosT * sinB
                            - cosA * cosT * sinP
                            - sinA * sinT
                            + cosB * (cosA * sinT - cosT * sinA * sinP)
                        if luminance > -0.15 {
                            let idx = yp * columns + xp
                            if ooz > zBuffer[idx] {
                                zBuffer[idx] = ooz
                                lumBuffer[idx] = max(0.0, min(1.0, (luminance + 0.15) / 1.56))
                            }
                        }
                    }
                }
                phi += phiStep
            }
            theta += thetaStep
        }

        for y in 0..<rows {
            let rowOffset = y * columns
            for x in 0..<columns {
                let lum = lumBuffer[rowOffset + x]
                guard lum >= 0 else { continue }
                let shadeIndex = Int((lum * Double(ramp.count - 1)).rounded())
                let r: UInt8
                let g: UInt8
                let b: UInt8
                if lum <= 0.72 {
                    let u = lum / 0.72
                    r = byte(70 + 20 * u)
                    g = byte(95 + 120 * u)
                    b = byte(175 + 65 * u)
                } else {
                    let u = (lum - 0.72) / 0.28
                    r = byte(90 + 165 * u)
                    g = byte(215 + 25 * u)
                    b = byte(240 - 45 * u)
                }
                frame.put(x, y, ramp[shadeIndex], r, g, b)
            }
        }
        return frame
    }
}

private final class GameOfLifeCache: @unchecked Sendable {
    private struct GridKey: Equatable {
        let columns: Int
        let rows: Int
    }

    private struct State {
        let key: GridKey
        var generation: Int
        var alive: [UInt8]
        var decay: [UInt8]
        var prevHash1: UInt64
        var prevHash2: UInt64
        var stagnantCount: Int
    }

    private let lock = NSLock()
    private var entries: [State] = []
    private static let maxCachedGrids = 4
    private static let maxIncrementalSteps = 32
    private static let rPentominoOffsets = [(1, 0), (2, 0), (0, 1), (1, 1), (1, 2)]
    private static let gliderOffsets = [(1, 0), (2, 1), (0, 2), (1, 2), (2, 2)]

    func snapshot(columns: Int, rows: Int, targetGen: Int) -> (alive: [UInt8], decay: [UInt8]) {
        let key = GridKey(columns: columns, rows: rows)
        lock.lock()
        defer { lock.unlock() }

        var state: State
        if let idx = entries.firstIndex(where: { $0.key == key }),
           targetGen >= entries[idx].generation,
           targetGen - entries[idx].generation <= Self.maxIncrementalSteps {
            state = entries.remove(at: idx)
        } else {
            entries.removeAll(where: { $0.key == key })
            let epoch = targetGen / Self.maxIncrementalSteps
            state = Self.seed(columns: columns, rows: rows, epoch: epoch)
        }

        let steps = targetGen - state.generation
        if steps > 0 {
            for _ in 0..<steps {
                Self.advance(&state)
            }
        }

        if entries.count >= Self.maxCachedGrids {
            entries.removeFirst()
        }
        entries.append(state)
        return (state.alive, state.decay)
    }

    private static func seed(columns: Int, rows: Int, epoch: Int) -> State {
        let count = columns * rows
        var alive = [UInt8](repeating: 0, count: count)
        let seedSalt = 300 &+ epoch &* 17
        for y in 0..<rows {
            let rowOffset = y * columns
            for x in 0..<columns where TerminalSaverNoise.value(x, y, seedSalt) < 0.30 {
                alive[rowOffset + x] = 1
            }
        }

        var state = State(
            key: GridKey(columns: columns, rows: rows),
            generation: epoch * maxIncrementalSteps,
            alive: alive,
            decay: [UInt8](repeating: 0, count: count),
            prevHash1: 0,
            prevHash2: 0,
            stagnantCount: 0
        )
        stamp(pattern: rPentominoOffsets, originX: columns / 2 - 1, originY: rows / 2 - 1, into: &state)
        if columns >= 16 && rows >= 8 {
            stamp(pattern: gliderOffsets, originX: 2, originY: 1, into: &state)
        }
        return state
    }

    private static func advance(_ state: inout State) {
        let cols = state.key.columns
        let rows = state.key.rows
        let count = cols * rows
        var nextAlive = [UInt8](repeating: 0, count: count)
        var nextDecay = [UInt8](repeating: 0, count: count)
        var population = 0
        var hash: UInt64 = 14695981039346656037

        for y in 0..<rows {
            let ym1 = ((y == 0) ? (rows - 1) : (y - 1)) * cols
            let y0 = y * cols
            let yp1 = ((y + 1 == rows) ? 0 : (y + 1)) * cols

            for x in 0..<cols {
                let xm1 = (x == 0) ? (cols - 1) : (x - 1)
                let xp1 = (x + 1 == cols) ? 0 : (x + 1)

                var neighbors = 0
                if state.alive[ym1 + xm1] > 0 { neighbors += 1 }
                if state.alive[ym1 + x] > 0 { neighbors += 1 }
                if state.alive[ym1 + xp1] > 0 { neighbors += 1 }
                if state.alive[y0 + xm1] > 0 { neighbors += 1 }
                if state.alive[y0 + xp1] > 0 { neighbors += 1 }
                if state.alive[yp1 + xm1] > 0 { neighbors += 1 }
                if state.alive[yp1 + x] > 0 { neighbors += 1 }
                if state.alive[yp1 + xp1] > 0 { neighbors += 1 }

                let idx = y0 + x
                let prevAge = state.alive[idx]
                if prevAge > 0 {
                    if neighbors == 2 || neighbors == 3 {
                        nextAlive[idx] = prevAge == UInt8.max ? UInt8.max : prevAge + 1
                        population += 1
                    } else {
                        nextDecay[idx] = 2
                    }
                } else {
                    if neighbors == 3 {
                        nextAlive[idx] = 1
                        population += 1
                    } else if state.decay[idx] > 0 {
                        nextDecay[idx] = state.decay[idx] - 1
                    }
                }

                hash ^= UInt64(nextAlive[idx] > 0 ? 1 : 0)
                hash &*= 1099511628211
            }
        }

        state.alive = nextAlive
        state.decay = nextDecay
        state.generation &+= 1

        if hash == state.prevHash1 || hash == state.prevHash2 || population < max(3, count / 55) {
            state.stagnantCount += 1
        } else {
            state.stagnantCount = 0
        }
        state.prevHash2 = state.prevHash1
        state.prevHash1 = hash

        if population == 0 || state.stagnantCount >= 8 {
            let ox = Int(TerminalSaverNoise.value(state.generation, cols, rows) * Double(cols))
            let oy = Int(TerminalSaverNoise.value(state.generation, rows, cols) * Double(rows))
            stamp(pattern: rPentominoOffsets, originX: ox, originY: oy, into: &state)
            if cols >= 16 && rows >= 8 {
                stamp(pattern: gliderOffsets, originX: ox + cols / 3, originY: oy + rows / 3, into: &state)
            }
            state.stagnantCount = 0
        }
    }

    private static func stamp(pattern: [(Int, Int)], originX: Int, originY: Int, into state: inout State) {
        let cols = state.key.columns
        let rows = state.key.rows
        for (dx, dy) in pattern {
            let px = ((originX + dx) % cols + cols) % cols
            let py = ((originY + dy) % rows + rows) % rows
            let idx = py * cols + px
            if state.alive[idx] == 0 {
                state.alive[idx] = 1
                state.decay[idx] = 0
            }
        }
    }
}

private final class PipesCache: @unchecked Sendable {
    struct PipeHead {
        var x: Int
        var y: Int
        var direction: Int
        var colorIndex: UInt8
        var stepsSinceTurn: Int
        var length: Int
    }

    struct Snapshot {
        let step: Int
        let glyphs: [Character]
        let colorIndices: [UInt8]
        let stampSteps: [Int]
        let heads: [PipeHead]
    }

    private struct GridKey: Equatable {
        let columns: Int
        let rows: Int
    }

    private struct State {
        let key: GridKey
        var step: Int
        var glyphs: [Character]
        var colorIndices: [UInt8]
        var stampSteps: [Int]
        var heads: [PipeHead]
    }

    private let lock = NSLock()
    private var entries: [State] = []
    private static let maxCachedGrids = 4
    private static let maxIncrementalSteps = 48
    private static let warmupSteps = 24
    private static let paletteCount = 6

    func snapshot(columns: Int, rows: Int, targetStep: Int) -> Snapshot {
        let key = GridKey(columns: columns, rows: rows)
        lock.lock()
        defer { lock.unlock() }

        var state: State
        if let idx = entries.firstIndex(where: { $0.key == key }),
           targetStep >= entries[idx].step,
           targetStep - entries[idx].step <= Self.maxIncrementalSteps {
            state = entries.remove(at: idx)
        } else {
            entries.removeAll(where: { $0.key == key })
            let epoch = targetStep / Self.maxIncrementalSteps
            state = Self.seed(columns: columns, rows: rows, epoch: epoch)
        }

        let steps = targetStep - state.step
        if steps > 0 {
            for _ in 0..<steps {
                Self.advance(&state)
            }
        }

        if entries.count >= Self.maxCachedGrids {
            entries.removeFirst()
        }
        entries.append(state)
        return Snapshot(
            step: state.step,
            glyphs: state.glyphs,
            colorIndices: state.colorIndices,
            stampSteps: state.stampSteps,
            heads: state.heads
        )
    }

    private static func seed(columns: Int, rows: Int, epoch: Int) -> State {
        let count = columns * rows
        let pipeCount = max(2, min(6, count / 450 + 2))
        let baseStep = epoch * maxIncrementalSteps
        var heads: [PipeHead] = []
        heads.reserveCapacity(pipeCount)

        for i in 0..<pipeCount {
            let hx = Int(TerminalSaverNoise.value(i, epoch, 500) * Double(columns))
            let hy = Int(TerminalSaverNoise.value(i, epoch, 501) * Double(rows))
            let dir = Int(TerminalSaverNoise.value(i, epoch, 502) * 4.0) % 4
            heads.append(
                PipeHead(
                    x: min(max(0, hx), columns - 1),
                    y: min(max(0, hy), rows - 1),
                    direction: dir,
                    colorIndex: UInt8(i % paletteCount),
                    stepsSinceTurn: 0,
                    length: 0
                )
            )
        }

        var state = State(
            key: GridKey(columns: columns, rows: rows),
            step: baseStep - warmupSteps,
            glyphs: [Character](repeating: " ", count: count),
            colorIndices: [UInt8](repeating: 0, count: count),
            stampSteps: [Int](repeating: Int.min, count: count),
            heads: heads
        )
        for _ in 0..<warmupSteps {
            advance(&state)
        }
        return state
    }

    private static func advance(_ state: inout State) {
        let cols = state.key.columns
        let rows = state.key.rows
        state.step &+= 1
        let stepTag = state.step

        for i in 0..<state.heads.count {
            var head = state.heads[i]
            var newDir = head.direction
            var resetTurnCounter = false

            if head.stepsSinceTurn >= 2 {
                let roll = TerminalSaverNoise.value(stepTag, i, 510)
                if roll < 0.22 {
                    let turnLeft = TerminalSaverNoise.value(stepTag, i, 511) < 0.5
                    newDir = (head.direction + (turnLeft ? 3 : 1)) % 4
                    resetTurnCounter = true
                }
            }

            let idx = head.y * cols + head.x
            state.glyphs[idx] = cornerGlyph(from: head.direction, to: newDir)
            state.colorIndices[idx] = head.colorIndex
            state.stampSteps[idx] = stepTag

            let dx: Int
            let dy: Int
            switch newDir {
            case 0: (dx, dy) = (1, 0)
            case 1: (dx, dy) = (0, 1)
            case 2: (dx, dy) = (-1, 0)
            default: (dx, dy) = (0, -1)
            }

            head.x = (head.x + dx + cols) % cols
            head.y = (head.y + dy + rows) % rows
            head.direction = newDir
            head.stepsSinceTurn = resetTurnCounter ? 0 : (head.stepsSinceTurn + 1)
            head.length += 1

            if head.length >= 120 {
                let nx = Int(TerminalSaverNoise.value(stepTag, i, 520) * Double(cols))
                let ny = Int(TerminalSaverNoise.value(stepTag, i, 521) * Double(rows))
                head.x = min(max(0, nx), cols - 1)
                head.y = min(max(0, ny), rows - 1)
                head.direction = Int(TerminalSaverNoise.value(stepTag, i, 522) * 4.0) % 4
                head.colorIndex = UInt8((Int(head.colorIndex) + 1) % paletteCount)
                head.stepsSinceTurn = 0
                head.length = 0
            }

            state.heads[i] = head
        }
    }

    private static func cornerGlyph(from oldDir: Int, to newDir: Int) -> Character {
        if oldDir == newDir {
            return (newDir == 0 || newDir == 2) ? "─" : "│"
        }
        switch (oldDir, newDir) {
        case (0, 1), (3, 2): return "╮"
        case (0, 3), (1, 2): return "╯"
        case (2, 1), (3, 0): return "╭"
        case (2, 3), (1, 0): return "╰"
        default: return (newDir == 0 || newDir == 2) ? "─" : "│"
        }
    }
}
