import weft

/// A view of cached text layout, with optional scrolling and selection.
public struct Paragraph: Widget {
    public let layout: TextLayout
    public var scroll: Int
    public var selection: TextSelection?
    public var style: Style
    public var horizontalScroll: Int
    public var alignment: CellAlignment

    public init(
        _ layout: TextLayout, scroll: Int = 0, selection: TextSelection? = nil, style: Style = Style(),
        horizontalScroll: Int = 0, alignment: CellAlignment = .left
    ) {
        self.layout = layout
        self.scroll = scroll
        self.selection = selection
        self.style = style
        self.horizontalScroll = horizontalScroll
        self.alignment = alignment
    }

    /// Maps terminal cells to the content coordinates accepted by TextSelection.
    public func contentPoint(at point: Point, in area: Rect) -> Point? {
        layout.contentPoint(
            at: point, in: area, rowOffset: scroll, columnOffset: horizontalScroll, alignment: alignment)
    }

    public func viewportPoint(for point: Point, in area: Rect) -> Point? {
        layout.viewportPoint(
            for: point, in: area, rowOffset: scroll, columnOffset: horizontalScroll, alignment: alignment)
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        layout.paint(
            in: area, rowOffset: scroll, selection: selection, style: style,
            columnOffset: horizontalScroll, alignment: alignment, buffer: &buffer)
    }
}
