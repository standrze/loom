import weft

/// A chart value with optional styled label, display text and inherited appearance changes.
public struct Bar: Sendable {
    public var value: Double
    public var label: [TextSpan]
    public var textValue: String?
    public var style: StylePatch
    public var labelStyle: StylePatch
    public var valueStyle: StylePatch

    public init(
        _ value: Double, label: String = "", textValue: String? = nil,
        style: StylePatch = StylePatch(), labelStyle: StylePatch = StylePatch(), valueStyle: StylePatch = StylePatch()
    ) {
        self.init(
            value, label: [TextSpan(label)], textValue: textValue,
            style: style, labelStyle: labelStyle, valueStyle: valueStyle)
    }

    public init(
        _ value: Double, label: [TextSpan], textValue: String? = nil,
        style: StylePatch = StylePatch(), labelStyle: StylePatch = StylePatch(), valueStyle: StylePatch = StylePatch()
    ) {
        self.value = value
        self.label = label
        self.textValue = textValue
        self.style = style
        self.labelStyle = labelStyle
        self.valueStyle = valueStyle
    }
}

/// A group of source-ordered bars with an optional one-row label and shared bar appearance.
public struct BarGroup: Sendable {
    public var bars: [Bar]
    public var label: [TextSpan]
    public var style: StylePatch
    public var labelStyle: StylePatch
    public var valueStyle: StylePatch

    public init(
        _ bars: [Bar], label: [TextSpan] = [], style: StylePatch = StylePatch(),
        labelStyle: StylePatch = StylePatch(), valueStyle: StylePatch = StylePatch()
    ) {
        self.bars = bars
        self.label = label
        self.style = style
        self.labelStyle = labelStyle
        self.valueStyle = valueStyle
    }

    public init(
        _ bars: [Bar], label: String, style: StylePatch = StylePatch(),
        labelStyle: StylePatch = StylePatch(), valueStyle: StylePatch = StylePatch()
    ) {
        self.init(bars, label: [TextSpan(label)], style: style, labelStyle: labelStyle, valueStyle: valueStyle)
    }
}

/// Grouped fractional bars in terminal cells, with caller-supplied labels and appearance.
///
/// Vertical bars grow upward and reserve bottom rows for nonempty bar/group labels.
/// Horizontal bars grow rightward, reserve a shared left label gutter, and place group
/// labels above their bars. Values are drawn inside bars at the baseline or left edge.
/// Bar width is columns for vertical charts and rows for horizontal charts; gaps are
/// nonnegative. Labels and values use one unwrapped row and clip at whole graphemes.
/// Empty groups consume no space. Negative and non-finite data render as zero.
public struct BarChart: Widget {
    public var groups: [BarGroup]
    public var direction: Direction = .vertical
    public var barWidth = 1
    public var barGap = 1
    public var groupGap = 2
    public var maximum: Double?
    public var style = Style()
    /// Optional complete replacement styles; nil inherits the chart or resolved bar appearance.
    public var barStyle: Style?
    public var labelStyle: Style?
    public var groupLabelStyle: Style?
    public var valueStyle: Style?
    public var showsValues = true

    public init(groups: [BarGroup], maximum: Double? = nil) {
        self.groups = groups
        self.maximum = maximum
    }

    /// Places ungrouped bars in a single group without a group label.
    public init(bars: [Bar], maximum: Double? = nil) {
        self.init(groups: [BarGroup(bars)], maximum: maximum)
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        let area = plotSafeArea(area)
        guard area.width > 0, area.height > 0, let visible = plotVisibleArea(area, buffer: buffer) else { return }
        let groups = groups.filter { !$0.bars.isEmpty }
        let maximum = plotMaximum(groups.flatMap { $0.bars.map(\.value) }, explicit: maximum)
        buffer.withClip(area) { target in
            target.fill(visible, style: style)
            switch direction {
            case .vertical: renderVertical(groups, maximum: maximum, in: area, visible: visible, buffer: &target)
            case .horizontal: renderHorizontal(groups, maximum: maximum, in: area, visible: visible, buffer: &target)
            }
        }
    }

    private func renderVertical(
        _ groups: [BarGroup], maximum: Double, in area: Rect, visible: Rect, buffer: inout Buffer
    ) {
        let barLabels = groups.contains { $0.bars.contains { plotTextWidth($0.label) > 0 } }
        let groupLabels = groups.contains { plotTextWidth($0.label) > 0 }
        let groupRows = groupLabels ? min(1, area.height) : 0
        let labelRows = barLabels ? min(1, area.height - groupRows) : 0
        let plotHeight = area.height - groupRows - labelRows
        let width = min(area.width, max(1, barWidth))
        var column = 0
        for group in groups {
            guard column < area.width else { break }
            let groupStart = column
            var groupEnd = column
            for (index, bar) in group.bars.enumerated() {
                guard column < area.width else { break }
                let cells = min(width, area.width - column)
                let barArea = Rect(x: area.x + column, y: area.y, width: cells, height: plotHeight)
                paintVerticalBar(bar, group: group, maximum: maximum, in: barArea, visible: visible, buffer: &buffer)
                if labelRows > 0 {
                    paintPlotLabel(
                        bar.label,
                        in: Rect(x: barArea.x, y: area.y + plotHeight, width: cells, height: 1),
                        style: (labelStyle ?? style).applying(group.labelStyle).applying(bar.labelStyle),
                        buffer: &buffer)
                }
                groupEnd = column + cells
                column = advanced(column, by: width, gap: index + 1 < group.bars.count ? barGap : 0, limit: area.width)
            }
            if groupRows > 0 {
                paintPlotLabel(
                    group.label,
                    in: Rect(
                        x: area.x + groupStart, y: area.y + area.height - 1,
                        width: groupEnd - groupStart, height: 1),
                    style: (groupLabelStyle ?? style).applying(group.labelStyle), buffer: &buffer)
            }
            column = advanced(column, by: 0, gap: groupGap, limit: area.width)
        }
    }

