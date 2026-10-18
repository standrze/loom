import Foundation
import weft

/// A position in caller-defined Cartesian coordinates; positive y points upward.
public struct CanvasPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Finite, increasing coordinate limits.
///
/// Invalid limits cause the canvas to paint nothing.
public struct CanvasBounds: Equatable, Sendable {
    public var min: Double
    public var max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }

    var valid: Bool { min.isFinite && max.isFinite && min < max }

    func fraction(_ value: Double) -> Double {
        let span = max - min
        if span.isFinite { return (value - min) / span }
        return (value / 2 - min / 2) / (max / 2 - min / 2)
    }
}

/// Raster resolution inside each terminal cell.
public enum CanvasMarker: Sendable {
    /// Two columns and four rows of dots per cell.
    case braille
    case quadrant
    case sextant
    case octant
    /// A single terminal-cell grapheme. Invalid or wide characters paint nothing.
    case custom(Character)
    case dot
    /// One point per cell using an open circle.
    case circle
    /// One point per cell using a lower half block.
    case bar
    case block
    /// One column and two rows per cell.
    case halfBlock

    var resolution: (x: Int, y: Int) {
        switch self {
        case .braille, .octant: return (2, 4)
        case .quadrant: return (2, 2)
        case .sextant: return (2, 3)
        case .halfBlock: return (1, 2)
        case .dot, .circle, .bar, .block, .custom: return (1, 1)
        }
    }
}

/// A clipped coordinate-space rasterizer.
///
/// It changes logical cells and performs no terminal I/O.
/// Empty cells remain untouched. Shapes in one layer combine their dots; later strokes own cell style.
public struct Canvas: Widget {
    public var xBounds: CanvasBounds
    public var yBounds: CanvasBounds
    public var marker: CanvasMarker
    public var style: Style
    public var paint: (inout CanvasContext) -> Void

    public init(
        xBounds: CanvasBounds, yBounds: CanvasBounds, marker: CanvasMarker = .braille,
        style: Style = Style(), paint: @escaping (inout CanvasContext) -> Void
    ) {
        self.xBounds = xBounds
        self.yBounds = yBounds
        self.marker = marker
        self.style = style
        self.paint = paint
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        guard xBounds.valid, yBounds.valid, area.width > 0, area.height > 0 else { return }
        let area = representableBorderArea(area)
        let left = max(0, area.x)
        let top = max(0, area.y)
        let right = min(buffer.width, area.maxX)
        let bottom = min(buffer.height, area.maxY)
        guard left < right, top < bottom else { return }
        buffer.withClip(area) { target in
            var context = CanvasContext(
                buffer: target, area: area, visible: Rect(x: left, y: top, width: right - left, height: bottom - top),
                xBounds: xBounds, yBounds: yBounds, marker: marker, style: style)
            paint(&context)
            context.newLayer()
            target = context.buffer
        }
    }
}

/// Drawing commands for a Canvas.
///
/// Coordinates are independent of terminal cell dimensions.
public struct CanvasContext {
    private struct RasterCell {
        var bits: Int
        var style: Style
    }
    private struct Key: Hashable {
        var x: Int
        var y: Int
    }
    var buffer: Buffer
    private let area: Rect
    private let visible: Rect
    private let xBounds: CanvasBounds
    private let yBounds: CanvasBounds
    private let marker: CanvasMarker
    private let style: Style
    private var cells: [Key: RasterCell] = [:]

    init(
        buffer: Buffer, area: Rect, visible: Rect, xBounds: CanvasBounds, yBounds: CanvasBounds,
        marker: CanvasMarker, style: Style
    ) {
        self.buffer = buffer
        self.area = area
        self.visible = visible
        self.xBounds = xBounds
        self.yBounds = yBounds
        self.marker = marker
        self.style = style
    }

    /// Adds a dot if the finite coordinate lies inside the canvas.
    public mutating func point(at point: CanvasPoint, style: Style? = nil) {
        guard point.x >= xBounds.min, point.x <= xBounds.max,
            point.y >= yBounds.min, point.y <= yBounds.max,
            let pixel = pixel(point), contains(pixel)
        else { return }
        put(x: Int(pixel.x.rounded()), y: Int(pixel.y.rounded()), style: style ?? self.style)
    }

    public mutating func points(_ points: [CanvasPoint], style: Style? = nil) {
        for point in points { self.point(at: point, style: style) }
    }

