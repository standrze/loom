/// A styled table cell.
///
/// Text wraps within its column and clips to its row's explicit height.
public struct TableCell: Sendable {
    public var spans: [TextSpan]
    public var alignment: CellAlignment?

    public init(_ text: String, style: Style? = nil, alignment: CellAlignment? = nil) {
        self.init(spans: [TextSpan(text, style: style)], alignment: alignment)
    }

    public init(spans: [TextSpan], alignment: CellAlignment? = nil) {
        self.spans = spans
        self.alignment = alignment
    }
}

/// A table column, sized by the same constraints used by `Layout`.
public struct TableColumn: Sendable {
    public var title: TableCell
    public var width: Constraint
    public var alignment: CellAlignment

    public init(_ title: String, width: Constraint = .fill(1), alignment: CellAlignment = .left) {
        self.title = TableCell(title)
        self.width = width
        self.alignment = alignment
    }
}

/// A stable table row.
///
/// Missing cells are blank; cells beyond the column count are ignored.
public struct TableRow<ID: Hashable>: Identifiable {
    public var id: ID
    public var cells: [TableCell]
    public var height: Int
    public var style: Style

    public init(id: ID, cells: [TableCell], height: Int = 1, style: Style = Style()) {
        self.id = id
        self.cells = cells
        self.height = height
        self.style = style
    }
}

/// Row/mark selection, optional cell selection, and two-axis scrolling owned by the caller.
public struct TableState<ID: Hashable> {
    public var rows: SelectionState<ID>
    public var horizontal = ScrollState()
    public private(set) var selectedColumn: Int?
    private var columns: [Range<Int>] = []

    public init(selectedID: ID? = nil, selectedColumn: Int? = nil) {
        rows = SelectionState(selectedID: selectedID)
        self.selectedColumn = selectedColumn
    }

    public mutating func selectColumn(_ column: Int?) {
        guard let column else {
            selectedColumn = nil
            return
        }
        guard columns.indices.contains(column) else { return }
        selectedColumn = column
        horizontal.reveal(columns[column])
    }

    public mutating func selectCell(row: ID, column: Int) {
        rows.select(row)
        selectColumn(column)
    }

    public mutating func moveColumn(by distance: Int) {
        guard !columns.isEmpty else { return }
        guard let selectedColumn else {
            selectColumn(distance < 0 ? columns.count - 1 : 0)
            return
        }
        let delta = distance >= 0 ? min(distance, columns.count - 1 - selectedColumn) : max(distance, -selectedColumn)
        selectColumn(selectedColumn + delta)
    }

    /// Up/down navigate rows; left/right navigate an active cell selection or scroll horizontally.
    @discardableResult
    public mutating func handle(_ event: InputEvent, allowsMultipleSelection: Bool = false) -> Bool {
        if rows.handle(event, allowsMultipleSelection: allowsMultipleSelection) { return true }
        if KeyChord(.left).matches(event) {
            if selectedColumn != nil { moveColumn(by: -1) } else { horizontal.scroll(by: -1) }
        } else if KeyChord(.right).matches(event) {
            if selectedColumn != nil { moveColumn(by: 1) } else { horizontal.scroll(by: 1) }
        } else {
            return false
        }
        return true
    }

    fileprivate mutating func updateColumns(_ columns: [Range<Int>], width: Int, viewport: Int) {
        let changed = self.columns != columns || horizontal.viewportLength != viewport
        self.columns = columns
        horizontal.update(contentLength: width, viewportLength: viewport)
        if let selectedColumn {
            self.selectedColumn = columns.isEmpty ? nil : min(max(0, selectedColumn), columns.count - 1)
        }
        if changed, let selectedColumn { horizontal.reveal(columns[selectedColumn]) }
    }
}

/// A selectable table with fixed headers/footers and clipped, independently scrollable body rows.
///
/// Sorting/filtering and cell actions belong to the caller. Set `minimumWidth` to allow
/// horizontal scrolling instead of squeezing columns into a narrow viewport.
public struct Table<ID: Hashable>: StatefulWidget {
    public var columns: [TableColumn]
    public var rows: [TableRow<ID>]
    public var columnSpacing = 1
    public var minimumWidth = 0
    public var showsHeader = true
    public var headerHeight = 1
    public var footer: [TableCell]?
    public var footerHeight = 1
    public var style = Style()
    public var headerStyle = Style(bold: true)
    public var footerStyle = Style(bold: true)
    public var selectionStyle = Style(reversed: true)
    public var markedStyle = Style(bold: true)
    public var cellSelectionStyle = Style(underlined: true)
    public var emptyMessage = "No rows"

    public init(columns: [TableColumn], rows: [TableRow<ID>]) {
        self.columns = columns
        self.rows = rows
    }

    public func bodyArea(in area: Rect) -> Rect {
        let top = showsHeader ? min(max(0, area.height), max(0, headerHeight)) : 0
        let bottom = footer == nil ? 0 : min(max(0, area.height - top), max(0, footerHeight))
        return Rect(x: area.x, y: area.y + top, width: area.width, height: max(0, area.height - top - bottom))
    }

