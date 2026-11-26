import Foundation
import CoreGraphics

public struct ASCIICell: Equatable {
    public var character: Character
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(_ character: Character, _ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.character = character
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let blank = ASCIICell(" ", 0, 0, 0)
    public var isBlank: Bool { character == " " }
}

public struct ASCIIFrame: Equatable {
    public let columns: Int
    public let rows: Int
    public var cells: [ASCIICell]

    public init(columns: Int, rows: Int, fill: ASCIICell = .blank) {
        self.columns = max(0, columns)
        self.rows = max(0, rows)
        self.cells = Array(repeating: fill, count: self.columns * self.rows)
    }

    @inline(__always)
    public func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < columns && y < rows
    }

    public subscript(x: Int, y: Int) -> ASCIICell {
        get { contains(x, y) ? cells[y * columns + x] : .blank }
        set { if contains(x, y) { cells[y * columns + x] = newValue } }
    }

    public mutating func put(_ x: Int, _ y: Int, _ character: Character, _ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self[x, y] = ASCIICell(character, red, green, blue)
    }

    public var isBlank: Bool { cells.allSatisfy(\.isBlank) }

    public func text(row y: Int) -> String {
        guard y >= 0, y < rows else { return "" }
        return String(cells[(y * columns)..<((y + 1) * columns)].map(\.character))
    }
}

public struct ASCIIContentBounds: Equatable {
    public let minX: Int
    public let maxX: Int
    public let minY: Int
    public let maxY: Int

    public init(minX: Int, maxX: Int, minY: Int, maxY: Int) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    public func contains(_ x: Int, _ y: Int) -> Bool {
        x >= minX && x < maxX && y >= minY && y < maxY
    }
}

/// Per-cell averaged RGB + alpha samples (0...1) produced from a source image.
public struct ASCIIPixelGrid: Equatable {
    public let columns: Int
    public let rows: Int
    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]
    public var alpha: [Float]
    public let contentBounds: ASCIIContentBounds

    public init(
        columns: Int,
        rows: Int,
        red: [Float],
        green: [Float],
        blue: [Float],
        alpha: [Float]? = nil,
        contentBounds: ASCIIContentBounds? = nil
    ) {
        let count = max(0, columns) * max(0, rows)
        self.columns = max(0, columns)
        self.rows = max(0, rows)
        self.red = red.count == count ? red : Array(repeating: 0, count: count)
        self.green = green.count == count ? green : Array(repeating: 0, count: count)
        self.blue = blue.count == count ? blue : Array(repeating: 0, count: count)
        if let alpha, alpha.count == count {
            self.alpha = alpha
        } else {
            self.alpha = Array(repeating: 1.0, count: count)
        }
        self.contentBounds = contentBounds ?? ASCIIContentBounds(minX: 0, maxX: self.columns, minY: 0, maxY: self.rows)
    }
}

public struct ASCIIRenderSettings: Equatable {
    public var style: ASCIIRenderStyle
    public var colorPreset: ASCIIColorPreset
    public var fitMode: ASCIIFitMode
    public var edgeDetail: Double
    public var darkFloor: Double
    public var gamma: Double

    public init(style: ASCIIRenderStyle = .filigree, colorPreset: ASCIIColorPreset = .original,
                fitMode: ASCIIFitMode = .contain, edgeDetail: Double = 0.55, darkFloor: Double = 0.08,
                gamma: Double = 1.15) {
        self.style = style
        self.colorPreset = colorPreset
        self.fitMode = fitMode
        self.edgeDetail = SecurityPolicy.bounded(edgeDetail, 0...1, fallback: 0.55)
        self.darkFloor = SecurityPolicy.bounded(darkFloor, 0...0.65, fallback: 0.08)
        self.gamma = SecurityPolicy.bounded(gamma, 0.6...3.5, fallback: 1.15)
    }

    public init(mediaItem: TerminalSaverMediaItem, config: TerminalSaverConfig = TerminalSaverConfig()) {
        self.init(
            style: mediaItem.style,
            colorPreset: mediaItem.colorPreset,
            fitMode: mediaItem.fitMode,
            edgeDetail: config.edgeDetail,
            darkFloor: config.darkFloor,
            gamma: config.gamma
        )
    }
}

