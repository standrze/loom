import weft

/// Nonnegative physical terminal dimensions in cells.
public struct RenderSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

/// A semantic rendering operation.
///
/// Coordinates outside frame buffers are physical cells.
public enum RenderUpdate: Sendable {
    case frame(RenderPresentation)
    case insertion(RenderInsertion)
}

/// A logical frame plus the terminal operations needed to place it.
public struct RenderPresentation: Sendable {
    public let next: FrameSnapshot
    public let previous: FrameSnapshot?
    public let terminalSize: RenderSize
    public let area: Rect
    public let clearScreen: Bool
    public let clears: [Rect]
    public let anchor: Point?

    public init(
        next: FrameSnapshot, previous: FrameSnapshot?, terminalSize: RenderSize, area: Rect,
        clearScreen: Bool, clears: [Rect] = [], anchor: Point? = nil
    ) {
        self.next = next
        self.previous = previous
        self.terminalSize = terminalSize
        self.area = area
        self.clearScreen = clearScreen
        self.clears = clears
        self.anchor = anchor
    }
}

/// Full-width transcript insertion, followed by repainting the retained inline frame.
public struct RenderInsertion: Sendable {
    public let content: Buffer
    public let retained: FrameSnapshot
    public let terminalSize: RenderSize
    public let oldArea: Rect
    public let newArea: Rect

    public init(content: Buffer, retained: FrameSnapshot, terminalSize: RenderSize, oldArea: Rect, newArea: Rect) {
        self.content = content
        self.retained = retained
        self.terminalSize = terminalSize
        self.oldArea = oldArea
        self.newArea = newArea
    }
}

/// Receives whole presentation operations without owning terminal modes or input.
///
/// Throwing may mean partial output. The driver invalidates its frame and requires
/// an explicit inline reanchor whenever an operation could have scrolled.
public protocol RenderBackend {
    mutating func render(_ update: RenderUpdate) throws -> RenderStats
    mutating func reset()
}

extension RenderBackend {
    public mutating func reset() {}
}
