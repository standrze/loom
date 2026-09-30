import weft

/// A view of cached text layout, with optional scrolling and selection.
public struct Paragraph: Widget {
    public let layout: TextLayout
    public var scroll: Int
    public var selection: TextSelection?
    public var style: Style

    public init(_ layout: TextLayout, scroll: Int = 0, selection: TextSelection? = nil, style: Style = Style()) {
        self.layout = layout
        self.scroll = scroll
        self.selection = selection
        self.style = style
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        layout.paint(in: area, rowOffset: scroll, selection: selection, style: style, buffer: &buffer)
    }
}
