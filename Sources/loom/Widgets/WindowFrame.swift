import weft

/// A single floating window's terminal-cell geometry and pointer interaction.
///
/// The caller owns its content and paints it inside `bounds`. This type draws only
/// the border and controls. Pointer events starting in the content remain available
/// to the caller, so text selection and other body interactions stay independent.
public struct WindowFrame: Widget {
    public private(set) var viewport: Rect
    public private(set) var bounds: Rect
    public private(set) var isExpanded = false
    public var style = Style()
    /// Places the draggable title row below the top border.
    public var insetTitle = false
    /// A source-compatible alias for `insetTitle`; resizing always starts at the lower-right border.
    public var edgeResizing: Bool {
        get { insetTitle }
        set { insetTitle = newValue }
    }

    private let minimumWidth: Int
    private let minimumHeight: Int
    private var normalBounds: Rect
    private var interaction: Interaction?

    private enum Interaction {
        case moving(anchor: Point, original: Rect)
        case resizing(anchor: Point, original: Rect)
    }

    /// Creates a centered window, bounded by the available terminal-cell viewport.
    public init(
        viewport: Rect, preferredWidth: Int, preferredHeight: Int,
        minimumWidth: Int = 24, minimumHeight: Int = 8
    ) {
        self.viewport = viewport
        self.minimumWidth = max(1, minimumWidth)
        self.minimumHeight = max(1, minimumHeight)
        let width = min(viewport.width, max(self.minimumWidth, preferredWidth))
        let height = min(viewport.height, max(self.minimumHeight, preferredHeight))
        let initialBounds = Rect(
            x: viewport.x + (viewport.width - width) / 2,
            y: viewport.y + (viewport.height - height) / 2,
            width: width, height: height)
        bounds = initialBounds
        normalBounds = initialBounds
    }

    /// The space inside the border, measured in terminal cells.
    public var contentArea: Rect { bounds.inset() }

    /// The draggable row between the corners, below the top border when `insetTitle` is enabled.
    public var titleArea: Rect {
        guard bounds.height >= (insetTitle ? 3 : 1) else { return Rect(width: 0, height: 0) }
        return Rect(x: bounds.x + 1, y: bounds.y + (insetTitle ? 1 : 0), width: max(0, bounds.width - 2), height: 1)
    }

    /// The three-cell control just inside the upper-right border.
    public var expandButton: Rect {
        guard bounds.width >= 7, bounds.height >= 3 else { return Rect(width: 0, height: 0) }
        return Rect(x: bounds.maxX - 4, y: bounds.y + 1, width: 3, height: 1)
    }

    /// The inset minimize control immediately left of expand.
    public var minimizeButton: Rect {
        guard bounds.width >= 30, bounds.height >= 3 else { return Rect(width: 0, height: 0) }
        return Rect(x: bounds.maxX - 8, y: bounds.y + 1, width: 3, height: 1)
    }

    /// The lower-right border's resize region, measured in terminal cells.
    ///
    /// Only its outer border cells resize the window; use `isResizeHandle(at:)` for hit testing.
    public var resizeHandle: Rect {
        guard bounds.width > 0, bounds.height > 0, !isExpanded else {
            return Rect(width: 0, height: 0)
        }
        let width = min(3, bounds.width)
        let height = min(2, bounds.height)
        return Rect(x: bounds.maxX - width, y: bounds.maxY - height, width: width, height: height)
    }

    /// Tests the connected bottom and right border cells beside the lower-right corner.
    public func isResizeHandle(at point: Point) -> Bool {
        resizeHandle.contains(point) && (point.x == bounds.maxX - 1 || point.y == bounds.maxY - 1)
    }

    /// Clamps the window to a new terminal-cell viewport while retaining its normal size.
    ///
    /// An expanded window continues to fill the viewport. Repeating the current viewport preserves active drags.
    public mutating func resizeViewport(to viewport: Rect) {
        guard viewport != self.viewport else { return }
        self.viewport = viewport
        interaction = nil
        bounds = isExpanded ? viewport : clamped(normalBounds)
    }

