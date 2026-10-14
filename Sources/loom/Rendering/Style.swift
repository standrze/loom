import weft

/// A terminal-native color or an indexed palette entry.
public enum Color: Equatable, Sendable {
    case terminalDefault
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)

    /// Linear blend from this RGB color toward `other`.
    ///
    /// Amounts outside 0...1 are clamped. Non-finite amounts stay on this color.
    /// Returns nil when either color is not an explicit RGB triple, because indexed
    /// and default colors depend on the terminal.
    public func blended(toward other: Color, amount: Double) -> Color? {
        guard case let .rgb(baseRed, baseGreen, baseBlue) = self,
            case let .rgb(targetRed, targetGreen, targetBlue) = other
        else { return nil }
        let amount = amount.isFinite ? min(1, max(0, amount)) : 0

        func channel(_ base: UInt8, _ target: UInt8) -> UInt8 {
            let value = Double(base) * (1 - amount) + Double(target) * amount
            return UInt8(clamping: Int(value.rounded()))
        }
        return .rgb(
            channel(baseRed, targetRed), channel(baseGreen, targetGreen), channel(baseBlue, targetBlue))
    }
}

/// Terminal-managed blinking; emulator support varies.
public enum Blink: Equatable, Sendable {
    case none
    case slow
    case rapid
}

/// The visual attributes applied to a terminal cell.
public struct Style: Equatable, Sendable {
    public var foreground: Color
    public var background: Color
    public var bold: Bool
    public var italic: Bool
    public var underlined: Bool
    public var reversed: Bool
    public var dim: Bool
    public var strikethrough: Bool
    public var underlineColor: Color
    public var hidden: Bool
    public var blink: Blink

    public init(
        foreground: Color = .terminalDefault, background: Color = .terminalDefault,
        bold: Bool = false, italic: Bool = false, underlined: Bool = false, reversed: Bool = false,
        dim: Bool = false, strikethrough: Bool = false,
        underlineColor: Color = .terminalDefault, hidden: Bool = false, blink: Blink = .none
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

    /// Resolves a patch over this appearance.
    ///
    /// Unspecified attributes retain their current values.
    public func applying(_ patch: StylePatch) -> Style {
        Style(
            foreground: patch.foreground ?? foreground, background: patch.background ?? background,
            bold: patch.bold ?? bold, italic: patch.italic ?? italic,
            underlined: patch.underlined ?? underlined, reversed: patch.reversed ?? reversed,
            dim: patch.dim ?? dim, strikethrough: patch.strikethrough ?? strikethrough,
            underlineColor: patch.underlineColor ?? underlineColor, hidden: patch.hidden ?? hidden,
            blink: patch.blink ?? blink)
    }
}
