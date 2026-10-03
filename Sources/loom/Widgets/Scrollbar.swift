/// Caller-owned pointer capture for a scrollbar thumb.
public struct ScrollbarDrag: Sendable {
    fileprivate var grabOffset: Int
}

/// A reusable scrollbar for any content measured by `ScrollState`.
///
/// Vertical bars occupy the area's first column; horizontal bars occupy its first row.
/// Route drag/up events to the captured bar even when the pointer leaves its track.
public struct Scrollbar: Widget {
    public var state: ScrollState
    public var direction: Direction
    public var trackStyle = Style(foreground: .indexed(8))
    public var thumbStyle = Style()
    public var hidesWhenUnneeded = true

    public init(_ state: ScrollState, direction: Direction = .vertical) {
        self.state = state
        self.direction = direction
    }

    public func trackArea(in area: Rect) -> Rect {
        Rect(
            x: area.x, y: area.y,
            width: direction == .vertical ? min(1, area.width) : area.width,
            height: direction == .vertical ? area.height : min(1, area.height))
    }

    /// Thumb cells relative to the start of the track.
    public func thumbRange(length: Int) -> Range<Int> {
        let length = max(0, length)
        guard length > 0 else { return 0..<0 }
        guard state.contentLength > state.viewportLength else { return 0..<length }
        let size = max(1, scaled(state.viewportLength, by: length, dividedBy: state.contentLength))
        let start = scaled(state.offset, by: length - size, dividedBy: state.maximumOffset)
        return start..<(start + size)
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        guard !hidesWhenUnneeded || state.maximumOffset > 0 else { return }
        let track = trackArea(in: area)
        guard track.width > 0, track.height > 0 else { return }
        let length = direction == .vertical ? track.height : track.width
        let thumb = thumbRange(length: length)
        buffer.withClip(track) { buffer in
            for cell in 0..<length {
                let point = Point(
                    x: track.x + (direction == .horizontal ? cell : 0),
                    y: track.y + (direction == .vertical ? cell : 0))
                buffer.put(
                    thumb.contains(cell) ? "█" : (direction == .vertical ? "│" : "─"), width: 1,
                    at: point, style: thumb.contains(cell) ? thumbStyle : trackStyle)
            }
        }
    }

    /// Track clicks page; thumb drags preserve the pointer's grab position; wheel events scroll.
    @discardableResult
    public func handle(
        _ mouse: MouseEvent, in area: Rect, state: inout ScrollState, drag: inout ScrollbarDrag?
    ) -> Bool {
        if mouse.kind == .up {
            let captured = drag != nil
            drag = nil
            return captured
        }
        let track = trackArea(in: area)
        let length = direction == .vertical ? track.height : track.width
        guard length > 0, track.width > 0, track.height > 0 else { return false }
        var current = self
        current.state = state
        let thumb = current.thumbRange(length: length)
        let position = direction == .vertical ? mouse.position.y - track.y : mouse.position.x - track.x
        if mouse.kind == .drag, let capture = drag {
            let travel = length - thumb.count
            guard travel > 0 else { return true }
            let location = min(travel, max(0, position - capture.grabOffset))
            state.scroll(to: scaled(location, by: state.maximumOffset, dividedBy: travel))
            return true
        }
        guard track.contains(mouse.position), !hidesWhenUnneeded || state.maximumOffset > 0 else { return false }
        if mouse.kind == .down {
            if thumb.contains(position) {
                drag = ScrollbarDrag(grabOffset: position - thumb.lowerBound)
            } else {
                drag = nil
                state.scrollPage(by: position < thumb.lowerBound ? -1 : 1)
            }
            return true
        }
        return state.handle(.mouse(mouse), axis: direction)
    }

    private func scaled(_ value: Int, by multiplier: Int, dividedBy divisor: Int) -> Int {
        guard divisor > 0 else { return 0 }
        let product = UInt(value).multipliedFullWidth(by: UInt(multiplier))
        return Int(UInt(divisor).dividingFullWidth(product).quotient)
    }
}
