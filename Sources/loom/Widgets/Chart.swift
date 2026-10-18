import weft

/// How a dataset's points are drawn.
///
/// Non-finite points break line segments.
public enum ChartGraphType: Equatable, Sendable {
    case scatter
    case line
    case bar
    /// Fill between consecutive points and the dataset baseline, then draw the line.
    case filledLine
}

/// One series in chart coordinates; ordering is retained for line segments.
public struct ChartDataset: Sendable {
    public var name: String?
    public var points: [CanvasPoint]
    public var graphType: ChartGraphType
    public var marker: CanvasMarker
    public var style: Style
    /// Horizontal baseline for filled lines; non-finite values suppress the fill.
    public var baseline: Double
    /// Nil uses the dataset style.
    public var fillStyle: Style?

    public init(
        name: String? = nil, points: [CanvasPoint], graphType: ChartGraphType = .line,
        marker: CanvasMarker = .braille, style: Style = Style(),
        baseline: Double = 0, fillStyle: Style? = nil
    ) {
        self.name = name
        self.points = points
        self.graphType = graphType
        self.marker = marker
        self.style = style
        self.baseline = baseline
        self.fillStyle = fillStyle
    }
}

/// A custom tick label at a numeric coordinate.
///
/// Text is clipped as complete terminal glyphs.
public struct ChartAxisLabel: Sendable {
    public var value: Double
    public var spans: [TextSpan]

    public init(value: Double, text: String, style: Style? = nil) {
        self.init(value: value, spans: [TextSpan(text, style: style)])
    }

    public init(value: Double, spans: [TextSpan]) {
        self.value = value
        self.spans = spans
    }
}

/// Axis presentation.
///
/// Nil bounds autoscale finite dataset points; invalid explicit bounds draw no data.
/// Titles are horizontal, with the y title above its axis and the x title below its labels.
public struct ChartAxis: Sendable {
    public var bounds: CanvasBounds?
    public var title: [TextSpan]
    public var labels: [ChartAxisLabel]
    /// Nil inherits the chart appearance; an explicit style replaces it.
    public var style: Style?
    /// Nil inherits the chart appearance; span styles still take precedence.
    public var labelStyle: Style?

    public init(
        bounds: CanvasBounds? = nil, title: [TextSpan] = [], labels: [ChartAxisLabel] = [],
        style: Style? = nil, labelStyle: Style? = nil
    ) {
        self.bounds = bounds
        self.title = title
        self.labels = labels
        self.style = style
        self.labelStyle = labelStyle
    }

    public init(
        bounds: CanvasBounds? = nil, title: String, labels: [ChartAxisLabel] = [],
        style: Style? = nil, labelStyle: Style? = nil
    ) {
        self.init(bounds: bounds, title: [TextSpan(title)], labels: labels, style: style, labelStyle: labelStyle)
    }
}

/// Legend placement inside the plot.
///
/// Legends that do not fit are omitted.
public enum ChartLegendPosition: Equatable, Sendable {
    case topLeft
    case topRight
    case top
    case left
    case right
    case bottomLeft
    case bottomRight
    case bottom
    case hidden
}

/// Maximum legend size on one axis.
///
/// Invalid ratios hide the legend.
public enum ChartLegendLimit: Equatable, Sendable {
    case cells(Int)
    case ratio(Double)
    case unlimited

    func allows(_ size: Int, available: Int) -> Bool {
        switch self {
        case .cells(let maximum): return size <= max(0, maximum)
        case .ratio(let fraction):
            return fraction.isFinite && fraction >= 0 && Double(size) <= Double(available) * fraction
        case .unlimited: return true
        }
    }
}

