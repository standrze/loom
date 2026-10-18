import weft

/// Controls whether a glyph participates in terminal presentation.
public enum CellDiffPolicy: Equatable, Sendable {
    /// Repaint when the cell changes.
    case automatic
    /// Preserve the existing terminal contents, for example beneath an external image.
    case skip
    /// Repaint every frame, including when the cell is unchanged.
    case alwaysUpdate
    /// Explicit terminal span for a safe symbol payload containing one or more graphemes.
    /// Use `Buffer.put` with the same positive width. This never permits terminal controls.
    case forcedWidth(Int)
}

/// One terminal cell, including continuation cells for wide graphemes.
public struct Cell: Equatable, Sendable {
    public var symbol: String

    /// 0 marks a continuation cell; positive widths mark leading cells.
    public var width: Int
    public var style: Style
    public var link: String?
    public var diffPolicy: CellDiffPolicy

    public init(
        symbol: String = " ", width: Int = 1, style: Style = Style(), link: String? = nil,
        diffPolicy: CellDiffPolicy = .automatic
    ) {
        self.symbol = symbol
        self.width = width
        self.style = style
        self.link = link
        self.diffPolicy = diffPolicy
    }
}
