/// A single menu row with a label and an optional right-aligned hint.
public struct MenuItem: Sendable {
    public var label: String
    public var hint: String

    public init(_ label: String, hint: String = "") {
        self.label = label
        self.hint = hint
    }
}

/// A clipped menu with shared rendering and hit-test geometry.
///
/// The application owns selection, keyboard handling, and action dispatch.
public struct Menu: Widget {
    public var items: [MenuItem]
    public var selectedIndex: Int?

    public init(_ items: [MenuItem], selectedIndex: Int? = nil) {
        self.items = items
        self.selectedIndex = selectedIndex
    }

    public func item(at point: Point, in area: Rect) -> Int? {
        guard area.contains(point), point.y - area.y < items.count else { return nil }
        return point.y - area.y
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        guard area.width > 0, area.height > 0 else { return }
        for (index, item) in items.prefix(area.height).enumerated() {
            let selected = selectedIndex == index
            let style = Style(bold: true, reversed: selected)
            let hintStyle = Style(foreground: selected ? .terminalDefault : .indexed(8), reversed: selected)
            let y = area.y + index
            for x in area.x..<(area.x + area.width) {
                buffer.put(" ", width: 1, at: Point(x: x, y: y), style: style)
            }
            let hint = TextLayout(item.hint, width: area.width)
            let hintWidth = hint.lines[0].glyphs.last.map { $0.column + $0.width } ?? 0
            // Hide hints in narrow areas so the action label remains useful.
            let showHint = hintWidth > 0 && area.width >= hintWidth + 12
            let labelWidth = showHint ? area.width - hintWidth - 4 : area.width
            Paragraph(TextLayout(item.label, width: max(1, labelWidth)), style: style)
                .render(in: Rect(x: area.x, y: y, width: labelWidth, height: 1), buffer: &buffer)
            if showHint {
                Paragraph(hint, style: hintStyle)
                    .render(
                        in: Rect(x: area.x + area.width - hintWidth, y: y, width: hintWidth, height: 1), buffer: &buffer
                    )
            }
        }
    }
}
