import weft

/// An inclusive selection between two positions in laid-out text.
public struct TextSelection: Equatable, Sendable {
    public var anchor: Point
    public var head: Point

    public init(anchor: Point, head: Point) {
        self.anchor = anchor
        self.head = head
    }
    public var first: Point {
        min(anchor, head)
    }
    public var last: Point {
        max(anchor, head)
    }

    public func intersects(x: Int, y: Int, width: Int) -> Bool {
        guard y >= first.y && y <= last.y else {
            return false
        }
        return x + width > (y == first.y ? first.x : -1) && x <= (y == last.y ? last.x : Int.max)
    }
}