    /// Clips crossing segments before rasterization, even when both endpoints are outside the bounds.
    public mutating func line(from start: CanvasPoint, to end: CanvasPoint, style: Style? = nil) {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
            let world = clipped(
                start, end,
                lower: CanvasPoint(x: xBounds.min, y: yBounds.min),
                upper: CanvasPoint(x: xBounds.max, y: yBounds.max)),
            let first = pixel(world.0), let last = pixel(world.1),
            let segment = clipped(first, last, lower: pixelLimits.0, upper: pixelLimits.1)
        else { return }
        var x = Int(segment.0.x.rounded())
        var y = Int(segment.0.y.rounded())
        let endX = Int(segment.1.x.rounded())
        let endY = Int(segment.1.y.rounded())
        let dx = abs(endX - x)
        let dy = -abs(endY - y)
        let stepX = x < endX ? 1 : -1
        let stepY = y < endY ? 1 : -1
        var error = dx + dy
        while true {
            put(x: x, y: y, style: style ?? self.style)
            if x == endX && y == endY { break }
            let twice = 2 * error
            if twice >= dy {
                error += dy
                x += stepX
            }
            if twice <= dx {
                error += dx
                y += stepY
            }
        }
    }

    /// Fills vertical raster columns between a segment and an explicit horizontal baseline.
    ///
    /// Non-finite inputs paint nothing. Work is bounded by the visible raster, even for
    /// offscreen endpoints; vertical and zero-length segments fill their baseline column.
    public mutating func filledLine(
        from start: CanvasPoint, to end: CanvasPoint, baseline: Double, style: Style? = nil
    ) {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
            baseline.isFinite
        else { return }
        if start.x == end.x {
            line(from: CanvasPoint(x: start.x, y: baseline), to: start, style: style)
            line(from: CanvasPoint(x: end.x, y: baseline), to: end, style: style)
            return
        }
        // Clip in world x before interpolation. This retains visible diagonals when the
        // original endpoints are so distant that all visible t parameters round to 0.5.
        guard
            let segment = clipped(
                start, end,
                lower: CanvasPoint(x: xBounds.min, y: min(start.y, end.y)),
                upper: CanvasPoint(x: xBounds.max, y: max(start.y, end.y)))
        else { return }
        let first = segment.0
        let last = segment.1
        let limits = pixelLimits
        let resolution = marker.resolution
        let rasterWidth = Double(area.width) * Double(resolution.x) - 1
        let rasterOrigin = Double(area.x) * Double(resolution.x)
        let firstColumn = rasterOrigin + xBounds.fraction(first.x) * rasterWidth
        let lastColumn = rasterOrigin + xBounds.fraction(last.x) * rasterWidth
        let left = max(limits.0.x, min(firstColumn, lastColumn).rounded())
        let right = min(limits.1.x, max(firstColumn, lastColumn).rounded())
        guard left <= right else { return }
        for column in Int(left)...Int(right) {
            let fraction = rasterWidth > 0 ? (Double(column) - rasterOrigin) / rasterWidth : 0.5
            let sampleX = (1 - fraction) * xBounds.min + fraction * xBounds.max
            // Endpoint columns belong to the segment even when its endpoints fall between
            // raster samples. Clamp evaluation while retaining the same rounded column.
            let x = min(max(first.x, last.x), max(min(first.x, last.x), sampleX))
            let span = last.x - first.x
            let t: Double
            if span == 0 {
                t = 0
            } else if span.isFinite {
                t = (x - first.x) / span
            } else {
                t = (x / 2 - first.x / 2) / (last.x / 2 - first.x / 2)
            }
            let y = (1 - t) * first.y + t * last.y
            guard y.isFinite else { continue }
            line(from: CanvasPoint(x: x, y: baseline), to: CanvasPoint(x: x, y: y), style: style)
        }
    }

