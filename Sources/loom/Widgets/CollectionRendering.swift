import weft

/// Horizontal alignment of text within a list row or table cell.
public enum CellAlignment: Equatable, Sendable {
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
        underlined: base.underlined || overlay.underlined, reversed: base.reversed || overlay.reversed,
        dim: base.dim || overlay.dim, strikethrough: base.strikethrough || overlay.strikethrough,
        underlineColor: overlay.underlineColor == .terminalDefault ? base.underlineColor : overlay.underlineColor,
        hidden: base.hidden || overlay.hidden, blink: overlay.blink == .none ? base.blink : overlay.blink)
}

func paintCollectionText(
    _ spans: [TextSpan], in area: Rect, alignment: CellAlignment = .left,
    style: Style, overlay: Style = Style(), patch: StylePatch? = nil, patches: [StylePatch] = [],
    presentation: [(Style, StylePatch?)] = [], wrapping: TextWrapping = .grapheme,
    wrapOptions: TextWrapOptions = TextWrapOptions(), buffer: inout Buffer
) {
    guard area.width > 0, area.height > 0 else { return }
    let layout = TextLayout(spans, width: area.width, wrapping: wrapping, options: wrapOptions)
    buffer.withClip(area) { buffer in
        for (row, line) in layout.lines.prefix(area.height).enumerated() {
            let width = line.glyphs.last.map { $0.column + $0.width } ?? 0
            let padding: Int
            switch alignment {
            case .left: padding = 0
            case .center: padding = max(0, area.width - width) / 2
            case .right: padding = max(0, area.width - width)
            }
            for glyph in line.glyphs {
                let tokenStyle = collectionStyle(style, overlay: glyph.style ?? Style()).applying(
                    glyph.patch ?? StylePatch())
                buffer.put(
                    glyph.text, width: glyph.width,
                    at: Point(x: area.x + padding + glyph.column, y: area.y + row),
                    style: collectionPresentation(
                        patches.reduce(collectionStyle(tokenStyle, overlay: overlay).applying(patch ?? StylePatch())) {
                            $0.applying($1)
                        }, stages: presentation), link: glyph.link)
            }
        }
    }
}

/// Whether a selection prefix consumes cells in the collection's content area.
public enum SelectionPrefixReservation: Sendable {
    case never
    case whenSelected
    case always
}

func collectionPrefixWidth(_ symbol: String, reservation: SelectionPrefixReservation, hasSelection: Bool) -> Int {
    switch reservation {
    case .never: return 0
    case .whenSelected where !hasSelection: return 0
    default:
        return TextLayout(symbol, width: 1, wrapping: .none).lines.first?.glyphs.last.map { $0.column + $0.width } ?? 0
    }
}

func collectionPresentation(_ base: Style, stages: [(Style, StylePatch?)]) -> Style {
    stages.reduce(base) { collectionStyle($0, overlay: $1.0).applying($1.1 ?? StylePatch()) }
}