/// Edge-aware, block-free ASCII renderer. Contours use directional strokes derived from a
/// 3x3 Sobel gradient; interiors use a fine luminance ramp over clean negative space.
public enum ASCIIRenderEngine {
    /// Supersampling factors per cell. Cells are roughly twice as tall as wide, so 2x4 samples are square.
    static let sampleWidth = 2
    static let sampleHeight = 4

    public static func render(image: CGImage, columns: Int, rows: Int, settings: ASCIIRenderSettings) -> ASCIIFrame {
        guard let grid = sample(image: image, columns: columns, rows: rows, fitMode: settings.fitMode) else {
            let size = TerminalSaverPolicy.clampedGrid(columns: columns, rows: rows)
            return ASCIIFrame(columns: size.columns, rows: size.rows)
        }
        return render(grid: grid, settings: settings)
    }

    /// Rasterizes `image` into an aspect-corrected grid of averaged cell colors.
    public static func sample(image: CGImage, columns: Int, rows: Int, fitMode: ASCIIFitMode) -> ASCIIPixelGrid? {
        let size = TerminalSaverPolicy.clampedGrid(columns: columns, rows: rows)
        let width = size.columns * sampleWidth
        let height = size.rows * sampleHeight
        guard image.width > 0, image.height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        let sx = Double(width) / Double(image.width)
        let sy = Double(height) / Double(image.height)
        let scale = fitMode == .contain ? min(sx, sy) : max(sx, sy)
        let drawWidth = Double(image.width) * scale
        let drawHeight = Double(image.height) * scale
        let drawX = (Double(width) - drawWidth) / 2
        let drawY = (Double(height) - drawHeight) / 2
        context.draw(image, in: CGRect(
            x: drawX,
            y: drawY,
            width: drawWidth,
            height: drawHeight
        ))

        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let count = size.columns * size.rows
        var red = [Float](repeating: 0, count: count)
        var green = [Float](repeating: 0, count: count)
        var blue = [Float](repeating: 0, count: count)
        var alpha = [Float](repeating: 1.0, count: count)
        let divisor = Float(sampleWidth * sampleHeight) * 255

        for cy in 0..<size.rows {
            // CoreGraphics bitmap rows are stored top-down in memory.
            for cx in 0..<size.columns {
                var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 0
                for py in 0..<sampleHeight {
                    let rowStart = (cy * sampleHeight + py) * width * 4
                    for px in 0..<sampleWidth {
                        let offset = rowStart + (cx * sampleWidth + px) * 4
                        r += UInt32(bytes[offset])
                        g += UInt32(bytes[offset + 1])
                        b += UInt32(bytes[offset + 2])
                        a += UInt32(bytes[offset + 3])
                    }
                }
                let index = cy * size.columns + cx
                let avgAlpha = Float(a) / divisor
                alpha[index] = avgAlpha
                if avgAlpha > 0.01 {
                    red[index] = min(1, (Float(r) / divisor) / avgAlpha)
                    green[index] = min(1, (Float(g) / divisor) / avgAlpha)
                    blue[index] = min(1, (Float(b) / divisor) / avgAlpha)
                }
            }
        }

        let minCellX = min(size.columns, max(0, Int((drawX / Double(sampleWidth)).rounded(.down))))
        let maxCellX = min(size.columns, max(minCellX, Int(((drawX + drawWidth) / Double(sampleWidth)).rounded(.up))))
        let minCellY = min(size.rows, max(0, Int((drawY / Double(sampleHeight)).rounded(.down))))
        let maxCellY = min(size.rows, max(minCellY, Int(((drawY + drawHeight) / Double(sampleHeight)).rounded(.up))))
        let bounds = ASCIIContentBounds(minX: minCellX, maxX: maxCellX, minY: minCellY, maxY: maxCellY)

        return ASCIIPixelGrid(columns: size.columns, rows: size.rows, red: red, green: green, blue: blue, alpha: alpha, contentBounds: bounds)
    }

    public static func render(grid: ASCIIPixelGrid, settings: ASCIIRenderSettings) -> ASCIIFrame {
        let columns = grid.columns
        let rows = grid.rows
        var frame = ASCIIFrame(columns: columns, rows: rows)
        guard columns > 0, rows > 0 else { return frame }

        let count = columns * rows
        let hasAlpha = grid.alpha.count == count
        var hasTransparency = false
        var luminance = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let a = hasAlpha ? grid.alpha[i] : 1.0
            if a < 0.35 {
                luminance[i] = 0
                hasTransparency = true
            } else {
                if a < 0.99 { hasTransparency = true }
                luminance[i] = 0.2126 * grid.red[i] + 0.7152 * grid.green[i] + 0.0722 * grid.blue[i]
            }
        }

