/// Optional appearance changes composed over a resolved `Style`.
///
/// Nil inherits the existing attribute. A false modifier explicitly disables it;
/// `.terminalDefault` explicitly resets a color. Use `Blink.none` to disable blinking
/// (`nil` or optional `.none` inherits it). For example,
/// `Style(foreground: .indexed(4)).applying(StylePatch(bold: true))` retains blue.
public struct StylePatch: Equatable, Sendable {
    public var foreground: Color?
    public var background: Color?
    public var bold: Bool?
    public var italic: Bool?
    public var underlined: Bool?
    public var reversed: Bool?
    public var dim: Bool?
    public var strikethrough: Bool?
    public var underlineColor: Color?
    public var hidden: Bool?
    public var blink: Blink?

    public init(
        foreground: Color? = nil, background: Color? = nil,
        bold: Bool? = nil, italic: Bool? = nil, underlined: Bool? = nil, reversed: Bool? = nil,
        dim: Bool? = nil, strikethrough: Bool? = nil,
        underlineColor: Color? = nil, hidden: Bool? = nil, blink: Blink? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underlined = underlined
        self.reversed = reversed
        self.dim = dim
        self.strikethrough = strikethrough
        self.underlineColor = underlineColor
        self.hidden = hidden
        self.blink = blink
    }

    /// Composes another patch after this one.
    ///
    /// Its specified attributes take precedence.
    ///
    /// Applying the result to a style is equivalent to applying the two patches in order.
    public func applying(_ patch: StylePatch) -> StylePatch {
        StylePatch(
            foreground: patch.foreground ?? foreground, background: patch.background ?? background,
            bold: patch.bold ?? bold, italic: patch.italic ?? italic,
            underlined: patch.underlined ?? underlined, reversed: patch.reversed ?? reversed,
            dim: patch.dim ?? dim, strikethrough: patch.strikethrough ?? strikethrough,
            underlineColor: patch.underlineColor ?? underlineColor, hidden: patch.hidden ?? hidden,
            blink: patch.blink ?? blink)
    }
}