/// A stateless chart with independently styled datasets, axes, custom ticks, and an optional legend.
///
/// Axes use terminal-cell geometry. Data drawing is clipped to `plotArea(in:)` and the caller's clip.
/// Datasets paint in input order; later datasets replace a shared terminal cell, including its marker dots.
/// Dataset styles compose enabled modifiers and explicit colors over the chart style. Axis and legend
/// styles inherit only when nil; an explicit style replaces the inherited appearance.
/// Custom tick labels retain input order; labels colliding with an earlier label are omitted.
public struct Chart: Widget, Sendable {
    public var datasets: [ChartDataset]
    public var xAxis: ChartAxis
    public var yAxis: ChartAxis
    public var style: Style
    public var legendPosition: ChartLegendPosition = .topRight
    public var legendWidthLimit: ChartLegendLimit = .unlimited
    public var legendHeightLimit: ChartLegendLimit = .unlimited
    /// Nil inherits the chart appearance; an explicit style replaces it.
    public var legendStyle: Style?

    public init(
        datasets: [ChartDataset], xAxis: ChartAxis = ChartAxis(), yAxis: ChartAxis = ChartAxis(),
        style: Style = Style()
    ) {
        self.datasets = datasets
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.style = style
    }

    /// Effective bounds, including constant-range expansion.
    ///
    /// Invalid explicit bounds remain invalid.
    public var resolvedXBounds: CanvasBounds { resolvedBounds(xAxis.bounds, coordinate: { $0.x }) }
    public var resolvedYBounds: CanvasBounds { resolvedBounds(yAxis.bounds, coordinate: { $0.y }) }

    /// The exact data viewport after titles, axes, and custom labels reserve terminal cells.
    ///
    /// Tiny areas clamp reservations to leave zero-sized rather than negative regions.
    public func plotArea(in area: Rect) -> Rect {
        let width = safeLength(area.width, origin: area.x)
        let height = safeLength(area.height, origin: area.y)
        let labelWidth = yAxis.labels.map { textWidth($0.spans) }.max() ?? 0
        let left = min(width, labelWidth + (labelWidth > 0 ? 1 : 0) + 1)
        let top = min(height, yAxis.title.isEmpty ? 0 : 1)
        let labelRows = xAxis.labels.isEmpty ? 0 : 1
        let titleRows = xAxis.title.isEmpty ? 0 : 1
        let bottom = min(height - top, 1 + labelRows + titleRows)
        return Rect(x: area.x + left, y: area.y + top, width: width - left, height: height - top - bottom)
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        let area = Rect(
            x: area.x, y: area.y,
            width: safeLength(area.width, origin: area.x), height: safeLength(area.height, origin: area.y))
        guard area.width > 0, area.height > 0 else { return }
        let plot = plotArea(in: area)
        let boundsX = resolvedXBounds
        let boundsY = resolvedYBounds
        buffer.withClip(area) { target in
            Fill(style: style).render(in: area, buffer: &target)
            drawAxes(in: area, plot: plot, xBounds: boundsX, yBounds: boundsY, buffer: &target)
            guard plot.width > 0, plot.height > 0, valid(boundsX), valid(boundsY) else { return }
            for dataset in datasets {
                let datasetStyle = collectionStyle(style, overlay: dataset.style)
                Canvas(xBounds: boundsX, yBounds: boundsY, marker: dataset.marker, style: datasetStyle) { context in
                    switch dataset.graphType {
                    case .scatter:
                        for point in dataset.points where finite(point) {
                            context.point(at: point, style: datasetStyle)
                        }
                    case .line, .filledLine:
                        if dataset.graphType == .filledLine {
                            var previous: CanvasPoint?
                            for point in dataset.points {
                                guard finite(point) else {
                                    previous = nil
                                    continue
                                }
                                if let previous {
                                    context.filledLine(
                                        from: previous, to: point, baseline: dataset.baseline,
                                        style: collectionStyle(
                                            datasetStyle, overlay: dataset.fillStyle ?? dataset.style))
                                }
                                previous = point
                            }
                            context.newLayer()
                        }
                        var previous: CanvasPoint?
                        for point in dataset.points {
                            guard finite(point) else {
                                previous = nil
                                continue
                            }
                            if let previous { context.line(from: previous, to: point, style: datasetStyle) }
                            context.point(at: point, style: datasetStyle)
                            previous = point
                        }
                    case .bar:
                        let baseline = min(boundsY.max, max(boundsY.min, 0))
                        for point in dataset.points where finite(point) {
                            context.line(
                                from: CanvasPoint(x: point.x, y: baseline), to: point, style: datasetStyle)
                        }
                    }
                }.render(in: plot, buffer: &target)
            }
            drawLegend(in: plot, buffer: &target)
        }
    }

