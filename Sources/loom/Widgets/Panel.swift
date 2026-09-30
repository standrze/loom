import weft

/// Terminal-cell padding inside a panel's borders.
public struct PanelPadding: Equatable, Sendable {
    public var left: Int
    public var right: Int
    public var top: Int
    public var bottom: Int

    public init(left: Int = 0, right: Int = 0, top: Int = 0, bottom: Int = 0) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public init(all amount: Int) {
        self.init(left: amount, right: amount, top: amount, bottom: amount)
    }
}

/// The sides of a panel that receive a border.
public struct BorderEdges: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let top = BorderEdges(rawValue: 1 << 0)
    public static let right = BorderEdges(rawValue: 1 << 1)
    public static let bottom = BorderEdges(rawValue: 1 << 2)
    public static let left = BorderEdges(rawValue: 1 << 3)
    public static let all: BorderEdges = [.top, .right, .bottom, .left]
}

/// The line characters used by a panel.
public enum BorderType: Sendable {
    case single
    case rounded
    case double

    var glyphs:
        (
            horizontal: String, vertical: String, topLeft: String, topRight: String,
            bottomLeft: String, bottomRight: String
        )
    {
        switch self {
        case .single:
            return ("─", "│", "┌", "┐", "└", "┘")
        case .rounded:
            return ("─", "│", "╭", "╮", "╰", "╯")
        case .double:
            return ("═", "║", "╔", "╗", "╚", "╝")
        }
    }
}

/// Horizontal placement of a panel title inside its top border.
public enum PanelTitleAlignment: Sendable {
    case left
    case center
    case right
}

/// Draws selectable borders and an optional title around an inner content area.
public struct Panel: Widget {
    public var style: Style
    public var borders: BorderEdges
    public var borderType: BorderType
    public var title: String?
    public var titleAlignment: PanelTitleAlignment
    public var padding: PanelPadding

    public init(
        style: Style = Style(), borders: BorderEdges = .all, borderType: BorderType = .single,
        title: String? = nil, titleAlignment: PanelTitleAlignment = .left,
        padding: PanelPadding = PanelPadding()
    ) {
        self.style = style
        self.borders = borders
        self.borderType = borderType
        self.title = title
        self.titleAlignment = titleAlignment
        self.padding = padding
    }

    /// Returns content geometry after border and padding cells have been removed.
    public func inner(_ area: Rect) -> Rect {
        let left = (borders.contains(.left) ? 1 : 0) + max(0, padding.left)
        let right = (borders.contains(.right) ? 1 : 0) + max(0, padding.right)
        let top = (borders.contains(.top) ? 1 : 0) + max(0, padding.top)
        let bottom = (borders.contains(.bottom) ? 1 : 0) + max(0, padding.bottom)
        let xOffset = min(area.width, left)
        let yOffset = min(area.height, top)
        return Rect(
            x: area.x + xOffset,
            y: area.y + yOffset,
            width: max(0, area.width - left - right),
            height: max(0, area.height - top - bottom)
        )
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        guard area.width >= 2, area.height >= 2 else {
            return
        }

        let glyphs = borderType.glyphs
        if borders.contains(.top) {
            drawRow(glyphs.horizontal, y: area.y, in: area, buffer: &buffer)
        }
        if borders.contains(.bottom) {
            drawRow(glyphs.horizontal, y: area.maxY - 1, in: area, buffer: &buffer)
        }
        if borders.contains(.left) {
            drawColumn(glyphs.vertical, x: area.x, in: area, buffer: &buffer)
        }
        if borders.contains(.right) {
            drawColumn(glyphs.vertical, x: area.maxX - 1, in: area, buffer: &buffer)
        }
        for (first, second, symbol, point) in [
            (BorderEdges.top, BorderEdges.left, glyphs.topLeft, Point(x: area.x, y: area.y)),
            (BorderEdges.top, BorderEdges.right, glyphs.topRight, Point(x: area.maxX - 1, y: area.y)),
            (BorderEdges.bottom, BorderEdges.left, glyphs.bottomLeft, Point(x: area.x, y: area.maxY - 1)),
            (BorderEdges.bottom, BorderEdges.right, glyphs.bottomRight, Point(x: area.maxX - 1, y: area.maxY - 1)),
        ] where borders.contains(first) && borders.contains(second) {
            buffer.put(symbol, width: 1, at: point, style: style)
        }
        renderTitle(in: area, buffer: &buffer)
    }

    private func drawRow(_ symbol: String, y: Int, in area: Rect, buffer: inout Buffer) {
        let start = area.x + (borders.contains(.left) ? 1 : 0)
        let end = area.maxX - (borders.contains(.right) ? 1 : 0)
        for x in start..<end {
            buffer.put(symbol, width: 1, at: Point(x: x, y: y), style: style)
        }
    }

    private func drawColumn(_ symbol: String, x: Int, in area: Rect, buffer: inout Buffer) {
        let start = area.y + (borders.contains(.top) ? 1 : 0)
        let end = area.maxY - (borders.contains(.bottom) ? 1 : 0)
        for y in start..<end {
            buffer.put(symbol, width: 1, at: Point(x: x, y: y), style: style)
        }
    }

    private func renderTitle(in area: Rect, buffer: inout Buffer) {
        guard borders.contains(.top), let title, !title.isEmpty else {
            return
        }
        let start = area.x + (borders.contains(.left) ? 1 : 0)
        let end = area.maxX - (borders.contains(.right) ? 1 : 0)
        let available = end - start
        guard available > 0 else {
            return
        }
        let firstLine = String(title.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
        let layout = TextLayout(" " + firstLine + " ", width: available)
        let titleWidth = min(available, layout.lines[0].glyphs.last.map { $0.column + $0.width } ?? 0)
        let offset: Int
        switch titleAlignment {
        case .left:
            offset = 0
        case .center:
            offset = (available - titleWidth) / 2
        case .right:
            offset = available - titleWidth
        }
        layout.paint(
            in: Rect(x: start + offset, y: area.y, width: titleWidth, height: 1),
            style: style, buffer: &buffer
        )
    }
}
