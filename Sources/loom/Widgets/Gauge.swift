/// A horizontal progress bar with eighth-cell precision and a centered optional label.
public struct Gauge: Widget {
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
        let progress = (ratio.isFinite ? min(1, max(0, ratio)) : 0) * Double(area.width)
        let whole = progress >= Double(area.width) ? area.width : Int(min(Double(area.width - 1), progress))
        let fraction = min(7, Int((progress - Double(whole)) * 8))
        let partial = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
        buffer.withClip(area) { target in
            Fill(style: style).render(in: area, buffer: &target)
            for y in area.y..<area.maxY {
                for column in 0..<area.width {
                    if column < whole {
                        target.put("█", width: 1, at: Point(x: area.x + column, y: y), style: filledStyle)
                    } else if column == whole && fraction > 0 {
                        target.put(partial[fraction], width: 1, at: Point(x: area.x + column, y: y), style: filledStyle)
                    }
                }
            }
            if let label {
                let layout = TextLayout(label, width: area.width)
                let width = layout.lines.first?.glyphs.last.map { $0.column + $0.width } ?? 0
                layout.paint(
                    in: Rect(
                        x: area.x + (area.width - width) / 2, y: area.y + area.height / 2,
                        width: width, height: 1), style: labelStyle, buffer: &target)
            }
        }
    }
}
