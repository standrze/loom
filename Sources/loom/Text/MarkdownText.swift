/// Styles used by the focused terminal Markdown renderer.
///
/// Nested markup combines enabled attributes. A terminal-default color inherits
/// its surrounding color so emphasis can retain the body's palette.
public struct MarkdownPalette: Sendable {
    public var body: Style
    public var heading: Style
    public var emphasis: Style
    public var strong: Style
    public var code: Style
    /// Enables full-row code panels and a header anchor when a style is supplied.
    public var codeBlockHeader: Style?
    /// Reserves three blank summary rows per code block when code headers are enabled.
    public var compactCodeBlocks: Bool
    /// Prefix on each fenced-code line when code headers are disabled.
    public var codeBlockPrefix: String
    /// Optional host-owned highlighting for displayed fenced code.
    public var codeHighlighter: (@Sendable (String, String?) -> [TextSpan])?
    public var quote: Style
    public var link: Style

    public init(
        body: Style = Style(), heading: Style = Style(bold: true),
        emphasis: Style = Style(italic: true), strong: Style = Style(bold: true),
        code: Style = Style(), quote: Style = Style(), link: Style = Style(underlined: true),
        codeBlockHeader: Style? = nil, compactCodeBlocks: Bool = false,
        codeBlockPrefix: String = "│ ",
        codeHighlighter: (@Sendable (String, String?) -> [TextSpan])? = nil
    ) {
        self.body = body
        self.heading = heading
        self.emphasis = emphasis
        self.strong = strong
        self.code = code
        self.codeBlockHeader = codeBlockHeader
        self.compactCodeBlocks = compactCodeBlocks
        self.codeBlockPrefix = codeBlockPrefix
        self.codeHighlighter = codeHighlighter
        self.quote = quote
        self.link = link
    }
}

/// Renders the common chat Markdown forms as styled terminal text.
///
/// Swift Markdown owns syntax parsing; loom supplies terminal styles and list,
/// quote, and code prefixes. Only HTTP(S) destinations become terminal links.
/// Unclosed inline markup stays literal, while an open code fence styles the
/// content received so far. Call it again as a response streams.
public enum MarkdownText {
    public static func spans(_ text: String, palette: MarkdownPalette = MarkdownPalette()) -> [TextSpan] {
        MarkdownRenderer(text, palette: palette).spans()
    }
}
