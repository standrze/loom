import weft

/// A one-column sample.
///
/// Nil and non-finite values are missing; negative values draw as zero.
public struct SparklineBar: Sendable {
    public var value: Double?
    public var patch: StylePatch

    public init(_ value: Double?, patch: StylePatch = StylePatch()) {
        self.value = value
        self.patch = patch
    }
}

/// The screen direction in which successive samples are placed.
public enum SparklineDirection: Equatable, Sendable {
    case leftToRight
    case rightToLeft
}

/// Nine validated single-cell graphemes, indexed from empty through eight eighths.
public struct SparklineSymbols: Sendable {
    public let glyphs: [String]

    /// Rejects wrong counts, wide graphemes and terminal controls.
    public init?(_ glyphs: [String]) {
        guard glyphs.count == 9, glyphs.allSatisfy(Self.isValid) else { return nil }
        self.glyphs = glyphs
    }

    public static let eighths = SparklineSymbols([" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"])!

    static func isValid(_ glyph: String) -> Bool {
        glyph.count == 1 && glyph.first.map { terminalCellWidth($0) == 1 } == true
            && !glyph.unicodeScalars.contains { $0.value < 32 || (0x7f...0x9f).contains($0.value) }
    }
}

/// One terminal column per sample, with multirow eighth-cell precision and optional missing markers.
///
/// Autoscaling considers all finite positive samples, including samples outside the viewport.
/// An explicit nonpositive or non-finite maximum draws no filled cells. Missing markers appear
/// only on the bottom row; invalid missing symbols fall back to a space. Rendering owns no I/O.
public struct Sparkline: Widget {
    public var bars: [SparklineBar]
    public var maximum: Double?
    public var style: Style
    public var direction: SparklineDirection = .leftToRight
    public var symbols: SparklineSymbols = .eighths
    public var missingSymbol = " "
    public var missingStyle = StylePatch()

    public init(_ values: [Double], maximum: Double? = nil, style: Style = Style()) {
        self.init(bars: values.map { SparklineBar($0) }, maximum: maximum, style: style)
    }

    /// Optional samples use a label so `Sparkline([])` remains unambiguous.
    public init(samples: [Double?], maximum: Double? = nil, style: Style = Style()) {
        self.init(bars: samples.map { SparklineBar($0) }, maximum: maximum, style: style)
    }

    public init(bars: [SparklineBar], maximum: Double? = nil, style: Style = Style()) {
        self.bars = bars
        self.maximum = maximum
        self.style = style
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        let area = plotSafeArea(area)
        guard area.width > 0, area.height > 0, let visible = plotVisibleArea(area, buffer: buffer) else { return }
        let maximum = plotMaximum(bars.compactMap(\.value), explicit: maximum)
        let marker = SparklineSymbols.isValid(missingSymbol) ? missingSymbol : " "
        buffer.withClip(area) { target in
            target.fill(visible, style: style)
            for x in visible.x..<visible.maxX {
                let local = x - area.x
                let index = direction == .leftToRight ? local : area.width - 1 - local
                guard bars.indices.contains(index) else { continue }
                let bar = bars[index]
                let appearance = style.applying(bar.patch)
                guard let value = bar.value, value.isFinite else {
                    let bottom = area.y.addingReportingOverflow(area.height - 1)
                    if !bottom.overflow {
                        target.put(
                            marker, width: 1, at: Point(x: x, y: bottom.partialValue),
                            style: appearance.applying(missingStyle))
                    }
                    continue
                }
                let extent = plotExtent(ratio: plotRatio(value, maximum: maximum), cells: area.height)
                for y in visible.y..<visible.maxY {
                    let fromBottom = area.height - 1 - (y - area.y)
                    let eighths = fromBottom < extent.whole ? 8 : fromBottom == extent.whole ? extent.eighths : 0
                    target.put(symbols.glyphs[eighths], width: 1, at: Point(x: x, y: y), style: appearance)
                }
            }
        }
    }
}
