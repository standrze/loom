import weft

/// A desktop icon and the application-defined target it opens.
///
/// IDs must be unique within a desktop. Loom renders the icon and returns its
/// launch target; the application owns the target's content and lifetime.
public struct DesktopIcon: Equatable, Sendable {
    public let id: String
    public let label: String
    public let symbol: String
    public let launchTarget: String

    public init(id: String, label: String, symbol: String, launchTarget: String) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.launchTarget = launchTarget
    }
}

/// A responsive grid of terminal-cell icons for a separate desktop screen.
///
/// The desktop owns icon selection and hover state. Its caller owns the screen
/// background, launch actions, and any windows opened from the icons.
public struct Desktop: Widget {
    public private(set) var viewport: Rect
    public private(set) var icons: [DesktopIcon]
    public private(set) var selectedIconID: String?
    public private(set) var hoveredIconID: String?
    public var style = Style()
    public var selectionStyle = Style(reversed: true)
    public var hoverStyle = Style(underlined: true)

    private var firstVisibleRow = 0

    public init(viewport: Rect, icons: [DesktopIcon]) {
        self.viewport = viewport
        self.icons = icons
    }

    /// Updates the terminal-cell viewport and keeps a selected icon visible.
    public mutating func resizeViewport(to viewport: Rect) {
        self.viewport = viewport
        hoveredIconID = nil
        revealSelection()
    }

    /// Replaces the icons, dropping selection and hover for removed IDs.
    public mutating func setIcons(_ icons: [DesktopIcon]) {
        self.icons = icons
        if let selectedIconID, !icons.contains(where: { $0.id == selectedIconID }) {
            self.selectedIconID = nil
        }
        if let hoveredIconID, !icons.contains(where: { $0.id == hoveredIconID }) {
            self.hoveredIconID = nil
        }
        revealSelection()
    }

    /// Returns the visible terminal-cell rectangle of an icon.
    public func iconArea(for id: String) -> Rect? {
        guard let index = icons.firstIndex(where: { $0.id == id }) else { return nil }
        return iconArea(at: index)
    }

    /// Returns the icon under a terminal-cell point, if any.
    public func icon(at point: Point) -> DesktopIcon? {
        icons.indices.first(where: { iconArea(at: $0)?.contains(point) == true }).map { icons[$0] }
    }

    /// Moves keyboard selection through icons in reading order, wrapping at the ends.
    public mutating func moveSelection(by steps: Int) {
        guard !icons.isEmpty, steps != 0 else { return }
        if let selectedIconID, let current = icons.firstIndex(where: { $0.id == selectedIconID }) {
            let count = icons.count
            self.selectedIconID = icons[(current + steps % count + count) % count].id
        } else {
            selectedIconID = steps < 0 ? icons.last?.id : icons.first?.id
        }
        revealSelection()
    }

    /// Returns the launch target of the keyboard-selected icon.
    public func activateSelected() -> String? {
        icons.first(where: { $0.id == selectedIconID })?.launchTarget
    }

    /// Clears keyboard or mouse selection.
    public mutating func clearSelection() {
        selectedIconID = nil
    }

    /// Clears pointer hover, for example when the pointer leaves the desktop.
    public mutating func clearHover() {
        hoveredIconID = nil
    }

    /// Selects and launches an icon on mouse-down; pointer motion updates hover.
    ///
    /// A mouse-down on empty desktop space clears selection. Other events do not
    /// launch an icon. The returned target is interpreted by the application.
    @discardableResult
    public mutating func handleMouse(_ mouse: MouseEvent) -> String? {
        switch mouse.kind {
        case .move, .drag:
            hoveredIconID = icon(at: mouse.position)?.id
        case .down:
            let hit = icon(at: mouse.position)
            selectedIconID = hit?.id
            hoveredIconID = hit?.id
            return hit?.launchTarget
        case .wheelUp:
            scroll(byRows: -1)
        case .wheelDown:
            scroll(byRows: 1)
        case .up:
            break
        }
        return nil
    }

