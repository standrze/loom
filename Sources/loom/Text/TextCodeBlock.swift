/// Original code associated with one Markdown block, independent of display wrapping.
public struct TextCodeBlock: Equatable, Sendable {
    /// A source-byte identity that remains stable as text is appended to the Markdown source.
    public let id: Int
    public let language: String?
    /// Code without fences or presentation prefixes, retaining source whitespace.
    public let code: String
    /// Indicates that the layout reserves a compact summary instead of displaying code.
    public let isCompact: Bool

    public init(id: Int, language: String? = nil, code: String, isCompact: Bool = false) {
        self.id = id
        self.language = language
        self.code = code
        self.isCompact = isCompact
    }
}