    private func drawAxes(
        in area: Rect, plot: Rect, xBounds: CanvasBounds, yBounds: CanvasBounds, buffer: inout Buffer
    ) {
        let axisX = plot.x - (plot.x > area.x ? 1 : 0)
        let axisY = plot.maxY
        let right = min(buffer.width, plot.maxX)
        let bottom = min(buffer.height, plot.maxY)
        let xStyle = xAxis.style ?? style
        let yStyle = yAxis.style ?? style
        let xLabelStyle = xAxis.labelStyle ?? style
        let yLabelStyle = yAxis.labelStyle ?? style
        if plot.x > area.x {
            for y in max(0, plot.y)..<max(max(0, plot.y), bottom) {
                buffer.put("│", width: 1, at: Point(x: axisX, y: y), style: yStyle)
            }
        }
        if axisY < area.maxY {
            for x in max(0, plot.x)..<max(max(0, plot.x), right) {
                buffer.put("─", width: 1, at: Point(x: x, y: axisY), style: xStyle)
            }
            if plot.x > area.x {
                buffer.put("└", width: 1, at: Point(x: axisX, y: axisY), style: xStyle)
            }
        }
        if !yAxis.title.isEmpty, plot.y > area.y {
            paint(
                yAxis.title, in: Rect(x: area.x, y: area.y, width: max(0, plot.maxX - area.x), height: 1),
                style: yLabelStyle, buffer: &buffer)
        }
        if valid(yBounds), plot.height > 0 {
            var occupiedRows: Set<Int> = []
            for label in yAxis.labels {
                guard let fraction = normalized(label.value, in: yBounds) else { continue }
                let row = plot.y + cellOffset(fraction: 1 - fraction, limit: plot.height - 1)
                let width = min(max(0, axisX - area.x - 1), textWidth(label.spans))
                buffer.put("┤", width: 1, at: Point(x: axisX, y: row), style: yStyle)
                guard width > 0, occupiedRows.insert(row).inserted else { continue }
                paint(
                    label.spans, in: Rect(x: axisX - 1 - width, y: row, width: width, height: 1),
                    style: yLabelStyle, buffer: &buffer)
            }
        }
        if valid(xBounds), plot.width > 0, axisY < area.maxY {
            var occupiedColumns: [Range<Int>] = []
            for label in xAxis.labels {
                guard let fraction = normalized(label.value, in: xBounds) else { continue }
                let offset = cellOffset(fraction: fraction, limit: plot.width - 1)
                let column = plot.x + offset
                buffer.put("┬", width: 1, at: Point(x: column, y: axisY), style: xStyle)
                let width = min(plot.width, textWidth(label.spans))
                let start = plot.x + min(plot.width - width, max(0, offset - width / 2))
                if axisY + 1 < area.maxY, width > 0 {
                    let columns = start..<start + width
                    guard !occupiedColumns.contains(where: { $0.overlaps(columns) }) else { continue }
                    occupiedColumns.append(columns)
                    paint(
                        label.spans, in: Rect(x: start, y: axisY + 1, width: width, height: 1),
                        style: xLabelStyle, buffer: &buffer)
                }
            }
        }
        if !xAxis.title.isEmpty {
            let extraRows = xAxis.labels.isEmpty ? 1 : 2
            let titleRow = axisY.addingReportingOverflow(extraRows)
            if !titleRow.overflow, titleRow.partialValue < area.maxY {
                let row = titleRow.partialValue
                let width = min(plot.width, textWidth(xAxis.title))
                paint(
                    xAxis.title, in: Rect(x: plot.x + (plot.width - width) / 2, y: row, width: width, height: 1),
                    style: xLabelStyle, buffer: &buffer)
            }
        }
    }

