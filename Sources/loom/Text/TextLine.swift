/// Styled source text with an optional alignment overriding its paragraph.
///
/// Soft-wrapped rows and explicit newlines within this line inherit its alignment.
/// Nil keeps the paragraph's alignment. Alignment never changes copied source text.
public struct TextLine: Sendable {
    public var spans: [TextSpan]
    public var alignment: CellAlignment?

    public init(_ text: String, style: Style? = nil, alignment: CellAlignment? = nil) {
        self.init([TextSpan(text, style: style)], alignment: alignment)
    }

    public init(_ spans: [TextSpan], alignment: CellAlignment? = nil) {
        self.spans = spans
        self.alignment = alignment
    }
}
