import Foundation
import weft

/// Immediate rendering with viewport-local frames and physical terminal output.
///
/// The caller owns raw mode, primary/alternate-screen choice, and input reading.
public struct RenderTerminal<R: RenderBackend> {
    public private(set) var backend: R
    public private(set) var viewport: Viewport
    public private(set) var viewportArea: Rect
    public private(set) var requiresReanchor = false
    private var terminalWidth: Int
    private var terminalHeight: Int
    private var front: Buffer
    private var frame: Frame
    private var presented = false
    private var presentedCursor: Point?
    private var pendingClear: [Rect] = []
    private var pendingAnchor: Point?

    /// An on-demand copy of the last successfully presented logical frame.
    ///
    /// Nil before the first draw, after resize/invalidation, or after output failure.
    public var snapshot: FrameSnapshot? {
        presented ? FrameSnapshot(buffer: front, cursor: presentedCursor) : nil
    }

    public init(
        backend: R, width: Int, height: Int, viewport: Viewport = .fullscreen
    ) {
        self.backend = backend
        self.viewport = viewport
        terminalWidth = max(0, width)
        terminalHeight = max(0, height)
        viewportArea = Self.area(for: viewport, width: max(0, width), height: max(0, height))
        front = Buffer(width: viewportArea.width, height: viewportArea.height)
        frame = Frame(width: viewportArea.width, height: viewportArea.height)
        if case let .inline(_, anchor) = viewport { pendingAnchor = anchor }
    }

    /// Converts a physical terminal position to a local frame position, if inside the viewport.
    public func localPoint(from physicalPoint: Point) -> Point? {
        guard viewportArea.contains(physicalPoint) else { return nil }
        return Point(x: physicalPoint.x - viewportArea.x, y: physicalPoint.y - viewportArea.y)
    }

    /// Converts a valid local frame position to a physical terminal position.
    public func physicalPoint(from localPoint: Point) -> Point? {
        guard front.area.contains(localPoint) else { return nil }
        return Point(x: viewportArea.x + localPoint.x, y: viewportArea.y + localPoint.y)
    }

    public mutating func resize(width: Int, height: Int) {
        let width = max(0, width)
        let height = max(0, height)
        guard width != terminalWidth || height != terminalHeight else { return }
        if presented, viewport != .fullscreen { pendingClear.append(viewportArea) }
        terminalWidth = width
        terminalHeight = height
        if case .inline = viewport { requiresReanchor = true }
        resetFrame(to: Self.area(for: viewport, width: width, height: height))
    }

    /// Changes the owned footprint.
    ///
    /// The previous footprint is erased on the next draw.
    ///
    /// Inline anchors must be confirmed by the caller; this never queries or reads stdin.
    public mutating func setViewport(_ viewport: Viewport) {
        if presented { pendingClear.append(viewportArea) }
        self.viewport = viewport
        requiresReanchor = false
        pendingAnchor = nil
        if case let .inline(_, anchor) = viewport { pendingAnchor = anchor }
        resetFrame(to: Self.area(for: viewport, width: terminalWidth, height: terminalHeight))
    }

    /// Confirms where inline rendering may resume after resize or uncertain output.
    ///
    /// This discards pending insertions and old footprint knowledge. The application
    /// must first establish a safe primary-screen cursor position by its own means.
    public mutating func reanchor(at anchor: Point) throws {
        guard case let .inline(height, _) = viewport else { throw ViewportError.inlineViewportRequired }
        viewport = .inline(height: height, anchor: anchor)
        pendingClear.removeAll()
        pendingAnchor = anchor
        requiresReanchor = false
        resetFrame(to: Self.area(for: viewport, width: terminalWidth, height: terminalHeight))
    }

    /// Repaints after external output.
    ///
    /// Inline output requires a confirmed new anchor.
    public mutating func invalidate() {
        presented = false
        backend.reset()
        if case .inline = viewport { requiresReanchor = true }
    }

