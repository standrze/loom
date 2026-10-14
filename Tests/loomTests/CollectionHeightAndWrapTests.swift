import Testing

@testable import loom

@Test func reversedListAlignsFirstAtBottomAndNavigatesOnScreen() {
    var list = List([ListItem(id: 0, "zero"), ListItem(id: 1, "one")])
    list.reversed = true
    let area = Rect(width: 5, height: 4)
    var state = SelectionState(selectedID: 0)
    var frame = Frame(width: 5, height: 4)
    frame.render(list, in: area, state: &state)
    #expect(frame.buffer[0, 3].symbol == "z")
    #expect(list.item(at: Point(x: 0, y: 2), in: area, state: state) == 1)
    #expect(list.item(at: Point(x: 0, y: 0), in: area, state: state) == nil)
    state.moveSelection(by: -1)
    #expect(state.selectedID == 1)
    state.selectFirst()
    #expect(state.selectedID == 1)
}

@Test func automaticListHeightUsesPrefixWidthAndCustomMeasurement() {
    var list = List([ListItem(id: 0, "abcdef")])
    list.automaticHeights = true
    list.selectionSymbol = "> "
    list.prefixReservation = .always
    var state = SelectionState<Int>()
    list.update(in: Rect(width: 5, height: 8), state: &state)
    #expect(state.scroll.contentLength == 2)
    list.measureRow = { _, width in width + 1 }
    list.update(in: Rect(width: 5, height: 8), state: &state)
    #expect(state.scroll.contentLength == 4)
}

@Test func tableMarginsOccupyScrollRowsWithoutCellHits() {
    var row = TableRow(id: 0, cells: [TableCell("abcdef")])
    row.topMargin = 1
    row.bottomMargin = 2
    var table = Table(columns: [TableColumn("A")], rows: [row])
    table.showsHeader = false
    table.automaticHeights = true
    var state = TableState<Int>()
    let area = Rect(width: 3, height: 6)
    table.update(in: area, state: &state)
    #expect(state.rows.scroll.contentLength == 5)
    #expect(table.cell(at: Point(x: 0, y: 0), in: area, state: state) == nil)
    #expect(table.cell(at: Point(x: 0, y: 1), in: area, state: state)?.row == 0)
    #expect(table.cell(at: Point(x: 0, y: 3), in: area, state: state) == nil)
}

@Test func wrapControlsPreserveSourceAndTabSelection() {
    let source = "abc  def\tghi"
    let layout = TextLayout(source, width: 3, options: TextWrapOptions(trimLeadingWhitespace: true, tabWidth: 2))
    #expect(layout.lines[1].glyphs.first?.text == "d")
    #expect(layout.selectedText(TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 9, y: 9))) == source)
    let long = TextLayout("abcdef", width: 3, wrapping: .word, options: TextWrapOptions(breakLongWords: false))
    #expect(long.lines.count == 1)
    #expect(long.lines[0].glyphs.last?.column == 5)
}

@Test func reverseOverflowStartsAtFirstItemAndPreservesManualScroll() {
    var list = List((0..<8).map { ListItem(id: $0, "\($0)") })
    list.reversed = true
    var state = SelectionState<Int>()
    let area = Rect(width: 3, height: 3)
    var frame = Frame(width: 3, height: 3)
    frame.render(list, in: area, state: &state)
    #expect(frame.buffer[0, 2].symbol == "0")
    #expect(state.scroll.offset == 5)
    state.scroll.scroll(to: 0)
    list.update(in: area, state: &state)
    #expect(state.scroll.offset == 0)
}

@Test func collectionWrappingMeasurementMatchesPaint() {
    var list = List([ListItem(id: 0, "abc  def\tghi")])
    list.automaticHeights = true
    list.wrapping = .word
    list.wrapOptions = TextWrapOptions(trimLeadingWhitespace: true, tabWidth: 2)
    var state = SelectionState<Int>()
    var frame = Frame(width: 3, height: 8)
    frame.render(list, in: Rect(width: 3, height: 8), state: &state)
    let layout = TextLayout("abc  def\tghi", width: 3, wrapping: list.wrapping, options: list.wrapOptions)
    #expect(state.scroll.contentLength == layout.lines.count)
    #expect(frame.buffer[0, 1].symbol == "d")

    var table = Table(columns: [TableColumn("A")], rows: [TableRow(id: 0, cells: [TableCell("abcdef")])])
    table.showsHeader = false
    table.automaticHeights = true
    table.wrapping = .word
    table.wrapOptions = TextWrapOptions(breakLongWords: false)
    var tableState = TableState<Int>()
    var tableFrame = Frame(width: 3, height: 4)
    tableFrame.render(table, in: Rect(width: 3, height: 4), state: &tableState)
    #expect(tableState.rows.scroll.contentLength == 1)
    #expect(tableFrame.buffer[0, 0].symbol == "a")
    #expect(tableFrame.buffer[0, 1].symbol == " ")
}

@Test func trimmedTrailingWhitespaceDoesNotCreateSoftWrapRows() {
    let options = TextWrapOptions(trimLeadingWhitespace: true)
    for text in ["abcd ", "abcd\t", "abcd \t  ", "    ", "\t\t"] {
        let layout = TextLayout(text, width: 4, options: options)
        #expect(layout.lines.count == 1)
        #expect(layout.source == text)
    }
    let explicit = TextLayout("abcd \t\n  x", width: 4, options: options)
    #expect(explicit.lines.count == 2)
    #expect(explicit.lines[1].glyphs.first?.text == " ")
    #expect(explicit.selectedText(TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 3, y: 1))) == "abcd \t\n  x")
    let interior = TextLayout("abcd \txyz", width: 4, options: options)
    #expect(interior.lines.count == 2)
    #expect(interior.lines[1].glyphs.first?.text == "x")
    #expect(interior.selectedText(TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 3, y: 1))) == "abcd \txyz")
}

@Test func automaticTableHeightIgnoresInvisibleColumns() {
    var table = Table(
        columns: [TableColumn("A", width: .length(3)), TableColumn("B", width: .length(0))],
        rows: [TableRow(id: 0, cells: [TableCell("abc"), TableCell("hidden long content")])])
    table.showsHeader = false
    table.automaticHeights = true
    var state = TableState<Int>()
    table.update(in: Rect(width: 4, height: 8), state: &state)
    #expect(state.rows.scroll.contentLength == 1)
}

@Test func trimmedBoundaryStillStartsAnUnbrokenLongWord() {
    let layout = TextLayout(
        "abcd efghijkl", width: 4, wrapping: .word,
        options: TextWrapOptions(trimLeadingWhitespace: true, breakLongWords: false))
    #expect(layout.lines.count == 2)
    #expect(layout.lines[1].glyphs.map(\.text).joined() == "efghijkl")
    #expect(layout.source == "abcd efghijkl")
}

@Test func reversedVariableHeightPagingFollowsPhysicalRows() {
    var list = List([
        ListItem(id: 0, "first", height: 2), ListItem(id: 1, "second"),
        ListItem(id: 2, "third", height: 3), ListItem(id: 3, "fourth"),
    ])
    list.reversed = true
    var state = SelectionState<Int>(selectedID: 0)
    list.update(in: Rect(width: 6, height: 3), state: &state)
    state.pageSelection(by: -1)
    #expect(state.selectedID == 2)
    state.pageSelection(by: 1)
    #expect(state.selectedID == 1)
    state.selectFirst()
    #expect(state.selectedID == 3)
    state.selectLast()
    #expect(state.selectedID == 0)
}
