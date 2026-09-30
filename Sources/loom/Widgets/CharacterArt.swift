import weft

/// Draws character artwork at its original spacing without wrapping.
///
/// Width and height are measured in terminal cells. Tabs advance to four-column
/// stops, and terminal controls are removed using the same rules as TextLayout.
/// Every newline starts a row, including a trailing newline; an empty source has
/// width zero and height one. Blank cells inside the artwork's natural rectangle
/// are painted with its style. Extra space in the assigned area remains untouched.
public struct CharacterArt: Widget, Sendable {
    public let width: Int
    public let height: Int
    public var style: Style

    private let layout: TextLayout

    /// Measures and caches artwork once, preserving explicit line breaks.
    public init(_ source: String, style: Style = Style()) {
        let layout = TextLayout(source, width: Int.max)
        self.layout = layout
        width = layout.lines.map { $0.glyphs.last.map { $0.column + $0.width } ?? 0 }.max() ?? 0
        height = layout.lines.count
        self.style = style
    }

    /// Clips to the assigned area and buffer without drawing partial wide graphemes.
    public func render(in area: Rect, buffer: inout Buffer) {
        let columns = visibleRange(origin: area.x, length: min(width, area.width), limit: buffer.width)
        let rows = visibleRange(origin: area.y, length: min(height, area.height), limit: buffer.height)
        guard !columns.isEmpty, !rows.isEmpty else { return }

        for row in rows {
            let y = area.y + row
            for column in columns {
                buffer.put(" ", width: 1, at: Point(x: area.x + column, y: y), style: style)
            }
            for glyph in layout.lines[row].glyphs {
                guard columns.contains(glyph.column), glyph.column + glyph.width <= columns.upperBound else {
                    continue
                }
                buffer.put(
                    glyph.text, width: glyph.width, at: Point(x: area.x + glyph.column, y: y), style: style)
            }
        }
    }

    private func visibleRange(origin: Int, length: Int, limit: Int) -> Range<Int> {
        guard length > 0, limit > 0, origin < limit else { return 0..<0 }
        if origin >= 0 { return 0..<min(length, limit - origin) }
        // magnitude remains representable when an offscreen origin is Int.min.
        let offset = origin.magnitude
        guard offset < UInt(length) else { return 0..<0 }
        let start = Int(offset)
        return start..<(start + min(length - start, limit))
    }
}
