import weft

func plotSafeArea(_ area: Rect) -> Rect {
    Rect(
        x: area.x, y: area.y,
        width: min(max(0, area.width), area.x > 0 ? Int.max - area.x : Int.max),
        height: min(max(0, area.height), area.y > 0 ? Int.max - area.y : Int.max))
}

/// Visible intersection without overflowing coordinate arithmetic on mutable Rect values.
func plotVisibleArea(_ area: Rect, buffer: Buffer) -> Rect? {
    let right = area.x.addingReportingOverflow(max(0, area.width))
    let bottom = area.y.addingReportingOverflow(max(0, area.height))
    let left = max(0, area.x)
    let top = max(0, area.y)
    let endX = min(buffer.width, right.overflow ? Int.max : right.partialValue)
    let endY = min(buffer.height, bottom.overflow ? Int.max : bottom.partialValue)
    guard left < endX, top < endY else { return nil }
    return Rect(x: left, y: top, width: endX - left, height: endY - top)
}

func plotMaximum(_ values: [Double], explicit: Double?) -> Double {
    if let explicit { return explicit.isFinite && explicit > 0 ? explicit : 0 }
    return values.filter { $0.isFinite && $0 > 0 }.max() ?? 0
}

func plotRatio(_ value: Double, maximum: Double) -> Double {
    guard maximum.isFinite, maximum > 0, value.isFinite, value > 0 else { return 0 }
    return min(1, value / maximum)
}

/// Returns whole cells and a remainder in eighths without multiplying an Int by eight.
func plotExtent(ratio: Double, cells: Int) -> (whole: Int, eighths: Int) {
    guard cells > 0, ratio > 0 else { return (0, 0) }
    if ratio >= 1 { return (cells, 0) }
    let scaled = ratio * Double(cells)
    if scaled >= Double(cells) || scaled >= Double(Int.max) { return (cells, 0) }
    let whole = Int(min(Double(cells - 1), scaled))
    return (whole, min(7, max(0, Int((scaled - Double(whole)) * 8))))
}

func plotTextWidth(_ spans: [TextSpan]) -> Int {
    TextLayout(spans, width: 1, wrapping: .none).lines.first?.glyphs.last.map { $0.column + $0.width } ?? 0
}

func paintPlotLabel(_ spans: [TextSpan], in area: Rect, style: Style, buffer: inout Buffer) {
    guard area.width > 0, area.height > 0 else { return }
    TextLayout(spans, width: area.width, wrapping: .none).paint(in: area, style: style, buffer: &buffer)
}
