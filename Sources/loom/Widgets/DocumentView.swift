import weft

/// A visible region of a document that reuses its cached entry layouts.
public struct DocumentView: Widget {
    public let document: TextDocument
    public let scroll: Int
    public let selection: TextSelection?

    public init(_ document: TextDocument, scroll: Int = 0, selection: TextSelection? = nil) {
        self.document = document
        self.scroll = scroll
        self.selection = selection
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        document.paint(in: area, scroll: scroll, selection: selection, buffer: &buffer)
    }
}
