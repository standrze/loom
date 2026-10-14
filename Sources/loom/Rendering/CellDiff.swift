import Foundation
import weft

/// Stateful output encoder.
///
/// Unchanged frames (including cursor state) emit no bytes.
public struct CellDiff {
    public var synchronizedOutput: Bool
    public var colorDepth: TerminalColorDepth
    public var hyperlinks: Bool
    private var lastCursor: Point?

    public init(
        synchronizedOutput: Bool = true, colorDepth: TerminalColorDepth = .trueColor,
        hyperlinks: Bool = false
    ) {
        self.synchronizedOutput = synchronizedOutput
        self.colorDepth = colorDepth
        self.hyperlinks = hyperlinks
    }

    public mutating func reset() {
        lastCursor = nil
    }

    /// Encodes local cells at a physical origin.
    ///
    /// Disable `clearScreen` for bounded regions.
    ///
    /// A bounded full repaint writes default blanks explicitly and never emits ED 2.
    public mutating func encode(
        _ next: Buffer, previous: Buffer?, cursor: Point?,
        origin: Point = Point(x: 0, y: 0), clearScreen: Bool = true
    ) -> (Data, RenderStats) {
        let sameSize = previous?.width == next.width && previous?.height == next.height
        var output = sameSize || !clearScreen ? "" : "\u{1b}[2J"
        var position: Point?
        var style: Style?
        var activeLink: String?
        var changed = 0
        for y in 0..<next.height {
            for x in 0..<next.width {
                let cell = next[x, y]
                guard !sameSize || cell != previous![x, y] else {
                    continue
                }
                // A full repaint starts with ED 2, so default blank cells are
                // already correct. Writing them all makes startup and resize
                // visibly slow in terminals that ignore synchronized output.
                if !sameSize && clearScreen && cell == Cell() {
                    continue
                }
                changed += 1
                guard cell.width > 0 else {
                    continue
                }
                let target = Point(x: x, y: y)
                if position != target {
                    output += move(Point(x: origin.x + target.x, y: origin.y + target.y))
                }
                if style != cell.style {
                    output += styleSequence(cell.style, previous: style)
                    style = cell.style
                }
                let nextLink = hyperlinks ? safeLink(cell.link) : nil
                if activeLink != nextLink {
                    if activeLink != nil { output += "\u{1b}]8;;\u{1b}\\" }
                    if let nextLink { output += "\u{1b}]8;;\(nextLink)\u{1b}\\" }
                    activeLink = nextLink
                }
                output += cell.symbol
                position = Point(x: x + cell.width, y: y)
            }
        }
        let validCursor = cursor.flatMap {
            next.area.contains($0) ? $0 : nil
        }
        let repainted = !sameSize || changed > 0
        if repainted && lastCursor != nil {
            // Keep the visible cursor away from the cells being repainted.
            // Move it back before showing it when the frame is complete.
            output = "\u{1b}[?25l" + output
        }
        if activeLink != nil { output += "\u{1b}]8;;\u{1b}\\" }
        if !output.isEmpty {
            if let style, style.underlineColor != .terminalDefault {
                output += "\u{1b}[0;59m"
            } else {
                output += "\u{1b}[0m"
            }
        }
        if let validCursor {
            if repainted || lastCursor != validCursor {
                output += move(Point(x: origin.x + validCursor.x, y: origin.y + validCursor.y))
            }
            if repainted || lastCursor == nil {
                output += "\u{1b}[?25h"
            }
        } else if lastCursor != nil || !sameSize {
            if !repainted || lastCursor == nil {
                output += "\u{1b}[?25l"
            }
        }
        lastCursor = validCursor
        if !output.isEmpty && synchronizedOutput {
            output = "\u{1b}[?2026h" + output + "\u{1b}[?2026l"
        }
        let data = Data(output.utf8)
        return (data, RenderStats(changedCells: changed, bytes: data.count))
    }

    private func move(_ point: Point) -> String {
        "\u{1b}[\(point.y+1);\(point.x+1)H"
    }

