/// A source-text segment with an optional style override.
///
/// A nil style inherits the paragraph's style. Adjacent spans remain one
/// continuous source string for layout, selection, and copying.
public struct TextSpan: Sendable {
    public let text: String
    public let style: Style?
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
        codeBlock: TextCodeBlock? = nil, isCodeBlockHeader: Bool = false, copyable: Bool = true
    ) {
        self.text = text
        self.style = style
        self.link = link
        self.codeBlock = codeBlock
        self.isCodeBlockHeader = isCodeBlockHeader
        self.copyable = copyable
    }
}