        let bMinX = grid.contentBounds.minX < grid.contentBounds.maxX ? grid.contentBounds.minX : 0
        let bMaxX = grid.contentBounds.minX < grid.contentBounds.maxX ? grid.contentBounds.maxX - 1 : columns - 1
        let bMinY = grid.contentBounds.minY < grid.contentBounds.maxY ? grid.contentBounds.minY : 0
        let bMaxY = grid.contentBounds.minY < grid.contentBounds.maxY ? grid.contentBounds.maxY - 1 : rows - 1

        @inline(__always) func rawLum(_ x: Int, _ y: Int) -> Float {
            luminance[min(max(y, bMinY), bMaxY) * columns + min(max(x, bMinX), bMaxX)]
        }

        @inline(__always) func rawAlpha(_ x: Int, _ y: Int) -> Float {
            guard hasAlpha, grid.contentBounds.contains(x, y) else { return 0 }
            return grid.alpha[y * columns + x]
        }

        // 3x3 Gaussian denoise clamped to contentBounds so letterbox bars never cause false border edges.
        var smoothLum = [Float](repeating: 0, count: count)
        for y in 0..<rows {
            for x in 0..<columns {
                let sum = rawLum(x - 1, y - 1) + 2 * rawLum(x, y - 1) + rawLum(x + 1, y - 1)
                    + 2 * rawLum(x - 1, y) + 4 * rawLum(x, y) + 2 * rawLum(x + 1, y)
                    + rawLum(x - 1, y + 1) + 2 * rawLum(x, y + 1) + rawLum(x + 1, y + 1)
                smoothLum[y * columns + x] = sum / 16.0
            }
        }

        @inline(__always) func sLum(_ x: Int, _ y: Int) -> Float {
            smoothLum[min(max(y, bMinY), bMaxY) * columns + min(max(x, bMinX), bMaxX)]
        }

        var gradX = [Float](repeating: 0, count: count)
        var gradY = [Float](repeating: 0, count: count)
        var gradMag = [Float](repeating: 0, count: count)
        for y in 0..<rows {
            for x in 0..<columns {
                let idx = y * columns + x
                let gx = (sLum(x + 1, y - 1) + 2 * sLum(x + 1, y) + sLum(x + 1, y + 1))
                    - (sLum(x - 1, y - 1) + 2 * sLum(x - 1, y) + sLum(x - 1, y + 1))
                let gy = (sLum(x - 1, y + 1) + 2 * sLum(x, y + 1) + sLum(x + 1, y + 1))
                    - (sLum(x - 1, y - 1) + 2 * sLum(x, y - 1) + sLum(x + 1, y - 1))
                gradX[idx] = gx
                gradY[idx] = gy
                gradMag[idx] = (gx * gx + gy * gy).squareRoot()
            }
        }

        let ramp = settings.style.ramp
        let floor = Float(settings.darkFloor)
        let effectiveFloor = hasTransparency ? min(floor, 0.02) : floor
        let gamma = Float(settings.gamma)
        let edgesEnabled = settings.edgeDetail > 0
        let edgeThreshold = Float(1.5 - 1.25 * settings.edgeDetail)