    /// Column regions in logical content coordinates, before horizontal scrolling.
    public func columnAreas(width: Int) -> [Rect] {
        let width = max(0, max(width, minimumWidth))
        let gaps = max(0, columns.count - 1)
        let spacing = gaps > 0 ? min(max(0, columnSpacing), width / gaps) : 0
        let regions = Layout(.horizontal, columns.map(\.width))
            .split(Rect(width: width - gaps * spacing, height: 1))
        return regions.enumerated().map { index, region in
            Rect(x: region.x + index * spacing, width: region.width, height: 1)
        }
    }

    /// Synchronizes data and geometry before dispatching events.
    ///
    /// Drawing also calls this method.
    public func update(in area: Rect, state: inout TableState<ID>) {
        let body = bodyArea(in: area)
        state.rows.update(ids: rows.map(\.id), heights: rows.map(\.height), viewportLength: body.height)
        let columns = columnAreas(width: area.width)
        state.updateColumns(
            columns.map { $0.x..<$0.maxX }, width: max(0, max(area.width, minimumWidth)),
            viewport: max(0, area.width))
    }

    public func render(in area: Rect, buffer: inout Buffer, state: inout TableState<ID>) {
        update(in: area, state: &state)
        guard area.width > 0, area.height > 0 else { return }
        let body = bodyArea(in: area)
        let regions = columnAreas(width: area.width)
        buffer.withClip(area) { buffer in
            fillCollectionArea(area, style: style, buffer: &buffer)
            if showsHeader {
                paintRow(
                    columns.map(\.title), regions: regions,
                    in: Rect(x: area.x, y: area.y, width: area.width, height: body.y - area.y),
                    offset: state.horizontal.offset, base: collectionStyle(style, overlay: headerStyle),
                    buffer: &buffer)
            }
            buffer.withClip(body) { buffer in
                if rows.isEmpty {
                    paintCollectionText([TextSpan(emptyMessage)], in: body, style: style, buffer: &buffer)
                }
                for index in state.rows.visibleIndices {
                    let row = rows[index]
                    let range = state.rows.rowRange(at: index)
                    let rowArea = Rect(
                        x: body.x, y: body.y + range.lowerBound - state.rows.scroll.offset,
                        width: body.width, height: range.count)
                    let selected = state.rows.selectedID == row.id
                    var overlay = state.rows.markedIDs.contains(row.id) ? markedStyle : Style()
                    if selected { overlay = collectionStyle(overlay, overlay: selectionStyle) }
                    paintRow(
                        row.cells, regions: regions, in: rowArea, offset: state.horizontal.offset,
                        base: collectionStyle(style, overlay: row.style), overlay: overlay,
                        selectedColumn: selected ? state.selectedColumn : nil, buffer: &buffer)
                }
            }
            if let footer {
                paintRow(
                    footer, regions: regions,
                    in: Rect(x: area.x, y: body.maxY, width: area.width, height: area.maxY - body.maxY),
                    offset: state.horizontal.offset, base: collectionStyle(style, overlay: footerStyle),
                    buffer: &buffer)
            }
        }
    }

    /// Returns body cells only; headers, footers, spacing, and unused columns return nil.
    public func cell(at point: Point, in area: Rect, state: TableState<ID>) -> (row: ID, column: Int)? {
        let body = bodyArea(in: area)
        guard body.contains(point), let index = state.rows.index(atRow: state.rows.scroll.offset + point.y - body.y),
            rows.indices.contains(index), state.rows.ids[index] == rows[index].id
        else { return nil }
        let x = point.x - area.x + state.horizontal.offset
        guard let column = columnAreas(width: area.width).firstIndex(where: { x >= $0.x && x < $0.maxX }) else {
            return nil
        }
        return (rows[index].id, column)
    }

    private func paintRow(
        _ cells: [TableCell], regions: [Rect], in area: Rect, offset: Int, base: Style,
        overlay: Style = Style(), selectedColumn: Int? = nil, buffer: inout Buffer
    ) {
        guard area.height > 0 else { return }
        buffer.withClip(area) { buffer in
            fillCollectionArea(area, style: collectionStyle(base, overlay: overlay), buffer: &buffer)
            for (index, region) in regions.enumerated() {
                let cellArea = Rect(
                    x: area.x + region.x - offset, y: area.y, width: region.width, height: area.height)
                guard cellArea.maxX > area.x, cellArea.x < area.maxX, cellArea.width > 0 else { continue }
                let cellOverlay =
                    selectedColumn == index ? collectionStyle(overlay, overlay: cellSelectionStyle) : overlay
                fillCollectionArea(cellArea, style: collectionStyle(base, overlay: cellOverlay), buffer: &buffer)
                guard cells.indices.contains(index) else { continue }
                paintCollectionText(
                    cells[index].spans, in: cellArea, alignment: cells[index].alignment ?? columns[index].alignment,
                    style: base, overlay: cellOverlay, buffer: &buffer)
            }
        }
    }
}

extension TableRow: Sendable where ID: Sendable {}
extension TableState: Sendable where ID: Sendable {}