    private func paintVerticalBar(
        _ bar: Bar, group: BarGroup, maximum: Double, in area: Rect, visible: Rect, buffer: inout Buffer
    ) {
        guard area.height > 0 else { return }
        let extent = plotExtent(ratio: plotRatio(bar.value, maximum: maximum), cells: area.height)
        let appearance = (barStyle ?? style).applying(group.style).applying(bar.style)
        let left = max(area.x, visible.x)
        let right = min(area.maxX, visible.maxX)
        let top = max(area.y, visible.y)
        let bottom = min(area.maxY, visible.maxY)
        guard left < right, top < bottom else { return }
        let symbols = SparklineSymbols.eighths.glyphs
        for y in top..<bottom {
            let fromBottom = area.height - 1 - (y - area.y)
            let eighths = fromBottom < extent.whole ? 8 : fromBottom == extent.whole ? extent.eighths : 0
            guard eighths > 0 else { continue }
            for x in left..<right {
                buffer.put(symbols[eighths], width: 1, at: Point(x: x, y: y), style: appearance)
            }
        }
        if showsValues, extent.whole > 0 {
            paintPlotLabel(
                [TextSpan(displayValue(bar))],
                in: Rect(x: area.x, y: area.maxY - 1, width: area.width, height: 1),
                style: (valueStyle ?? appearance).applying(group.valueStyle).applying(bar.valueStyle), buffer: &buffer)
        }
    }

    private func renderHorizontal(
        _ groups: [BarGroup], maximum: Double, in area: Rect, visible: Rect, buffer: inout Buffer
    ) {
        let labelWidth = min(area.width, groups.flatMap(\.bars).map { plotTextWidth($0.label) }.max() ?? 0)
        let gutter = min(area.width, labelWidth + (labelWidth > 0 && labelWidth < area.width ? 1 : 0))
        let plotWidth = area.width - gutter
        let thickness = min(area.height, max(1, barWidth))
        var row = 0
        for group in groups {
            guard row < area.height else { break }
            if plotTextWidth(group.label) > 0 {
                paintPlotLabel(
                    group.label, in: Rect(x: area.x, y: area.y + row, width: area.width, height: 1),
                    style: (groupLabelStyle ?? style).applying(group.labelStyle), buffer: &buffer)
                row += 1
            }
            for (index, bar) in group.bars.enumerated() {
                guard row < area.height else { break }
                let rows = min(thickness, area.height - row)
                paintPlotLabel(
                    bar.label,
                    in: Rect(x: area.x, y: area.y + row, width: labelWidth, height: 1),
                    style: (labelStyle ?? style).applying(group.labelStyle).applying(bar.labelStyle), buffer: &buffer)
                let barArea = Rect(x: area.x + gutter, y: area.y + row, width: plotWidth, height: rows)
                paintHorizontalBar(bar, group: group, maximum: maximum, in: barArea, visible: visible, buffer: &buffer)
                row = advanced(row, by: thickness, gap: index + 1 < group.bars.count ? barGap : 0, limit: area.height)
            }
            row = advanced(row, by: 0, gap: groupGap, limit: area.height)
        }
    }

    private func paintHorizontalBar(
        _ bar: Bar, group: BarGroup, maximum: Double, in area: Rect, visible: Rect, buffer: inout Buffer
    ) {
        guard area.width > 0 else { return }
        let extent = plotExtent(ratio: plotRatio(bar.value, maximum: maximum), cells: area.width)
        let appearance = (barStyle ?? style).applying(group.style).applying(bar.style)
        let left = max(area.x, visible.x)
        let right = min(area.maxX, visible.maxX)
        let top = max(area.y, visible.y)
        let bottom = min(area.maxY, visible.maxY)
        guard left < right, top < bottom else { return }
        let symbols = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
        for x in left..<right {
            let local = x - area.x
            let eighths = local < extent.whole ? 8 : local == extent.whole ? extent.eighths : 0
            guard eighths > 0 else { continue }
            for y in top..<bottom {
                buffer.put(symbols[eighths], width: 1, at: Point(x: x, y: y), style: appearance)
            }
        }
        if showsValues, extent.whole > 0 {
            paintPlotLabel(
                [TextSpan(displayValue(bar))],
                in: Rect(x: area.x, y: area.y, width: extent.whole, height: 1),
                style: (valueStyle ?? appearance).applying(group.valueStyle).applying(bar.valueStyle), buffer: &buffer)
        }
    }

    private func displayValue(_ bar: Bar) -> String {
        if let textValue = bar.textValue { return textValue }
        let value = bar.value.isFinite ? max(0, bar.value) : 0
        let text = String(value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    private func advanced(_ offset: Int, by length: Int, gap: Int, limit: Int) -> Int {
        let afterLength = offset + min(max(0, length), limit - offset)
        return afterLength + min(max(0, gap), limit - afterLength)
    }
}