        for y in 0..<rows {
            for x in 0..<columns {
                guard grid.contentBounds.contains(x, y) else { continue }
                let index = y * columns + x
                let a = hasAlpha ? grid.alpha[index] : 1.0
                if a < 0.35 {
                    continue
                }

                let l = luminance[index]
                let gx = gradX[index]
                let gy = gradY[index]
                let magnitude = gradMag[index]
                let isStrongEdge = edgesEnabled && magnitude >= edgeThreshold

                if hasTransparency {
                    let agx = (rawAlpha(x + 1, y - 1) + 2 * rawAlpha(x + 1, y) + rawAlpha(x + 1, y + 1))
                        - (rawAlpha(x - 1, y - 1) + 2 * rawAlpha(x - 1, y) + rawAlpha(x - 1, y + 1))
                    let agy = (rawAlpha(x - 1, y + 1) + 2 * rawAlpha(x, y + 1) + rawAlpha(x + 1, y + 1))
                        - (rawAlpha(x - 1, y - 1) + 2 * rawAlpha(x, y - 1) + rawAlpha(x + 1, y - 1))
                    let alphaGradMag = (agx * agx + agy * agy).squareRoot()
                    if alphaGradMag >= 1.2 && l < floor {
                        let liftLum = max(0.28, l)
                        let color = settings.colorPreset.grade(
                            red: max(grid.red[index], 0.25),
                            green: max(grid.green[index], 0.25),
                            blue: max(grid.blue[index], 0.25),
                            luminance: liftLum
                        )
                        frame.cells[index] = ASCIICell(edgeGlyph(gx: agx, gy: agy, style: settings.style), color.0, color.1, color.2)
                        continue
                    }
                }

                guard l >= effectiveFloor, l > 0 else {
                    if isStrongEdge {
                        let edgeLum = min(1, max(0.15, magnitude * 0.45))
                        let color = settings.colorPreset.grade(
                            red: grid.red[index], green: grid.green[index], blue: grid.blue[index], luminance: edgeLum
                        )
                        frame.cells[index] = ASCIICell(edgeGlyph(gx: gx, gy: gy, style: settings.style), color.0, color.1, color.2)
                    }
                    continue
                }

                let stretched = max(0, min(1, (l - effectiveFloor) / max(0.05, 1 - effectiveFloor)))
                let effectiveLum = powf(stretched, gamma)
                guard effectiveLum >= 0.02 || isStrongEdge else { continue }

                let character: Character = isStrongEdge
                    ? edgeGlyph(gx: gx, gy: gy, style: settings.style)
                    : rampGlyph(luminance: effectiveLum, floor: 0, ramp: ramp)

                let color = settings.colorPreset.grade(
                    red: grid.red[index], green: grid.green[index], blue: grid.blue[index], luminance: effectiveLum
                )
                frame.cells[index] = ASCIICell(character, color.0, color.1, color.2)
            }
        }
        return frame
    }

    /// Maps a luminance gradient to the stroke that runs perpendicular to it (screen y grows downward).
    public static func edgeGlyph(gx: Float, gy: Float, style: ASCIIRenderStyle) -> Character {
        let glyphs = style.edgeGlyphs
        var angle = atan2(Double(gy), Double(gx)) * 180 / .pi
        if angle < 0 { angle += 180 }
        if angle >= 180 { angle -= 180 }
        switch angle {
        case 22.5..<67.5: return glyphs.rising
        case 67.5..<112.5: return glyphs.horizontal
        case 112.5..<157.5: return glyphs.falling
        default: return glyphs.vertical
        }
    }

    public static func rampGlyph(luminance: Float, floor: Float, ramp: [Character]) -> Character {
        guard ramp.count > 1 else { return ramp.first ?? " " }
        let span = max(0.0001, 1 - floor)
        let normalized = max(0, min(1, (luminance - floor) / span))
        let index = 1 + Int((normalized * Float(ramp.count - 2)).rounded())
        return ramp[min(max(index, 1), ramp.count - 1)]
    }
}

public enum ASCIIColorMode: Equatable {
    case trueColor
    case palette256

    public static func detect(environment: [String: String]) -> ASCIIColorMode {
        let colorTerm = environment["COLORTERM"]?.lowercased() ?? ""
        if colorTerm.contains("truecolor") || colorTerm.contains("24bit") { return .trueColor }
        return .palette256
    }
}

public enum ASCIIANSIEncoder {
    public static let escape = "\u{1B}["

    public static func colorCode(_ red: UInt8, _ green: UInt8, _ blue: UInt8, mode: ASCIIColorMode) -> String {
        switch mode {
        case .trueColor:
            return "\(escape)38;2;\(red);\(green);\(blue)m"
        case .palette256:
            return "\(escape)38;5;\(xterm256Index(red, green, blue))m"
        }
    }

