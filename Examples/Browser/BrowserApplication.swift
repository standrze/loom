import Foundation
import loom

/// A complete application: loom supplies widgets/state; this type owns routing and filtering policy.
struct BrowserApplication {
    private enum Control: String { case search, categories, table, dialog }
    private enum Action {
        case nextFocus, previousFocus, next, previous, pageUp, pageDown, first, last, mark, sort, inspect, quit
    }

    private var focus = FocusState<Control>()
    private var search = LineEditor()
    private var categories = SelectionState(selectedID: "All")
    private var tableState = TableState(selectedID: 0)
    private var descending = false
    private var dialog: String?
    private var bounds = Rect(width: 0, height: 0)
    private var searchArea = Rect(width: 0, height: 0)
    private var listArea = Rect(width: 0, height: 0)
    private var tableArea = Rect(width: 0, height: 0)
    private var scrollbarArea = Rect(width: 0, height: 0)
    private var drag: ScrollbarDrag?

    private var categoryList: List<String> {
        List(["All", "Ready", "Running", "Failed"].map { ListItem(id: $0, $0) })
    }

    private var table: Table<Int> {
        let names = ["Ready", "Running", "Failed"]
        var ids = (0..<80).filter { id in
            let status = names[id % names.count]
            let categoryMatches = categories.selectedID == "All" || categories.selectedID == status
            return categoryMatches
                && (search.text.isEmpty || "job-\(id) \(status)".localizedCaseInsensitiveContains(search.text))
        }
        if descending { ids.reverse() }
        return Table(
            columns: [
                TableColumn("Job", width: .fill(2)), TableColumn("Status", width: .fill(1)),
                TableColumn("Duration", width: .length(9), alignment: .right),
            ],
            rows: ids.map { id in
                TableRow(
                    id: id,
                    cells: [TableCell("job-\(id)"), TableCell(names[id % names.count]), TableCell("\(id + 1)s")])
            })
    }

    private var bindings: KeyMap<Action> {
        var result = [
            KeyBinding(Action.nextFocus, keys: [KeyChord(.tab)], help: "focus"),
            KeyBinding(Action.previousFocus, keys: [KeyChord(.tab, modifiers: .shift)], help: "back"),
        ]
        if dialog == nil, focus.focusedID != .search {
            result += [
                KeyBinding(.previous, keys: [KeyChord(.up), KeyChord(.character("k"))], help: "up"),
                KeyBinding(.next, keys: [KeyChord(.down), KeyChord(.character("j"))], help: "down"),
                KeyBinding(.pageUp, keys: [KeyChord(.pageUp)], help: "page up"),
                KeyBinding(.pageDown, keys: [KeyChord(.pageDown)], help: "page down"),
                KeyBinding(.first, keys: [KeyChord(.home)], help: "first"),
                KeyBinding(.last, keys: [KeyChord(.end)], help: "last"),
            ]
        }
        if dialog == nil, focus.focusedID == .table {
            result += [
                KeyBinding(.mark, keys: [KeyChord(.character(" "))], help: "mark"),
                KeyBinding(.sort, keys: [KeyChord(.character("s"))], help: "reverse sort"),
                KeyBinding(.inspect, keys: [KeyChord(.enter)], help: "inspect"),
            ]
        }
        result.append(KeyBinding(.quit, keys: [KeyChord(.escape)], help: dialog == nil ? "quit" : "close dialog"))
        return KeyMap(result)
    }