    private func drawLegend(in plot: Rect, buffer: inout Buffer) {
        guard legendPosition != .hidden else { return }
        let entries = datasets.compactMap { dataset -> (String, Style)? in
            guard let name = dataset.name, !name.isEmpty else { return nil }
            return (name, collectionStyle(style, overlay: dataset.style))
        }
        guard !entries.isEmpty else { return }
        let width = (entries.map { textWidth([TextSpan($0.0)]) }.max() ?? 0) + 2
        // A legend must leave both uncovered rows and uncovered columns for data.
        guard width < plot.width, entries.count < plot.height else { return }
        guard legendWidthLimit.allows(width, available: plot.width),
            legendHeightLimit.allows(entries.count, available: plot.height)
        else { return }
        let x: Int
        switch legendPosition {
        case .topLeft, .left, .bottomLeft: x = plot.x
        case .top, .bottom: x = plot.x + (plot.width - width) / 2
        default: x = plot.maxX - width
        }
        let y: Int
        switch legendPosition {
        case .topLeft, .top, .topRight: y = plot.y
        case .left, .right: y = plot.y + (plot.height - entries.count) / 2
        default: y = plot.maxY - entries.count
        }
        let legend = Rect(x: x, y: y, width: width, height: entries.count)
        let appearance = legendStyle ?? style
        buffer.withClip(legend) { target in
            Fill(style: appearance).render(in: legend, buffer: &target)
            for (index, entry) in entries.enumerated() {
                target.put("•", width: 1, at: Point(x: x, y: y + index), style: entry.1)
                paint(
                    [TextSpan(entry.0)], in: Rect(x: x + 2, y: y + index, width: width - 2, height: 1),
                    style: appearance, buffer: &target)
            }
        }
    }

    private func resolvedBounds(_ explicit: CanvasBounds?, coordinate: (CanvasPoint) -> Double) -> CanvasBounds {
        if let explicit { return explicit }
        let values = datasets.flatMap(\.points).filter(finite).map(coordinate)
        guard let minimum = values.min(), let maximum = values.max() else { return CanvasBounds(min: 0, max: 1) }
        guard minimum == maximum else { return CanvasBounds(min: minimum, max: maximum) }
        let padding = max(1, abs(minimum) * 0.05)
        let lower = minimum - padding
        let upper = maximum + padding
        if lower.isFinite, upper.isFinite { return CanvasBounds(min: lower, max: upper) }
        return minimum > 0
            ? CanvasBounds(min: minimum - padding, max: minimum)
            : CanvasBounds(min: minimum, max: minimum + padding)
    }

    /// Clamp in floating point before conversion: Double(Int.max) rounds up past Int.max.
    private func cellOffset(fraction: Double, limit: Int) -> Int {
        guard limit > 0, fraction > 0 else { return 0 }
        guard fraction < 1 else { return limit }
        let scaled = (fraction * Double(limit)).rounded()
        if scaled >= Double(limit) { return limit }
        return max(0, Int(scaled))
    }

    private func normalized(_ value: Double, in bounds: CanvasBounds) -> Double? {
        guard value.isFinite, value >= bounds.min, value <= bounds.max, valid(bounds) else { return nil }
        let span = bounds.max - bounds.min
        let fraction =
            span.isFinite
            ? (value - bounds.min) / span
            : (value / 2 - bounds.min / 2) / (bounds.max / 2 - bounds.min / 2)
        guard fraction.isFinite else { return nil }
        return min(1, max(0, fraction))
    }

    private func valid(_ bounds: CanvasBounds) -> Bool {
        bounds.min.isFinite && bounds.max.isFinite && bounds.min < bounds.max
    }

    private func finite(_ point: CanvasPoint) -> Bool { point.x.isFinite && point.y.isFinite }

    private func textWidth(_ spans: [TextSpan]) -> Int {
        TextLayout(spans, width: 1, wrapping: .none).lines.first?.glyphs.last.map { $0.column + $0.width } ?? 0
    }

    private func paint(_ spans: [TextSpan], in area: Rect, style: Style, buffer: inout Buffer) {
        TextLayout(spans, width: max(1, area.width), wrapping: .none).paint(in: area, style: style, buffer: &buffer)
    }

    private func safeLength(_ length: Int, origin: Int) -> Int {
        min(max(0, length), origin > 0 ? Int.max - origin : Int.max)
    }
}
