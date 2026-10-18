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
    case custom(BorderSymbols)

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
        case .custom(let symbols):
            return (
                symbols.horizontal, symbols.vertical, symbols.topLeft, symbols.topRight,
                symbols.bottomLeft, symbols.bottomRight
            )
        }
    }
}

/// Horizontal placement of a panel title inside its top border.
public enum PanelTitleAlignment: Sendable {
    case left
    case center
    case right
}

/// The border row receiving a rich panel title.
public enum PanelTitlePosition: Sendable {
    case top
    case bottom
}

/// Styled spans placed on a panel border.
///
/// Earlier titles own colliding cells.
public struct PanelTitle: Sendable {
    public var spans: [TextSpan]
    public var alignment: PanelTitleAlignment
    public var position: PanelTitlePosition

    public init(
        _ spans: [TextSpan], alignment: PanelTitleAlignment = .left,
        position: PanelTitlePosition = .top
    ) {
        self.spans = spans
        self.alignment = alignment
        self.position = position
    }
}

/// Draws selectable borders and an optional title around an inner content area.
public struct Panel: Widget, Sendable {
    public var style: Style
    public var borders: BorderEdges
    public var borderType: BorderType
    public var title: String?
    public var titleAlignment: PanelTitleAlignment
    public var padding: PanelPadding
    public var titles: [PanelTitle]
    public var borderStyle: Style?
    public var titleStyle: Style?
    public var shadow: PanelShadow?
    /// Opts titles into borderless edge rows, reserving those rows in `inner(_:)`.
    ///
    /// False preserves the requirement that a title's edge have a border.
    public var titlesWithoutBorders: Bool

    public init(
        style: Style = Style(), borders: BorderEdges = .all, borderType: BorderType = .single,
        title: String? = nil, titleAlignment: PanelTitleAlignment = .left,
        padding: PanelPadding = PanelPadding(), titles: [PanelTitle] = [],
        borderStyle: Style? = nil, titleStyle: Style? = nil, shadow: PanelShadow? = nil,
        titlesWithoutBorders: Bool = false
    ) {
        self.style = style
        self.borders = borders
        self.borderType = borderType
        self.title = title
        self.titleAlignment = titleAlignment
        self.padding = padding
        self.titles = titles
        self.borderStyle = borderStyle
        self.titleStyle = titleStyle
        self.shadow = shadow
        self.titlesWithoutBorders = titlesWithoutBorders
    }

    /// Returns content geometry after border and padding cells have been removed.
    public func inner(_ area: Rect) -> Rect {
        let left = (borders.contains(.left) ? 1 : 0) + max(0, padding.left)
        let right = (borders.contains(.right) ? 1 : 0) + max(0, padding.right)
        let top = (reservesTitleRow(.top) ? 1 : 0) + max(0, padding.top)
        let bottom = (reservesTitleRow(.bottom) ? 1 : 0) + max(0, padding.bottom)
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
            if titlesWithoutBorders && area.width > 0 && area.height > 0 {
                buffer.withClip(area) { target in
                    renderTitle(in: area, buffer: &target)
                    renderRichTitles(in: area, buffer: &target)
                }
            }
            return
        }