    /// Nearest xterm-256 index using the 6x6x6 cube or the 24-step gray ramp.
    public static func xterm256Index(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Int {
        let levels = [0, 95, 135, 175, 215, 255]
        func cubeIndex(_ value: Int) -> Int {
            if value < 48 { return 0 }
            if value < 115 { return 1 }
            return min(5, (value - 35) / 40)
        }
        let r = Int(red), g = Int(green), b = Int(blue)
        let ri = cubeIndex(r), gi = cubeIndex(g), bi = cubeIndex(b)
        let cubeDistance = (levels[ri] - r) * (levels[ri] - r) + (levels[gi] - g) * (levels[gi] - g) + (levels[bi] - b) * (levels[bi] - b)

        let average = (r + g + b) / 3
        let grayStep = min(23, max(0, (average - 8 + 5) / 10))
        let grayValue = 8 + grayStep * 10
        let grayDistance = (grayValue - r) * (grayValue - r) + (grayValue - g) * (grayValue - g) + (grayValue - b) * (grayValue - b)

        return grayDistance < cubeDistance ? 232 + grayStep : 16 + 36 * ri + 6 * gi + bi
    }

    /// Encodes only changed row spans since `previous`, coalescing identical color runs and clearing shrunk tails.
    public static func encode(_ frame: ASCIIFrame, previous: ASCIIFrame?, mode: ASCIIColorMode) -> String {
        let full = previous == nil || previous?.columns != frame.columns || previous?.rows != frame.rows
        var output = ""
        output.reserveCapacity(frame.cells.count * 2)

        for y in 0..<frame.rows {
            let rowStart = y * frame.columns
            let range = rowStart..<(rowStart + frame.columns)
            if !full, let prev = previous, prev.cells[range] == frame.cells[range] { continue }

            var lastNonBlank = frame.columns - 1
            while lastNonBlank >= 0, frame.cells[rowStart + lastNonBlank].isBlank {
                lastNonBlank -= 1
            }

            if lastNonBlank < 0 {
                output += "\(escape)\(y + 1);1H\(escape)0m\(escape)K"
                continue
            }

            guard let prev = previous, !full else {
                output += "\(escape)\(y + 1);1H"
                var lastCode: String?
                for x in 0...lastNonBlank {
                    let cell = frame.cells[rowStart + x]
                    if cell.isBlank {
                        output.append(" ")
                        continue
                    }
                    let code = colorCode(cell.red, cell.green, cell.blue, mode: mode)
                    if code != lastCode {
                        output += code
                        lastCode = code
                    }
                    output.append(cell.character)
                }
                output += "\(escape)0m"
                if lastNonBlank < frame.columns - 1 {
                    output += "\(escape)K"
                }
                continue
            }

            var prevLastNonBlank = prev.columns - 1
            while prevLastNonBlank >= 0, prev.cells[rowStart + prevLastNonBlank].isBlank {
                prevLastNonBlank -= 1
            }

            var cursorX = -1
            var x = 0
            while x <= lastNonBlank {
                if frame.cells[rowStart + x] == prev.cells[rowStart + x] {
                    x += 1
                    continue
                }
                let spanStart = x
                var spanEnd = x
                var probe = x + 1
                while probe <= lastNonBlank {
                    if frame.cells[rowStart + probe] != prev.cells[rowStart + probe] {
                        spanEnd = probe
                        probe += 1
                    } else {
                        var look = probe + 1
                        let limit = min(lastNonBlank, probe + 5)
                        var foundNext = false
                        while look <= limit {
                            if frame.cells[rowStart + look] != prev.cells[rowStart + look] {
                                foundNext = true
                                break
                            }
                            look += 1
                        }
                        if foundNext {
                            spanEnd = look
                            probe = look + 1
                        } else {
                            break
                        }
                    }
                }

                if cursorX != spanStart {
                    output += "\(escape)\(y + 1);\(spanStart + 1)H"
                }
                var lastCode: String?
                for cx in spanStart...spanEnd {
                    let cell = frame.cells[rowStart + cx]
                    if cell.isBlank {
                        output.append(" ")
                        continue
                    }
                    let code = colorCode(cell.red, cell.green, cell.blue, mode: mode)
                    if code != lastCode {
                        output += code
                        lastCode = code
                    }
                    output.append(cell.character)
                }
                output += "\(escape)0m"
                cursorX = spanEnd + 1
                x = spanEnd + 1
            }

            if prevLastNonBlank > lastNonBlank {
                let clearStart = lastNonBlank + 1
                if cursorX != clearStart {
                    output += "\(escape)\(y + 1);\(clearStart + 1)H\(escape)0m"
                }
                output += "\(escape)K"
            }
        }
        return output
    }
}
