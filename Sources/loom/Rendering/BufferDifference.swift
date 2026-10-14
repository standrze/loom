import weft

/// One changed terminal cell.
///
/// Nil marks a coordinate outside that buffer's dimensions.
public struct BufferDifference: Equatable, Sendable {
    public var point: Point
    public var before: Cell?
    public var after: Cell?

    public init(point: Point, before: Cell?, after: Cell?) {
        self.point = point
        self.before = before
        self.after = after
    }
}
