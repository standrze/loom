/// Application-owned scrolling along one axis, measured in terminal cells.
public struct ScrollState: Equatable, Sendable {
    public private(set) var contentLength: Int
    public private(set) var viewportLength: Int
    public private(set) var offset: Int
    public private(set) var followsEnd: Bool

    public var maximumOffset: Int { max(0, contentLength - viewportLength) }
    public var isAtStart: Bool { offset == 0 }
    public var isAtEnd: Bool { offset == maximumOffset }
    public var visibleRange: Range<Int> { offset..<(offset + min(viewportLength, contentLength - offset)) }

    public init(contentLength: Int = 0, viewportLength: Int = 0, offset: Int = 0, followsEnd: Bool = false) {
        self.contentLength = max(0, contentLength)
        self.viewportLength = max(0, viewportLength)
        self.offset = 0
        self.followsEnd = followsEnd
        self.offset = followsEnd ? maximumOffset : min(max(0, offset), maximumOffset)
    }

    /// Updates metrics after content changes or resize, preserving the offset or following the end.
    public mutating func update(contentLength: Int, viewportLength: Int) {
        self.contentLength = max(0, contentLength)
        self.viewportLength = max(0, viewportLength)
        offset = followsEnd ? maximumOffset : min(offset, maximumOffset)
    }

    /// Moves to a clamped cell offset.
    ///
    /// Moving away from the end stops automatic following.
    public mutating func scroll(to offset: Int) {
        self.offset = min(max(0, offset), maximumOffset)
        followsEnd = followsEnd && isAtEnd
    }

    public mutating func scroll(by cells: Int) {
        let delta = cells >= 0 ? min(cells, maximumOffset - offset) : max(cells, -offset)
        scroll(to: offset + delta)
    }

    public mutating func scrollPage(by pages: Int) {
        let distance = max(1, viewportLength).multipliedReportingOverflow(by: pages)
        scroll(by: distance.overflow ? (pages < 0 ? Int.min : Int.max) : distance.partialValue)
    }

    public mutating func scrollToEnd(follow: Bool = false) {
        offset = maximumOffset
        followsEnd = follow
    }

    /// Reveals a cell range; a range larger than the viewport is aligned to its start.
    public mutating func reveal(_ range: Range<Int>, padding: Int = 0) {
        guard !range.isEmpty, viewportLength > 0 else { return }
        let start = max(0, min(range.lowerBound, contentLength))
        let end = max(start, min(range.upperBound, contentLength))
        let margin = min(max(0, padding), max(0, (viewportLength - (end - start)) / 2))
        if start - margin < offset || end - start > viewportLength {
            scroll(to: max(0, start - margin))
        } else if end > offset + viewportLength - margin {
            scroll(to: min(maximumOffset, end - viewportLength + margin))
        }
    }

    /// Optional default navigation.
    ///
    /// The caller routes only events belonging to this viewport.
    @discardableResult
    public mutating func handle(_ event: InputEvent, axis: Direction = .vertical, wheelStep: Int = 3) -> Bool {
        if case let .mouse(mouse) = event {
            switch mouse.kind {
            case .wheelUp: scroll(by: -max(0, wheelStep))
            case .wheelDown: scroll(by: max(0, wheelStep))
            default: return false
            }
            return true
        }
        let backward: Key = axis == .vertical ? .up : .left
        let forward: Key = axis == .vertical ? .down : .right
        if KeyChord(backward).matches(event) {
            scroll(by: -1)
        } else if KeyChord(forward).matches(event) {
            scroll(by: 1)
        } else if KeyChord(.pageUp).matches(event) {
            scrollPage(by: -1)
        } else if KeyChord(.pageDown).matches(event) {
            scrollPage(by: 1)
        } else if KeyChord(.home).matches(event) {
            scroll(to: 0)
        } else if KeyChord(.end).matches(event) {
            scrollToEnd()
        } else {
            return false
        }
        return true
    }
}
