import weft

/// Fills a rectangle with a printable, single-cell grapheme.
///
/// Existing wide glyphs crossing its boundary are preserved in full.
public struct Fill: Widget {
    public var symbol: String
    public var style: Style

    public init(_ symbol: String = " ", style: Style = Style()) {
        self.symbol = symbol
        self.style = style
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        guard symbol.count == 1, let character = symbol.first, terminalCellWidth(character) == 1,
            !symbol.unicodeScalars.contains(where: { $0.value < 32 || (0x7f...0x9f).contains($0.value) })
        else { return }
        let left = max(0, area.x)
        let right = min(buffer.width, area.maxX)
        let top = max(0, area.y)
        let bottom = min(buffer.height, area.maxY)
        guard left < right, top < bottom else { return }
        buffer.withClip(area) { target in
            for y in top..<bottom {
                for x in left..<right {
                    let cell = target[x, y]
                    if cell.width == 0 && x == left { continue }
                    if cell.width == 2 && x + 1 >= right { continue }
                    target.put(symbol, width: 1, at: Point(x: x, y: y), style: style)
                }
            }
        }
    }
}
