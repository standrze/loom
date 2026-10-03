/// Horizontal alignment of text within a list row or table cell.
public enum CellAlignment: Sendable {
    case left
    case center
    case right
}

/// Draws only visible cells even when the logical row extends far outside the buffer.
func fillCollectionArea(_ area: Rect, style: Style, buffer: inout Buffer) {
    let left = max(0, min(buffer.width, area.x))
    let right = max(left, min(buffer.width, area.maxX))
    let top = max(0, min(buffer.height, area.y))
    let bottom = max(top, min(buffer.height, area.maxY))
    for y in top..<bottom {
        for x in left..<right { buffer.put(" ", width: 1, at: Point(x: x, y: y), style: style) }
    }
}

/// Default colors inherit; explicit colors override and enabled attributes combine.
func collectionStyle(_ base: Style, overlay: Style) -> Style {
    Style(
        foreground: overlay.foreground == .terminalDefault ? base.foreground : overlay.foreground,
        background: overlay.background == .terminalDefault ? base.background : overlay.background,
        bold: base.bold || overlay.bold, italic: base.italic || overlay.italic,
        underlined: base.underlined || overlay.underlined, reversed: base.reversed || overlay.reversed)
}

func paintCollectionText(
    _ spans: [TextSpan], in area: Rect, alignment: CellAlignment = .left,
    style: Style, overlay: Style = Style(), buffer: inout Buffer
) {
    guard area.width > 0, area.height > 0 else { return }
    let layout = TextLayout(spans, width: area.width)
    buffer.withClip(area) { buffer in
        for (row, line) in layout.lines.prefix(area.height).enumerated() {
            let width = line.glyphs.last.map { $0.column + $0.width } ?? 0
            let padding: Int
            switch alignment {
            case .left: padding = 0
            case .center: padding = (area.width - width) / 2
            case .right: padding = area.width - width
            }
            for glyph in line.glyphs {
                let tokenStyle = collectionStyle(style, overlay: glyph.style ?? Style())
                buffer.put(
                    glyph.text, width: glyph.width,
                    at: Point(x: area.x + padding + glyph.column, y: area.y + row),
                    style: collectionStyle(tokenStyle, overlay: overlay), link: glyph.link)
            }
        }
    }
}
