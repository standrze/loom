/// A source-text segment with an optional style override.
///
/// A nil style inherits the paragraph's style; a supplied style replaces it.
/// The optional patch then modifies that resolved appearance. Adjacent spans remain one
/// continuous source string for layout, selection, and copying.
public struct TextSpan: Sendable {
    /// One-based Markdown source line for the first character, when supplied.
    ///
    /// Synthetic presentation prefixes have no source location.
    public let sourceLine: Int?
    public let text: String
    public let style: Style?
    /// Changes applied after the span or inherited paragraph style.
    public let patch: StylePatch?
    /// An HTTP(S) destination associated with this visible text.
    public let link: String?
    /// The original code represented by this span's block, when supplied by the renderer.
    public let codeBlock: TextCodeBlock?
    /// Marks a dedicated code-block header row for application-owned controls.
    public let isCodeBlockHeader: Bool
    /// Display-only text remains visible but is omitted from copied selections.
    public let copyable: Bool

    public init(
        _ text: String, style: Style? = nil, link: String? = nil,
        codeBlock: TextCodeBlock? = nil, isCodeBlockHeader: Bool = false, copyable: Bool = true,
        sourceLine: Int? = nil, patch: StylePatch? = nil
    ) {
        self.sourceLine = sourceLine
        self.text = text
        self.style = style
        self.patch = patch
        self.link = link
        self.codeBlock = codeBlock
        self.isCodeBlockHeader = isCodeBlockHeader
        self.copyable = copyable
    }
}
