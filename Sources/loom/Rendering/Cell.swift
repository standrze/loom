import weft

/// One terminal cell, including continuation cells for wide graphemes.
public struct Cell: Equatable, Sendable {
    public var symbol: String

    /// 0 marks the trailing cell of a two-column grapheme.
    public var width: Int
    public var style: Style
    public var link: String?

    public init(symbol: String = " ", width: Int = 1, style: Style = Style(), link: String? = nil) {
        self.symbol = symbol
        self.width = width
        self.style = style
        self.link = link
    }
}
