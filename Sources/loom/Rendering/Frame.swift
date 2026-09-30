import weft

/// The logical screen and cursor produced by one rendering pass.
public struct Frame {
    public var buffer: Buffer
    public var cursor: Point?
    public var area: Rect {
        buffer.area
    }

    public init(width: Int, height: Int) {
        buffer = Buffer(width: width, height: height)
    }

    mutating func reset() {
        buffer.reset()
        cursor = nil
    }

    public mutating func render<W: Widget>(_ widget: W, in area: Rect) {
        widget.render(in: area, buffer: &buffer)
    }
}