    /// Draws an outline or filled rectangle.
    ///
    /// Negative sizes are accepted; zero sizes produce a line or point.
    public mutating func rectangle(
        origin: CanvasPoint, width: Double, height: Double, style: Style? = nil, filled: Bool = false
    ) {
        let opposite = CanvasPoint(x: origin.x + width, y: origin.y + height)
        guard width.isFinite, height.isFinite, origin.x.isFinite, origin.y.isFinite,
            opposite.x.isFinite, opposite.y.isFinite
        else { return }
        if filled {
            let minimum = CanvasPoint(
                x: max(xBounds.min, min(origin.x, opposite.x)),
                y: max(yBounds.min, min(origin.y, opposite.y)))
            let maximum = CanvasPoint(
                x: min(xBounds.max, max(origin.x, opposite.x)),
                y: min(yBounds.max, max(origin.y, opposite.y)))
            guard minimum.x <= maximum.x, minimum.y <= maximum.y,
                let first = pixel(minimum), let last = pixel(maximum)
            else { return }
            let limits = pixelLimits
            let left = max(limits.0.x, min(first.x, last.x))
            let right = min(limits.1.x, max(first.x, last.x))
            let top = max(limits.0.y, min(first.y, last.y))
            let bottom = min(limits.1.y, max(first.y, last.y))
            guard left <= right, top <= bottom else { return }
            for y in Int(top.rounded())...Int(bottom.rounded()) {
                for x in Int(left.rounded())...Int(right.rounded()) { put(x: x, y: y, style: style ?? self.style) }
            }
        } else {
            let lowerRight = CanvasPoint(x: opposite.x, y: origin.y)
            let upperLeft = CanvasPoint(x: origin.x, y: opposite.y)
            line(from: origin, to: lowerRight, style: style)
            line(from: lowerRight, to: opposite, style: style)
            line(from: opposite, to: upperLeft, style: style)
            line(from: upperLeft, to: origin, style: style)
        }
    }

    /// Draws a circle outline, sampling in proportion to the visible raster size.
    public mutating func circle(center: CanvasPoint, radius: Double, style: Style? = nil) {
        guard center.x.isFinite, center.y.isFinite, radius.isFinite, radius >= 0 else { return }
        guard radius > 0 else {
            point(at: center, style: style)
            return
        }
        let resolution = marker.resolution
        let steps = max(12, 4 * (visible.width * resolution.x + visible.height * resolution.y))
        var previous = CanvasPoint(x: center.x + radius, y: center.y)
        for index in 1...steps {
            let angle = Double(index) * 2 * Double.pi / Double(steps)
            let next = CanvasPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            line(from: previous, to: next, style: style)
            previous = next
        }
    }

    /// Flushes the current raster layer, then writes Unicode text anchored at its top-left cell.
    ///
    /// Whole graphemes crossing the canvas or enclosing buffer clip are omitted.
    public mutating func print(_ text: String, at point: CanvasPoint, style: Style? = nil) {
        guard point.x >= xBounds.min, point.x <= xBounds.max,
            point.y >= yBounds.min, point.y <= yBounds.max,
            let pixel = pixel(point), contains(pixel)
        else { return }
        newLayer()
        let resolution = marker.resolution
        let x = Int(pixel.x.rounded()) / resolution.x
        let y = Int(pixel.y.rounded()) / resolution.y
        let width = visible.maxX - x
        let height = visible.maxY - y
        guard width > 0, height > 0 else { return }
        TextLayout(text, width: Int.max, wrapping: .none).paint(
            in: Rect(x: x, y: y, width: width, height: height),
            style: style ?? self.style, buffer: &buffer)
    }

    /// Commits accumulated dots.
    ///
    /// The next layer may replace glyphs and styles in the same cells.
    public mutating func newLayer() {
        for (key, cell) in cells {
            let symbol: String
            switch marker {
            case .quadrant: symbol = CanvasMarkerSymbols.quadrants[cell.bits]
            case .sextant: symbol = CanvasMarkerSymbols.sextants[cell.bits]
            case .octant: symbol = CanvasMarkerSymbols.octants[cell.bits]
            case .custom(let character):
                let text = String(character)
                let glyphs = TextLayout(text, width: 2, wrapping: .none).lines.flatMap(\.glyphs)
                guard glyphs.count == 1, glyphs[0].width == 1, glyphs[0].text == text else { continue }
                symbol = text
            case .braille: symbol = String(UnicodeScalar(0x2800 + cell.bits)!)
            case .halfBlock: symbol = cell.bits == 3 ? "█" : cell.bits == 1 ? "▀" : "▄"
            case .dot: symbol = "•"
            case .circle: symbol = "○"
            case .bar: symbol = "▄"
            case .block: symbol = "█"
            }
            buffer.put(symbol, width: 1, at: Point(x: key.x, y: key.y), style: cell.style)
        }
        cells.removeAll(keepingCapacity: true)
    }

    private var pixelLimits: (CanvasPoint, CanvasPoint) {
        let resolution = marker.resolution
        return (
            CanvasPoint(x: Double(visible.x * resolution.x), y: Double(visible.y * resolution.y)),
            CanvasPoint(x: Double(visible.maxX * resolution.x - 1), y: Double(visible.maxY * resolution.y - 1))
        )
    }

