import weft

/// One choice in a popup list.
///
/// Application-specific values and actions stay with the caller.
public struct PopupMenuItem: Sendable {
    public var label: String
    public var detail: String

    public init(_ label: String, detail: String = "") {
        self.label = label
        self.detail = detail
    }
}

/// An opaque, scrollable list with aligned labels, details, and horizontal separators.
///
/// Render after the content it overlays. The caller owns selection and placement;
/// rendering and hit testing use the same visible range. Colors inherit the terminal.
public struct PopupMenu: Widget {
    public var items: [PopupMenuItem]
    /// Pointer highlight, independent of keyboard selection and scrolling.
    public var hoveredIndex: Int?
    public var hoverStyle = Style(underlined: true)
    public var selectedIndex: Int
    public var style = Style()
    public var detailStyle = Style(foreground: .indexed(8))
    public var selectionStyle = Style(reversed: true)
    public var separatorStyle = Style(foreground: .indexed(8))
    /// A title set into a full border.
    ///
    /// Titled menus use two-column content insets.
    public var title: String?
    /// A single supporting row above the choices when the menu has enough room.
    public var introduction: String?
    /// A centered keyboard hint below the choices when the menu has enough room.
    public var footer: String?
    public var showsCloseButton = false
    public var rightAlignsDetails = false
    /// Adds square side borders to the existing top and bottom rules.
    public var fullBorder = false
    /// Displays the keyboard selection chevron and reserves its two columns.
    public var showsSelectionMarker = true
    /// Displays the number of items on the top border.
    public var showsItemCount = true
    public var emptyMessage = "No matches"

    public init(_ items: [PopupMenuItem], selectedIndex: Int = 0) {
        self.items = items
        self.selectedIndex = selectedIndex
    }

    /// Preferred height including the border, optional supporting rows, and at least one choice row.
    public func height(maximumRows: Int = 8) -> Int {
        min(max(1, maximumRows), max(1, items.count)) + 2
            + (title != nil && introduction != nil ? 3 : 0)
            + (title != nil && footer != nil ? 2 : 0)
    }

    /// Item indices visible at this size, keeping the selected row near the middle.
    public func visibleRange(in area: Rect) -> Range<Int> {
        let count = min(items.count, contentArea(in: area).height)
        guard count > 0 else { return 0..<0 }
        let selected = min(max(0, selectedIndex), items.count - 1)
        let start = min(max(0, selected - count / 2), items.count - count)
        return start..<(start + count)
    }

    /// Returns the item under a content cell, excluding separators and the scrollbar.
    public func item(at point: Point, in area: Rect) -> Int? {
        let content = contentArea(in: area)
        guard content.contains(point) else { return nil }
        let range = visibleRange(in: area)
        let index = range.lowerBound + point.y - content.y
        return range.contains(index) ? index : nil
    }

