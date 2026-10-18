import loom

/// Opt-in showcase with caller-owned layout cache and independent collection state.
struct WidgetsDetails {
    private var cache = LayoutCache(capacity: 8)
    private var listState = SelectionState<Int>(selectedID: 0)
    private var tableState = TableState<Int>(selectedID: 0)

    mutating func render(_ frame: inout Frame) {
        let rows = Layout(.vertical, [.length(1), .length(6), .fill(1), .length(3), .length(1)])
            .split(frame.area, cache: &cache)
        paint("loom details | overlap + layout cache | d returns", in: rows[0], frame: &frame)
        let shared = Layout(.horizontal, [.fill(1), .fill(1)], spacing: .overlap(1))
            .split(rows[1], cache: &cache)
        var borders = BorderLayer()
        borders.insert(Panel(title: "Merged single", borderStyle: Style(foreground: .indexed(6))), in: shared[0])
        borders.insert(
            Panel(borderType: .double, title: "Merged double", borderStyle: Style(foreground: .indexed(3))),
            in: shared[1])
        borders.render(buffer: &frame.buffer)
        paint("Shared topology", in: Panel().inner(shared[0]), frame: &frame)
        if let symbols = try? BorderSymbols(
            horizontal: "=", vertical: "!", topLeft: "+", topRight: "+",
            bottomLeft: "+", bottomRight: "+"),
            let shadow = try? PanelShadow(offsetX: 1, offsetY: 1, style: Style(foreground: .indexed(8)), glyph: "░")
        {
            let outer = Panel().inner(shared[1])
            let inset = Rect(
                x: outer.x + 1, y: outer.y, width: max(0, outer.width - 3), height: max(0, outer.height - 1))
            let custom = Panel(borderType: .custom(symbols), title: "Custom + shadow", shadow: shadow)
            frame.render(custom, in: inset)
        }
        let collections = Layout(.horizontal, [.fill(1), .fill(1)], spacing: 1).split(rows[2], cache: &cache)
        let listPanel = Panel(
            borders: [.left, .right, .bottom], title: "Reverse + auto-height", titlesWithoutBorders: true)
        frame.render(listPanel, in: collections[0])
        var list = List([
            ListItem(id: 0, "First item at bottom\nmeasured second line"),
            ListItem(id: 1, "Second item wraps naturally at the available terminal width"),
            ListItem(id: 2, "Third item above"),
        ])
        list.reversed = true
        list.automaticHeights = true
        list.selectionSymbol = "> "
        list.repeatHighlightSymbol = true
        list.prefixReservation = .always
        frame.render(list, in: listPanel.inner(collections[0]), state: &listState)
        let tablePanel = Panel(title: "Table row margins")
        frame.render(tablePanel, in: collections[1])
        var firstRow = TableRow(id: 0, cells: [TableCell("alpha"), TableCell("Measured\nsecond line")])
        firstRow.topMargin = 1
        firstRow.bottomMargin = 1
        var secondRow = TableRow(id: 1, cells: [TableCell("beta"), TableCell("Spaced rows")])
        secondRow.bottomMargin = 1
        var table = Table(
            columns: [TableColumn("Item", width: .length(8)), TableColumn("Details", width: .length(14))],
            rows: [firstRow, secondRow])
        table.automaticHeights = true
        table.columnFlex = .center
        frame.render(table, in: tablePanel.inner(collections[1]), state: &tableState)
        let styled = [
            TextSpan("Underline color ", style: Style(underlined: true, underlineColor: .indexed(2))),
            TextSpan("Slow blink ", style: Style(blink: .slow)),
            TextSpan("hidden sample", style: Style(hidden: true)),
        ]
        frame.render(Paragraph(TextLayout(styled, width: max(1, rows[3].width))), in: rows[3])
        paint("Hidden/blink are terminal attributes; cache entries: \(cache.count)", in: rows[4], frame: &frame)
    }

    private func paint(_ text: String, in area: Rect, frame: inout Frame) {
        frame.render(Paragraph(TextLayout(text, width: max(1, area.width))), in: area)
    }
}
