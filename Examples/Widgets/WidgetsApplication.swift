import loom

/// A standalone composition; filtering, sorting, focus, and input policy remain application-owned.
struct WidgetsApplication {
    private enum Action { case quit, filter, sort, focus, logDown, logRight, align, details }
    private var showingDetails = false
    private var details = WidgetsDetails()
    private var tableState = TableState(selectedID: 0)
    private var filtered = false
    private var descending = false
    private var logFocused = false
    private var logScroll = ScrollState()
    private var logColumn = 0
    private var logAlignment: CellAlignment = .left
    private var tableArea = Rect(width: 0, height: 0)
    private var logArea = Rect(width: 0, height: 0)
    private var tabsArea = Rect(width: 0, height: 0)
    private var scrollbarArea = Rect(width: 0, height: 0)
    private var drag: ScrollbarDrag?

    private var bindings: KeyMap<Action> {
        KeyMap([
            KeyBinding(.quit, keys: [KeyChord(.escape)], help: "quit"),
            KeyBinding(.filter, keys: [KeyChord(.character("f"))], help: "filter"),
            KeyBinding(.sort, keys: [KeyChord(.character("s"))], help: "sort"),
            KeyBinding(.focus, keys: [KeyChord(.tab)], help: "table/log"),
            KeyBinding(.logDown, keys: [KeyChord(.character("l"))], help: "log down"),
            KeyBinding(.logRight, keys: [KeyChord(.character("h"))], help: "log right"),
            KeyBinding(.details, keys: [KeyChord(.character("d"))], help: "details"),
            KeyBinding(.align, keys: [KeyChord(.character("a"))], help: "align log"),
        ])
    }

    private var tabs: Tabs<String> {
        Tabs(
            [Tab(id: "all", label: "All jobs"), Tab(id: "ready", label: "Ready")], selected: filtered ? "ready" : "all")
    }

    private var table: Table<Int> {
        var ids = (0..<40).filter { !filtered || $0.isMultiple(of: 2) }
        if descending { ids.reverse() }
        var table = Table(
            columns: [
                TableColumn("Job", width: .fill(2)), TableColumn("Status", width: .fill(1)),
                TableColumn("Progress", width: .length(10), alignment: .right),
            ],
            rows: ids.map { id in
                TableRow(
                    id: id,
                    cells: [
                        TableCell("job-\(id)"), TableCell(id.isMultiple(of: 2) ? "Ready" : "Running"),
                        TableCell("\(id * 100 / 39)%"),
                    ])
            })
        table.selectionSymbol = "> "
        table.prefixReservation = .always
        table.minimumWidth = 34
        table.columnSelectionPatch = StylePatch(underlined: true)
        table.selectionPatch = StylePatch(foreground: .indexed(15), background: .indexed(4), reversed: false)
        table.cellSelectionPatch = StylePatch(underlined: true)
        return table
    }