    /// Expands to the viewport or restores the previous window bounds.
    public mutating func toggleExpanded() {
        interaction = nil
        if isExpanded {
            isExpanded = false
            bounds = clamped(normalBounds)
        } else {
            normalBounds = bounds
            bounds = viewport
            isExpanded = true
        }
    }

    /// Moves an unexpanded window by terminal cells, keeping it inside the viewport.
    public mutating func move(byColumns columns: Int, rows: Int) {
        guard !isExpanded else { return }
        bounds = clamped(
            Rect(
                x: bounds.x + columns, y: bounds.y + rows,
                width: bounds.width, height: bounds.height))
        normalBounds = bounds
    }

    /// Resizes an unexpanded window by terminal cells, subject to its minimum size.
    public mutating func resize(byColumns columns: Int, rows: Int) {
        guard !isExpanded else { return }
        bounds = resized(bounds, byColumns: columns, rows: rows)
        normalBounds = bounds
    }

    /// Handles title dragging, lower-right border resizing, and expand/restore clicks.
    ///
    /// Returns true only for window-chrome interactions; the caller handles body input.
    @discardableResult
    public mutating func handleMouse(_ mouse: MouseEvent) -> Bool {
        switch mouse.kind {
        case .down:
            interaction = nil
            if expandButton.contains(mouse.position) {
                toggleExpanded()
                return true
            }
            if isResizeHandle(at: mouse.position) {
                interaction = .resizing(anchor: mouse.position, original: bounds)
                return true
            }
            if titleArea.contains(mouse.position) {
                interaction = .moving(anchor: mouse.position, original: bounds)
                return true
            }
            return false
        case .drag:
            guard interaction != nil else { return false }
            updateInteraction(at: mouse.position)
            return true
        case .up:
            guard interaction != nil else { return false }
            updateInteraction(at: mouse.position)
            interaction = nil
            return true
        default:
            return false
        }
    }

    /// Draws a thin square border and inset window controls.
    ///
    /// Pass `bounds` as `area` so rendering and hit testing use the same cells.
    public func render(in area: Rect, buffer: inout Buffer) {
        Panel(style: style, borderType: .single).render(in: area, buffer: &buffer)
        if minimizeButton.width > 0 {
            for (offset, character) in "[−]".enumerated() {
                buffer.put(
                    String(character), width: 1,
                    at: Point(x: minimizeButton.x + offset, y: minimizeButton.y), style: style)
            }
        }
        let symbol = isExpanded ? "▣" : "□"
        if expandButton.width > 0 {
            for (offset, character) in ("[" + symbol + "]").enumerated() {
                buffer.put(
                    String(character), width: 1,
                    at: Point(x: expandButton.x + offset, y: expandButton.y), style: style)
            }
        }
    }

    private mutating func updateInteraction(at point: Point) {
        guard let interaction, !isExpanded else { return }
        switch interaction {
        case let .moving(anchor, original):
            bounds = clamped(
                Rect(
                    x: original.x + point.x - anchor.x, y: original.y + point.y - anchor.y,
                    width: original.width, height: original.height))
        case let .resizing(anchor, original):
            bounds = resized(original, byColumns: point.x - anchor.x, rows: point.y - anchor.y)
        }
        normalBounds = bounds
    }

    private func clamped(_ candidate: Rect) -> Rect {
        let width = min(viewport.width, max(minimumWidth, candidate.width))
        let height = min(viewport.height, max(minimumHeight, candidate.height))
        return Rect(
            x: min(max(viewport.x, candidate.x), viewport.maxX - width),
            y: min(max(viewport.y, candidate.y), viewport.maxY - height),
            width: width, height: height)
    }

    private func resized(_ original: Rect, byColumns columns: Int, rows: Int) -> Rect {
        let width = min(max(minimumWidth, original.width + columns), viewport.maxX - original.x)
        let height = min(max(minimumHeight, original.height + rows), viewport.maxY - original.y)
        return Rect(x: original.x, y: original.y, width: width, height: height)
    }
}