    /// The title-bar close control, excluding its surrounding padding and border.
    public func closeButtonArea(in area: Rect) -> Rect? {
        guard title != nil, showsCloseButton, area.width >= 8, area.height >= 3 else { return nil }
        return Rect(x: area.maxX - 5, y: area.y, width: 3, height: 1)
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        // Clear underlying content even when the list is empty or the window is tiny.
        for y in min(buffer.height, max(0, area.y))..<max(0, min(area.maxY, buffer.height)) {
            for x in min(buffer.width, max(0, area.x))..<max(0, min(area.maxX, buffer.width)) {
                buffer.put(" ", width: 1, at: Point(x: x, y: y), style: style)
            }
        }
        guard area.width > 0, area.height >= 3 else { return }
        let bordered = fullBorder || title != nil
        let panel = Panel(style: separatorStyle, borders: bordered ? .all : [.top, .bottom])
        panel.render(in: area, buffer: &buffer)
        let counter = " \(items.count) "
        if title == nil, showsItemCount, counter.count < area.width - (bordered ? 2 : 0) {
            paint(
                counter,
                in: Rect(
                    x: area.maxX - counter.count - (bordered ? 1 : 0), y: area.y, width: counter.count, height: 1),
                style: separatorStyle, buffer: &buffer)
        }
        renderChrome(in: area, buffer: &buffer)
        let content = contentArea(in: area)
        guard content.width > 0 else { return }
        let range = visibleRange(in: area)
        if items.isEmpty {
            paint(
                emptyMessage, in: Rect(x: content.x, y: content.y, width: content.width, height: 1),
                style: detailStyle, buffer: &buffer)
            return
        }
        let markerWidth = showsSelectionMarker ? 2 : 0
        let labelBudget = min(40, max(1, (content.width - markerWidth) * 3 / 5))
        let labelWidth = min(labelBudget, items.map { displayWidth($0.label, limit: labelBudget) }.max() ?? 0)
        for (row, index) in range.enumerated() {
            let y = content.y + row
            let selected = index == min(max(0, selectedIndex), items.count - 1)
            let hovered = hoveredIndex == index && !selected
            let rowStyle = selected ? selectionStyle : (hovered ? hoverStyle : style)
            for x in content.x..<content.maxX {
                buffer.put(" ", width: 1, at: Point(x: x, y: y), style: rowStyle)
            }
            if showsSelectionMarker {
                paint(
                    selected ? "❯ " : "  ",
                    in: Rect(x: content.x, y: y, width: min(2, content.width), height: 1),
                    style: rowStyle, buffer: &buffer)
            }
            let textWidth = max(0, content.width - markerWidth)
            let hasDetail = textWidth >= labelWidth + 8
            let nameWidth = hasDetail ? labelWidth : textWidth
            var labelStyle = rowStyle
            labelStyle.bold = selected
            paint(
                items[index].label, in: Rect(x: content.x + markerWidth, y: y, width: nameWidth, height: 1),
                style: labelStyle, buffer: &buffer)
            if hasDetail {
                var rowDetailStyle = selected ? selectionStyle : (hovered ? hoverStyle : detailStyle)
                let detailWidth = textWidth - nameWidth - 2
                let paintedWidth =
                    rightAlignsDetails ? displayWidth(items[index].detail, limit: detailWidth) : detailWidth
                if rightAlignsDetails {
                    rowDetailStyle.foreground = detailStyle.foreground
                }
                paint(
                    items[index].detail,
                    in: Rect(
                        x: content.maxX - paintedWidth, y: y, width: paintedWidth, height: 1),
                    style: rowDetailStyle, buffer: &buffer)
            }
        }
        if items.count > content.height && content.height > 0 && area.width >= 4 {
            let thumbHeight = max(1, content.height * content.height / items.count)
            let travel = content.height - thumbHeight
            let offset = range.lowerBound * travel / max(1, items.count - content.height)
            for row in 0..<content.height {
                let symbol = (offset..<(offset + thumbHeight)).contains(row) ? "█" : "│"
                buffer.put(
                    symbol, width: 1, at: Point(x: area.maxX - (bordered ? 2 : 1), y: content.y + row),
                    style: separatorStyle)
            }
        }
    }

    private func contentArea(in area: Rect) -> Rect {
        let footerRows = footerArea(in: area) == nil ? 0 : 2
        let introductionRows = introductionArea(in: area) == nil ? 0 : 3
        let height = max(0, area.height - 2 - introductionRows - footerRows)
        let scrollbar = items.count > height ? 1 : 0
        let inset = title == nil ? 1 : 2
        return Rect(
            x: area.x + inset, y: area.y + 1 + introductionRows,
            width: max(0, area.width - inset * 2 - scrollbar), height: height)
    }

    private func footerArea(in area: Rect) -> Rect? {
        guard title != nil, footer != nil, area.width >= 5, area.height >= 5 else { return nil }
        return Rect(x: area.x + 2, y: area.maxY - 2, width: area.width - 4, height: 1)
    }

    private func introductionArea(in area: Rect) -> Rect? {
        let footerRows = footerArea(in: area) == nil ? 0 : 2
        guard title != nil, introduction != nil, area.width >= 5, area.height - footerRows >= 6 else { return nil }
        return Rect(x: area.x + 2, y: area.y + 2, width: area.width - 4, height: 1)
    }

    private func renderChrome(in area: Rect, buffer: inout Buffer) {
        guard let title else { return }
        let closeArea = closeButtonArea(in: area)
        var titleStyle = style
        titleStyle.bold = true
        paint(
            " " + title + " ",
            in: Rect(
                x: area.x + 1, y: area.y,
                width: max(0, (closeArea?.x ?? (area.maxX - 1)) - area.x - 2), height: 1),
            style: titleStyle, buffer: &buffer)
        if let closeArea {
            paint("[x]", in: closeArea, style: detailStyle, buffer: &buffer)
        }
        if let introduction, let introductionArea = introductionArea(in: area) {
            paint(introduction, in: introductionArea, style: detailStyle, buffer: &buffer)
        }
        if let footer, let footerArea = footerArea(in: area) {
            let width = displayWidth(footer, limit: footerArea.width)
            paint(
                footer,
                in: Rect(
                    x: footerArea.x + (footerArea.width - width) / 2, y: footerArea.y, width: width, height: 1),
                style: detailStyle, buffer: &buffer)
        }
    }

    private func displayWidth(_ text: String, limit: Int) -> Int {
        let layout = TextLayout(text, width: max(1, limit))
        return layout.lines[0].glyphs.last.map { $0.column + $0.width } ?? 0
    }

    private func paint(_ text: String, in area: Rect, style: Style, buffer: inout Buffer) {
        guard area.width > 0 else { return }
        Paragraph(TextLayout(text, width: area.width), style: style).render(in: area, buffer: &buffer)
    }
}