    mutating func render(_ frame: inout Frame) {
        if showingDetails {
            details.render(&frame)
            return
        }
        let regions = Layout(.vertical, [.length(1), .length(1), .fill(2), .length(2), .fill(1), .length(2)]).split(
            frame.area)
        let status =
            "loom widgets | \(tableState.rows.selectedID.map { "selected: \($0)" } ?? "selected: none") | \(filtered ? "Ready" : "All") | \(descending ? "descending" : "ascending") | focus: \(logFocused ? "log" : "table")"
        frame.render(Paragraph(TextLayout(status, width: max(1, frame.area.width))), in: regions[0])
        tabsArea = regions[1]
        frame.render(tabs, in: tabsArea)
        let panel = Panel(
            titles: [
                PanelTitle([TextSpan(" Job queue ", patch: StylePatch(bold: true))]),
                PanelTitle([TextSpan(" stable IDs ")], alignment: .right, position: .bottom),
            ],
            borderStyle: Style(foreground: .indexed(6)), titleStyle: Style(foreground: .indexed(3)))
        frame.render(panel, in: regions[2])
        let content = panel.inner(regions[2])
        tableArea = Rect(x: content.x, y: content.y, width: max(0, content.width - 1), height: content.height)
        let body = table.bodyArea(in: tableArea)
        scrollbarArea = Rect(x: tableArea.maxX, y: body.y, width: min(1, content.width), height: body.height)
        tableState.rows.revealPadding = 1
        let currentTable = table
        currentTable.update(in: tableArea, state: &tableState)
        if tableState.highlightedColumn == nil { tableState.highlightColumn(1) }
        frame.render(currentTable, in: tableArea, state: &tableState)
        var bar = Scrollbar(tableState.rows.scroll)
        bar.startSymbol = "^"
        bar.endSymbol = "v"
        frame.render(bar, in: scrollbarArea)
        let progress = Double(tableState.rows.selectedID ?? 0) / 39
        let bars = Layout(.vertical, [.length(1), .length(1)]).split(regions[3])
        frame.render(
            Gauge(ratio: progress, label: "Selected job progress", filledStyle: Style(foreground: .indexed(2))),
            in: bars[0])
        frame.render(
            LineGauge(ratio: 0.625, label: "Queue capacity", filledStyle: Style(foreground: .indexed(6))), in: bars[1])
        let alignmentName = logAlignment == .left ? "left" : logAlignment == .center ? "center" : "right"
        let logPanel = Panel(title: "Log row: \(logScroll.offset) col: \(logColumn) \(alignmentName)")
        frame.render(logPanel, in: regions[4])
        logArea = logPanel.inner(regions[4])
        let messages = (0..<24).map { "log \($0): job event — Unicode 界 — worker completed its checkpoint" }.joined(
            separator: "\n")
        let layout = TextLayout(messages, width: max(1, logArea.width), wrapping: .none)
        logScroll.update(contentLength: layout.lines.count, viewportLength: logArea.height)
        frame.render(
            Paragraph(layout, scroll: logScroll.offset, horizontalScroll: logColumn, alignment: logAlignment),
            in: logArea)
        frame.render(KeyHelp(bindings), in: regions[5])
    }

    mutating func handle(_ event: InputEvent) -> Bool {
        if let action = bindings.action(for: event) {
            switch action {
            case .quit: return false
            case .details: showingDetails.toggle()
            case .filter: filtered.toggle()
            case .sort: descending.toggle()
            case .focus: logFocused.toggle()
            case .logDown: logScroll.scroll(by: 1)
            case .logRight: logColumn = (logColumn + 4) % 24
            case .align: logAlignment = logAlignment == .left ? .center : logAlignment == .center ? .right : .left
            }
            return true
        }
        if case let .mouse(mouse) = event {
            if mouse.kind == .down, let tab = tabs.hitTest(mouse.position, in: tabsArea) {
                filtered = tab == "ready"
                return true
            }
            let bar = Scrollbar(tableState.rows.scroll)
            var endpointBar = bar
            endpointBar.startSymbol = "^"
            endpointBar.endSymbol = "v"
            if drag != nil || scrollbarArea.contains(mouse.position) {
                _ = endpointBar.handle(mouse, in: scrollbarArea, state: &tableState.rows.scroll, drag: &drag)
            } else if tableArea.contains(mouse.position) {
                if mouse.kind == .down, let cell = table.cell(at: mouse.position, in: tableArea, state: tableState) {
                    tableState.selectCell(row: cell.row, column: cell.column)
                } else {
                    _ = tableState.rows.scroll.handle(event)
                }
            } else if logArea.contains(mouse.position) {
                _ = logScroll.handle(event)
            }
            return true
        }
        if logFocused {
            _ = logScroll.handle(event)
        } else {
            _ = tableState.handle(event, allowsMultipleSelection: true)
        }
        return true
    }
}