    private func styleSequence(_ style: Style, previous: Style?) -> String {
        var codes = ["0"]
        if style.underlineColor == .terminalDefault,
            let previous, previous.underlineColor != .terminalDefault
        {
            codes.append("59")
        }
        if style.bold {
            codes.append("1")
        }
        if style.dim {
            codes.append("2")
        }
        if style.italic {
            codes.append("3")
        }
        if style.underlined {
            codes.append("4")
        }
        if style.hidden { codes.append("8") }
        switch style.blink {
        case .none: break
        case .slow: codes.append("5")
        case .rapid: codes.append("6")
        }
        if let underline = underlineCode(style.underlineColor) { codes.append(underline) }
        if style.reversed {
            codes.append("7")
        }
        if style.strikethrough {
            codes.append("9")
        }
        if let foreground = colorCode(style.foreground, foreground: true) { codes.append(foreground) }
        if let background = colorCode(style.background, foreground: false) { codes.append(background) }
        return "\u{1b}[" + codes.joined(separator: ";") + "m"
    }

    private func underlineCode(_ color: Color) -> String? {
        guard colorDepth != .monochrome else { return nil }
        switch color {
        case .terminalDefault: return nil  // SGR 0 restores the default underline color.
        case let .indexed(index):
            return "58;5;\(nearestIndex(index, limit: colorDepth == .ansi16 ? 16 : 256))"
        case let .rgb(red, green, blue):
            if colorDepth == .trueColor { return "58;2;\(red);\(green);\(blue)" }
            let index = nearestPaletteIndex((Int(red), Int(green), Int(blue)), limit: colorDepth == .ansi16 ? 16 : 256)
            return "58;5;\(index)"
        }
    }

    private func colorCode(_ color: Color, foreground: Bool) -> String? {
        guard colorDepth != .monochrome else { return nil }
        let prefix = foreground ? 38 : 48
        switch color {
        case .terminalDefault:
            return nil
        case let .indexed(index):
            if colorDepth == .ansi16 {
                return ansi16Code(nearestIndex(index, limit: 16), foreground: foreground)
            }
            return "\(prefix);5;\(index)"
        case let .rgb(red, green, blue):
            if colorDepth == .trueColor { return "\(prefix);2;\(red);\(green);\(blue)" }
            let target = (Int(red), Int(green), Int(blue))
            let index = nearestPaletteIndex(target, limit: colorDepth == .ansi16 ? 16 : 256)
            if colorDepth == .ansi16 { return ansi16Code(index, foreground: foreground) }
            return "\(prefix);5;\(index)"
        }
    }

    private func ansi16Code(_ index: Int, foreground: Bool) -> String {
        let base = foreground ? 30 : 40
        return String(base + index % 8 + (index >= 8 ? 60 : 0))
    }

    private func nearestIndex(_ index: UInt8, limit: Int) -> Int {
        if Int(index) < limit { return Int(index) }
        return nearestPaletteIndex(paletteRGB(Int(index)), limit: limit)
    }

    private func nearestPaletteIndex(_ target: (Int, Int, Int), limit: Int) -> Int {
        var best = 0
        var distance = Int.max
        for index in 0..<limit {
            let candidate = paletteRGB(index)
            let delta =
                (target.0 - candidate.0) * (target.0 - candidate.0)
                + (target.1 - candidate.1) * (target.1 - candidate.1)
                + (target.2 - candidate.2) * (target.2 - candidate.2)
            if delta < distance {
                distance = delta
                best = index
            }
        }
        return best
    }

    private func paletteRGB(_ index: Int) -> (Int, Int, Int) {
        let basic: [(Int, Int, Int)] = [
            (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
            (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
            (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
            (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
        ]
        if index < 16 { return basic[index] }
        if index < 232 {
            let cube = index - 16
            func level(_ value: Int) -> Int { value == 0 ? 0 : 55 + value * 40 }
            return (level(cube / 36), level((cube / 6) % 6), level(cube % 6))
        }
        let gray = 8 + (index - 232) * 10
        return (gray, gray, gray)
    }

    private func safeLink(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 2048,
            !value.unicodeScalars.contains(where: { $0.value < 32 || (0x7f...0x9f).contains($0.value) }),
            let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            (scheme == "https" || scheme == "http"), url.host != nil
        else { return nil }
        return url.absoluteString
    }
}