    @discardableResult
    public mutating func draw(_ render: (inout Frame) -> Void) throws -> RenderStats {
        guard !requiresReanchor else { throw ViewportError.reanchorRequired }
        frame.reset()
        render(&frame)
        let reservesInline =
            pendingAnchor != nil && terminalWidth > 0 && terminalHeight > 0
            && viewportArea.height > 0 && (pendingAnchor!.x > 0 || viewportArea.height > 1)
        let presentation = RenderPresentation(
            next: FrameSnapshot(buffer: frame.buffer, cursor: frame.cursor), previous: snapshot,
            terminalSize: RenderSize(width: terminalWidth, height: terminalHeight), area: viewportArea,
            clearScreen: viewport == .fullscreen, clears: pendingClear, anchor: pendingAnchor)
        let stats: RenderStats
        do {
            stats = try backend.render(.frame(presentation))
        } catch {
            presented = false
            backend.reset()
            if reservesInline { requiresReanchor = true }
            throw error
        }
        pendingClear.removeAll()
        pendingAnchor = nil
        presentedCursor = frame.cursor.flatMap { front.area.contains($0) ? $0 : nil }
        swap(&front, &frame.buffer)
        presented = true
        return stats
    }

    /// Commits full-width styled rows above an inline frame and redraws its current contents.
    ///
    /// Uses line feeds on the primary screen, preserving scrollback. Short rows are
    /// padded; excess columns are clipped at whole graphemes. Failure may mean partial
    /// insertion: subsequent draws and insertions require explicit `reanchor(at:)`.
    public mutating func insertBefore(_ content: Buffer) throws {
        guard case .inline = viewport else { throw ViewportError.inlineViewportRequired }
        guard !requiresReanchor else { throw ViewportError.reanchorRequired }
        guard content.height > 0, terminalWidth > 0, terminalHeight > 0, viewportArea.height > 0 else { return }
        // Establish the reservation first; its failure also makes cursor position unknown.
        if pendingAnchor != nil { _ = try draw { _ in } }
        // Count physical line advances without risking overflow on large content.
        let physicalRow = viewportArea.y + min(content.height, terminalHeight - 1 - viewportArea.y)
        let newArea = Rect(
            x: 0, y: min(physicalRow, max(0, terminalHeight - viewportArea.height)),
            width: viewportArea.width, height: viewportArea.height)
        let insertion = RenderInsertion(
            content: content, retained: FrameSnapshot(buffer: front, cursor: presentedCursor),
            terminalSize: RenderSize(width: terminalWidth, height: terminalHeight),
            oldArea: viewportArea, newArea: newArea)
        do {
            _ = try backend.render(.insertion(insertion))
        } catch {
            presented = false
            requiresReanchor = true
            backend.reset()
            throw error
        }
        viewportArea = newArea
    }

    /// Builds styled rows to commit above an inline viewport.
    public mutating func insertBefore(height: Int, render: (inout Frame) -> Void) throws {
        var insertion = Frame(width: terminalWidth, height: max(0, height))
        render(&insertion)
        try insertBefore(insertion.buffer)
    }

    private mutating func resetFrame(to area: Rect) {
        viewportArea = area
        front = Buffer(width: area.width, height: area.height)
        frame = Frame(width: area.width, height: area.height)
        presented = false
        presentedCursor = nil
        backend.reset()
    }

    private static func area(for viewport: Viewport, width: Int, height: Int) -> Rect {
        switch viewport {
        case .fullscreen:
            return Rect(width: width, height: height)
        case let .fixed(area):
            let x = min(width, max(0, area.x))
            let y = min(height, max(0, area.y))
            let (rightEdge, rightOverflow) = area.x.addingReportingOverflow(area.width)
            let (bottomEdge, bottomOverflow) = area.y.addingReportingOverflow(area.height)
            let right = min(width, max(x, rightOverflow ? Int.max : rightEdge))
            let bottom = min(height, max(y, bottomOverflow ? Int.max : bottomEdge))
            return Rect(x: x, y: y, width: right - x, height: bottom - y)
        case let .inline(requestedHeight, anchor):
            let rows = min(height, max(0, requestedHeight))
            let start = min(max(0, height - 1), max(0, anchor.y))
            let nextRow = min(height, start + (anchor.x > 0 ? 1 : 0))
            return Rect(x: 0, y: min(nextRow, max(0, height - rows)), width: width, height: rows)
        }
    }
}
