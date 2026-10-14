/// A single-row fractional progress bar with an optional label before the bar.
public struct LineGauge: Widget {
    public var ratio: Double
    public var label: String?
    public var style: Style
    public var filledStyle: Style
    public var labelStyle: Style

    public init(
        ratio: Double, label: String? = nil, style: Style = Style(),
        filledStyle: Style = Style(), labelStyle: Style = Style()
    ) {
        self.ratio = ratio
        self.label = label
        self.style = style
        self.filledStyle = filledStyle
        self.labelStyle = labelStyle
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        guard area.width > 0, area.height > 0 else { return }
        buffer.withClip(area) { target in
            var offset = 0
            if let label, !label.isEmpty {
                let layout = TextLayout(label, width: area.width)
                offset = layout.lines.first?.glyphs.last.map { $0.column + $0.width } ?? 0
                layout.paint(
                    in: Rect(x: area.x, y: area.y, width: offset, height: 1),
                    style: labelStyle, buffer: &target)
                if offset < area.width {
                    target.put(" ", width: 1, at: Point(x: area.x + offset, y: area.y), style: style)
                    offset += 1
                }
            }
            Gauge(ratio: ratio, style: style, filledStyle: filledStyle).render(
                in: Rect(x: area.x + offset, y: area.y, width: area.width - offset, height: 1), buffer: &target)
        }
    }
}