    /// Renders icons using the same geometry as hit testing.
    ///
    /// Pass `viewport` as `area` so rendering and input refer to the same cells.
    public func render(in area: Rect, buffer: inout Buffer) {
        for (index, icon) in icons.enumerated() {
            guard let iconArea = iconArea(at: index), area.contains(Point(x: iconArea.x, y: iconArea.y)) else {
                continue
            }
            let iconStyle: Style
            if icon.id == selectedIconID {
                iconStyle = selectionStyle
            } else if icon.id == hoveredIconID {
                iconStyle = hoverStyle
            } else {
                iconStyle = style
            }
            for y in iconArea.y..<iconArea.maxY {
                for x in iconArea.x..<iconArea.maxX {
                    buffer.put(" ", width: 1, at: Point(x: x, y: y), style: iconStyle)
                }
            }
            if iconArea.height > 1 {
                paintCentered(icon.symbol, y: iconArea.y, in: iconArea, style: iconStyle, buffer: &buffer)
            }
            let labelY = iconArea.height >= 3 ? iconArea.y + 2 : iconArea.maxY - 1
            paintCentered(icon.label, y: labelY, in: iconArea, style: iconStyle, buffer: &buffer)
        }
    }

    private var layout: (width: Int, columns: Int, rows: Int, left: Int, top: Int) {
        let left = min(2, max(0, (viewport.width - 1) / 2))
        let top = viewport.height >= 6 ? 1 : 0
        let availableWidth = max(0, viewport.width - 2 * left)
        let width = min(16, availableWidth)
        let columns = width == 0 ? 0 : max(1, (availableWidth + 3) / (width + 3))
        let availableHeight = max(0, viewport.height - top)
        let rows = availableHeight == 0 ? 0 : max(1, (availableHeight + 1) / 5)
        return (width, columns, rows, left, top)
    }

    private func iconArea(at index: Int) -> Rect? {
        let layout = layout
        guard layout.columns > 0, layout.rows > 0 else { return nil }
        let row = index / layout.columns - firstVisibleRow
        guard row >= 0, row < layout.rows else { return nil }
        let column = index % layout.columns
        let x = viewport.x + layout.left + column * (layout.width + 3)
        let y = viewport.y + layout.top + row * 5
        return Rect(x: x, y: y, width: layout.width, height: min(4, viewport.maxY - y))
    }

    private mutating func revealSelection() {
        let layout = layout
        guard layout.columns > 0, layout.rows > 0 else {
            firstVisibleRow = 0
            return
        }
        let totalRows = (icons.count + layout.columns - 1) / layout.columns
        firstVisibleRow = min(firstVisibleRow, max(0, totalRows - layout.rows))
        guard let selectedIconID, let index = icons.firstIndex(where: { $0.id == selectedIconID }) else { return }
        let selectedRow = index / layout.columns
        if selectedRow < firstVisibleRow {
            firstVisibleRow = selectedRow
        } else if selectedRow >= firstVisibleRow + layout.rows {
            firstVisibleRow = selectedRow - layout.rows + 1
        }
    }

    private mutating func scroll(byRows rows: Int) {
        let layout = layout
        guard layout.columns > 0, layout.rows > 0 else { return }
        let totalRows = (icons.count + layout.columns - 1) / layout.columns
        firstVisibleRow = min(max(0, firstVisibleRow + rows), max(0, totalRows - layout.rows))
        hoveredIconID = nil
    }

    private func paintCentered(_ text: String, y: Int, in area: Rect, style: Style, buffer: inout Buffer) {
        guard area.width > 0 else { return }
        let textLayout = TextLayout(text, width: area.width)
        let width = min(area.width, textLayout.lines[0].glyphs.last.map { $0.column + $0.width } ?? 0)
        Paragraph(textLayout, style: style).render(
            in: Rect(x: area.x + (area.width - width) / 2, y: y, width: width, height: 1),
            buffer: &buffer)
    }
}