        renderShadow(in: area, buffer: &buffer)
        buffer.withClip(area) { target in
            let glyphs = borderType.glyphs
            if borders.contains(.top) {
                drawRow(glyphs.horizontal, y: area.y, in: area, buffer: &target)
            }
            if borders.contains(.bottom) {
                drawRow(glyphs.horizontal, y: area.maxY - 1, in: area, buffer: &target)
            }
            if borders.contains(.left) {
                drawColumn(glyphs.vertical, x: area.x, in: area, buffer: &target)
            }
            if borders.contains(.right) {
                drawColumn(glyphs.vertical, x: area.maxX - 1, in: area, buffer: &target)
            }
            for (first, second, symbol, point) in [
                (BorderEdges.top, BorderEdges.left, glyphs.topLeft, Point(x: area.x, y: area.y)),
                (BorderEdges.top, BorderEdges.right, glyphs.topRight, Point(x: area.maxX - 1, y: area.y)),
                (BorderEdges.bottom, BorderEdges.left, glyphs.bottomLeft, Point(x: area.x, y: area.maxY - 1)),
                (BorderEdges.bottom, BorderEdges.right, glyphs.bottomRight, Point(x: area.maxX - 1, y: area.maxY - 1)),
            ] where borders.contains(first) && borders.contains(second) {
                target.put(symbol, width: 1, at: point, style: borderStyle ?? style)
            }
            renderTitle(in: area, buffer: &target)
            renderRichTitles(in: area, buffer: &target)
        }
    }

    func renderShadow(in area: Rect, buffer: inout Buffer) {
        guard let shadow, area.width > 0, area.height > 0 else { return }
        let original = representableBorderArea(area)
        let (x, xOverflow) = original.x.addingReportingOverflow(shadow.offsetX)
        let (y, yOverflow) = original.y.addingReportingOverflow(shadow.offsetY)
        // With nonnegative buffer coordinates, an overflowing translation cannot be visible.
        guard !xOverflow, !yOverflow else { return }
        let translated = representableBorderArea(
            Rect(x: x, y: y, width: original.width, height: original.height))
        let visible = buffer.area
        let left = max(visible.x, translated.x)
        let right = min(visible.maxX, translated.maxX)
        let top = max(visible.y, translated.y)
        let bottom = min(visible.maxY, translated.maxY)
        guard left < right, top < bottom else { return }
        for y in top..<bottom {
            for x in left..<right where !original.contains(Point(x: x, y: y)) {
                buffer.put(shadow.glyph, width: 1, at: Point(x: x, y: y), style: shadow.style)
            }
        }
    }

    private func drawRow(_ symbol: String, y: Int, in area: Rect, buffer: inout Buffer) {
        let start = area.x + (borders.contains(.left) ? 1 : 0)
        let end = area.maxX - (borders.contains(.right) ? 1 : 0)
        for x in start..<end {
            buffer.put(symbol, width: 1, at: Point(x: x, y: y), style: borderStyle ?? style)
        }
    }

    private func drawColumn(_ symbol: String, x: Int, in area: Rect, buffer: inout Buffer) {
        let start = area.y + (borders.contains(.top) ? 1 : 0)
        let end = area.maxY - (borders.contains(.bottom) ? 1 : 0)
        for y in start..<end {
            buffer.put(symbol, width: 1, at: Point(x: x, y: y), style: borderStyle ?? style)
        }
    }

    func renderTitle(in area: Rect, buffer: inout Buffer) {
        guard borders.contains(.top) || titlesWithoutBorders, let title, !title.isEmpty else {
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
            style: titleStyle ?? style, buffer: &buffer
        )
    }
    func renderRichTitles(in area: Rect, buffer: inout Buffer) {
        let start = area.x + (borders.contains(.left) ? 1 : 0)
        let end = area.maxX - (borders.contains(.right) ? 1 : 0)
        let available = end - start
        guard available > 0 else { return }
        var occupied: [Int: Set<Int>] = [:]
        // The legacy title retains its original geometry and takes precedence.
        if let title, !title.isEmpty, borders.contains(.top) || titlesWithoutBorders {
            let first = String(title.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
            let layout = TextLayout(" " + first + " ", width: available)
            let width = layout.lines[0].glyphs.last.map { $0.column + $0.width } ?? 0
            let offset =
                titleAlignment == .left ? 0 : titleAlignment == .right ? available - width : (available - width) / 2
            occupied[area.y] = Set((start + offset)..<(start + offset + width))
        }
        for title in titles {
            let edge: BorderEdges = title.position == .top ? .top : .bottom
            guard borders.contains(edge) || titlesWithoutBorders else { continue }
            let y = title.position == .top ? area.y : area.maxY - 1
            let layout = TextLayout([TextSpan(" ")] + title.spans + [TextSpan(" ")], width: available)
            let glyphs = layout.lines[0].glyphs
            let width = glyphs.last.map { $0.column + $0.width } ?? 0
            let offset =
                title.alignment == .left ? 0 : title.alignment == .right ? available - width : (available - width) / 2
            for glyph in glyphs {
                let x = start + offset + glyph.column
                let columns = x..<(x + glyph.width)
                guard !columns.contains(where: { occupied[y, default: []].contains($0) }) else { continue }
                buffer.put(
                    glyph.text, width: glyph.width, at: Point(x: x, y: y),
                    style: (glyph.style ?? titleStyle ?? style).applying(glyph.patch ?? StylePatch()), link: glyph.link)
                occupied[y, default: []].formUnion(columns)
            }
        }
    }

    private func reservesTitleRow(_ position: PanelTitlePosition) -> Bool {
        let edge: BorderEdges = position == .top ? .top : .bottom
        if borders.contains(edge) { return true }
        guard titlesWithoutBorders else { return false }
        if position == .top, let title, !title.isEmpty { return true }
        return titles.contains { $0.position == position }
    }
}
