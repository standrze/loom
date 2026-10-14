/// Validated single-cell border glyphs, including junctions for explicit border layers.
public struct BorderSymbols: Sendable {
    public let horizontal: String
    public let vertical: String
    public let topLeft: String
    public let topRight: String
    public let bottomLeft: String
    public let bottomRight: String
    public let topJunction: String
    public let bottomJunction: String
    public let leftJunction: String
    public let rightJunction: String
    public let cross: String

    public enum ValidationError: Error { case invalidSymbol(String) }

    public init(
        horizontal: String, vertical: String, topLeft: String, topRight: String,
        bottomLeft: String, bottomRight: String, topJunction: String = "+",
        bottomJunction: String = "+", leftJunction: String = "+",
        rightJunction: String = "+", cross: String = "+"
    ) throws {
        for symbol in [
            horizontal, vertical, topLeft, topRight, bottomLeft, bottomRight,
            topJunction, bottomJunction, leftJunction, rightJunction, cross,
        ] {
            guard Self.isValid(symbol) else { throw ValidationError.invalidSymbol(symbol) }
        }
        self.horizontal = horizontal
        self.vertical = vertical
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.topJunction = topJunction
        self.bottomJunction = bottomJunction
        self.leftJunction = leftJunction
        self.rightJunction = rightJunction
        self.cross = cross
    }

    static func isValid(_ symbol: String) -> Bool {
        guard symbol.count == 1,
            !symbol.unicodeScalars.contains(where: { $0.value < 32 || (0x7f...0x9f).contains($0.value) })
        else { return false }
        let glyphs = TextLayout(symbol, width: 2).lines.flatMap(\.glyphs)
        return glyphs.count == 1 && glyphs[0].width == 1 && glyphs[0].text == symbol
    }
}

/// A translated rectangular shadow drawn before the panel and clipped by its enclosing buffer clip.
public struct PanelShadow: Sendable {
    public var offsetX: Int
    public var offsetY: Int
    public var style: Style
    public let glyph: String

    public init(offsetX: Int = 1, offsetY: Int = 1, style: Style = Style(), glyph: String = "░") throws {
        guard BorderSymbols.isValid(glyph) else { throw BorderSymbols.ValidationError.invalidSymbol(glyph) }
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.style = style
        self.glyph = glyph
    }
}