    private func contains(_ point: CanvasPoint) -> Bool {
        let limits = pixelLimits
        return point.x >= limits.0.x && point.x <= limits.1.x && point.y >= limits.0.y && point.y <= limits.1.y
    }

    private func pixel(_ point: CanvasPoint) -> CanvasPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let resolution = marker.resolution
        let x =
            Double(area.x) * Double(resolution.x)
            + xBounds.fraction(point.x) * (Double(area.width) * Double(resolution.x) - 1)
        let y =
            Double(area.y) * Double(resolution.y)
            + (1 - yBounds.fraction(point.y)) * (Double(area.height) * Double(resolution.y) - 1)
        guard x.isFinite, y.isFinite else { return nil }
        return CanvasPoint(x: x, y: y)
    }

    private mutating func put(x: Int, y: Int, style: Style) {
        guard contains(CanvasPoint(x: Double(x), y: Double(y))) else { return }
        let resolution = marker.resolution
        let key = Key(x: x / resolution.x, y: y / resolution.y)
        let bit: Int
        switch marker {
        case .braille:
            let bits = [[1, 2, 4, 64], [8, 16, 32, 128]]
            bit = bits[x % 2][y % 4]
        case .quadrant, .sextant, .octant:
            bit = 1 << ((y % resolution.y) * 2 + x % 2)
        case .halfBlock: bit = 1 << (y % 2)
        case .dot, .circle, .bar, .block, .custom: bit = 1
        }
        cells[key] = RasterCell(bits: (cells[key]?.bits ?? 0) | bit, style: style)
    }

    private func clipped(
        _ first: CanvasPoint, _ last: CanvasPoint, lower: CanvasPoint, upper: CanvasPoint
    ) -> (CanvasPoint, CanvasPoint)? {
        var dx = last.x - first.x
        var dy = last.y - first.y
        if !dx.isFinite || !dy.isFinite {
            dx = last.x / 2 - first.x / 2
            dy = last.y / 2 - first.y / 2
        }
        if dx == 0, dy == 0 {
            guard first.x >= lower.x, first.x <= upper.x,
                first.y >= lower.y, first.y <= upper.y
            else { return nil }
            return (first, first)
        }
        // Express the secondary axis against the dominant axis. Its slope is bounded by one.
        // A midpoint anchor and fused multiply-add retain cancellation for enormous crossings;
        // unlike t parameters, the exact clip boundaries never collapse into one parameter.
        let swap = abs(dy) > abs(dx)
        let a = swap ? first.y : first.x
        let b = swap ? last.y : last.x
        let c = swap ? first.x : first.y
        let d = swap ? last.x : last.y
        let primaryLow = swap ? lower.y : lower.x
        let primaryHigh = swap ? upper.y : upper.x
        let secondaryLow = swap ? lower.x : lower.y
        let secondaryHigh = swap ? upper.x : upper.y
        let slope = swap ? dx / dy : dy / dx
        func midpoint(_ a: Double, _ b: Double) -> Double {
            let delta = b - a
            return delta.isFinite ? a + delta / 2 : a / 2 + b / 2
        }
        let intercept = midpoint(c, d).addingProduct(-slope, midpoint(a, b))
        guard intercept.isFinite else { return nil }
        var start = max(primaryLow, min(a, b))
        var end = min(primaryHigh, max(a, b))
        guard start <= end else { return nil }
        if slope == 0 {
            guard intercept >= secondaryLow, intercept <= secondaryHigh else { return nil }
        } else {
            let crossingLow = (secondaryLow - intercept) / slope
            let crossingHigh = (secondaryHigh - intercept) / slope
            start = max(start, min(crossingLow, crossingHigh))
            end = min(end, max(crossingLow, crossingHigh))
            guard start <= end else { return nil }
        }
        func position(_ primary: Double) -> CanvasPoint {
            let secondary = min(secondaryHigh, max(secondaryLow, intercept.addingProduct(slope, primary)))
            return swap ? CanvasPoint(x: secondary, y: primary) : CanvasPoint(x: primary, y: secondary)
        }
        return (position(start), position(end))
    }
}

/// An application-defined coordinate-space shape; compose the context's clipped drawing commands.
public protocol CanvasShape {
    func draw(in context: inout CanvasContext)
}

extension CanvasContext {
    /// Draws a custom shape into the current layer.
    public mutating func draw<S: CanvasShape>(_ shape: S) {
        shape.draw(in: &self)
    }
}
