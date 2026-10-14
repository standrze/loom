/// Clears a rectangle to blank default cells, preserving boundary-crossing wide glyphs.
public struct Clear: Widget {
    public init() {}

    public func render(in area: Rect, buffer: inout Buffer) {
        Fill().render(in: area, buffer: &buffer)
    }
}
