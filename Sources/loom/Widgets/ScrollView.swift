/// A clipped view of a caller-owned cell buffer, with independent horizontal and vertical offsets.
///
/// The content buffer can be cached between draws. This widget copies only visible cells;
/// it does not allocate a second content-sized buffer. Wide glyphs cut by either edge are omitted.
public struct ScrollView: Widget {
    public var content: Buffer
    public var horizontalOffset: Int
    public var verticalOffset: Int

    public init(_ content: Buffer, horizontalOffset: Int = 0, verticalOffset: Int = 0) {
        self.content = content
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        let xOffset = min(content.width, max(0, horizontalOffset))
        let yOffset = min(content.height, max(0, verticalOffset))
        let columns = max(0, min(area.width, content.width - xOffset))
        let rows = max(0, min(area.height, content.height - yOffset))
        buffer.withClip(area) { buffer in
            fillCollectionArea(area, style: Style(), buffer: &buffer)
            for y in 0..<rows {
                for x in 0..<columns {
                    let cell = content[x + xOffset, y + yOffset]
                    guard cell.width > 0, cell.width <= columns - x else { continue }
                    buffer.put(
                        cell.symbol, width: cell.width, at: Point(x: area.x + x, y: area.y + y),
                        style: cell.style, link: cell.link)
                }
            }
        }
    }

    /// Translates a viewport hit to content coordinates, excluding blank padding.
    public func contentPoint(at point: Point, in area: Rect) -> Point? {
        guard area.contains(point) else { return nil }
        let x = min(content.width, max(0, horizontalOffset))
        let y = min(content.height, max(0, verticalOffset))
        let column = point.x - area.x
        let row = point.y - area.y
        guard column < content.width - x, row < content.height - y else { return nil }
        return Point(x: x + column, y: y + row)
    }
}