    mutating func render(_ frame: inout Frame) {
        bounds = frame.area
        let regions = Layout(.vertical, [.length(1), .length(3), .fill(1), .length(3)]).split(bounds)
        searchArea = regions[1]
        let panes = Layout(.horizontal, [.max(16), .fill(1)]).split(regions[2])
        let leftPanel = Panel(title: "Status", padding: PanelPadding(left: 1, right: 1))
        let rightPanel = Panel(title: "Jobs")
        frame.render(leftPanel, in: panes[0])
        frame.render(rightPanel, in: panes[1])
        listArea = leftPanel.inner(panes[0])
        let content = rightPanel.inner(panes[1])
        tableArea = Rect(x: content.x, y: content.y, width: max(0, content.width - 1), height: content.height)
        let body = table.bodyArea(in: tableArea)
        scrollbarArea = Rect(x: tableArea.maxX, y: body.y, width: min(1, content.width), height: body.height)
        if dialog == nil {
            focus.update([
                FocusTarget(.search, area: searchArea), FocusTarget(.categories, area: panes[0]),
                FocusTarget(.table, area: panes[1]),
            ])
        }
        var input = TextInput(search, placeholder: "Filter jobs…", prompt: "Find", maximumRows: 1)
        input.borderStyle = Style(bold: focus.focusedID == .search)
        frame.render(input, in: searchArea)
        frame.render(categoryList, in: listArea, state: &categories)
        frame.render(table, in: tableArea, state: &tableState)
        frame.render(Scrollbar(tableState.rows.scroll), in: scrollbarArea)
        frame.render(KeyHelp(bindings), in: regions[3])
        let status =
            "loom browser | focus: \(focus.focusedID?.rawValue ?? "none") | \(tableState.rows.ids.count) rows | "
            + "\(tableState.rows.markedIDs.count) marked | selected: \(tableState.rows.selectedID.map(String.init) ?? "none")"
        frame.render(Paragraph(TextLayout(status, width: max(1, bounds.width))), in: regions[0])
        if focus.focusedID == .search { frame.cursor = input.cursor(in: searchArea) }
        if let dialog {
            let width = min(44, bounds.width)
            let height = min(5, bounds.height)
            let area = Rect(
                x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
            focus.update([FocusTarget(.dialog, area: area)])
            let panel = Panel(title: "Inspect", padding: PanelPadding(left: 1, right: 1))
            let blank = Paragraph(TextLayout(String(repeating: " ", count: width * height), width: max(1, width)))
            frame.render(blank, in: area)
            frame.render(panel, in: area)
            let inner = panel.inner(area)
            frame.render(
                Paragraph(TextLayout(dialog + "\nEscape closes; focus returns.", width: max(1, inner.width))), in: inner
            )
        }
    }

    mutating func handle(_ event: InputEvent) -> Bool {
        if case .signal = event { return false }
        if KeyChord(.interrupt).matches(event) || KeyChord(.endOfInput).matches(event) { return false }
        // Reconcile after each event, so a batched filter change followed by navigation sees current rows.
        categoryList.update(in: listArea, state: &categories)
        table.update(in: tableArea, state: &tableState)
        if let action = bindings.action(for: event) { return perform(action) }
        if case let .mouse(mouse) = event {
            guard dialog == nil else { return true }
            let bar = Scrollbar(tableState.rows.scroll)
            if drag != nil || scrollbarArea.contains(mouse.position) {
                if bar.handle(mouse, in: scrollbarArea, state: &tableState.rows.scroll, drag: &drag) { return true }
            }
            focus.handle(event)
            if mouse.kind == .down {
                if let id = categoryList.item(at: mouse.position, in: listArea, state: categories) {
                    categories.select(id)
                }
                if let hit = table.cell(at: mouse.position, in: tableArea, state: tableState) {
                    tableState.rows.select(hit.row)
                }
            } else if listArea.contains(mouse.position) {
                categories.scroll.handle(event)
            } else if tableArea.contains(mouse.position) {
                tableState.rows.scroll.handle(event)
            }
        } else if dialog == nil, focus.focusedID == .search {
            editSearch(event)
        }
        return true
    }

    private mutating func perform(_ action: Action) -> Bool {
        switch action {
        case .quit:
            guard dialog != nil else { return false }
            dialog = nil
            focus.popScope()
        case .nextFocus: focus.moveForward()
        case .previousFocus: focus.moveBackward()
        case .sort: descending.toggle()
        case .mark:
            if let id = tableState.rows.selectedID { tableState.rows.toggleMarked(id) }
        case .inspect:
            if let id = tableState.rows.selectedID {
                dialog = "Selected job-\(id)"
                focus.pushScope([FocusTarget(.dialog)])
            }
        default:
            if focus.focusedID == .categories {
                navigate(action, state: &categories)
            } else if focus.focusedID == .table {
                navigate(action, state: &tableState.rows)
            }
        }
        return true
    }

    private func navigate<ID>(_ action: Action, state: inout SelectionState<ID>) {
        switch action {
        case .next: state.moveSelection(by: 1)
        case .previous: state.moveSelection(by: -1)
        case .pageDown: state.pageSelection(by: 1)
        case .pageUp: state.pageSelection(by: -1)
        case .first: state.selectFirst()
        case .last: state.selectLast()
        default: break
        }
    }

    private mutating func editSearch(_ event: InputEvent) {
        switch event {
        case let .text(text), let .paste(text): search.insert(text.replacingOccurrences(of: "\n", with: " "))
        default:
            guard let key = event.keyboardEvent, key.kind != .release,
                key.modifiers.subtracting([.capsLock, .numLock, .shift]).isEmpty
            else { return }
            if case let .character(text) = key.key { search.insert(text) } else { search.handle(key.key) }
        }
    }
}
