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

/// The visual attributes applied to a terminal cell.
public struct Style: Equatable, Sendable {
    public var foreground: Color
    public var background: Color
    public var bold: Bool
    public var italic: Bool
    public var underlined: Bool
    public var reversed: Bool

    public init(
        foreground: Color = .terminalDefault, background: Color = .terminalDefault,
        bold: Bool = false, italic: Bool = false, underlined: Bool = false, reversed: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underlined = underlined
        self.reversed = reversed
    }
}
