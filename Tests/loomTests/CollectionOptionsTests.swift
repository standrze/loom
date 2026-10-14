import Testing

@testable import loom

@Test func listPrefixUsesTerminalCellsAndItemAlignment() {
    var list = List([ListItem(id: 1, "X", alignment: .right), ListItem(id: 2, "Y")])
    list.selectionSymbol = "界 "
    list.prefixReservation = .always
    var state = SelectionState(selectedID: 1)
    var frame = Frame(width: 8, height: 2)
    frame.render(list, in: Rect(width: 8, height: 2), state: &state)
    #expect(frame.buffer[0, 0].symbol == "界")
    #expect(frame.buffer[7, 0].symbol == "X")
    #expect(frame.buffer[3, 1].symbol == "Y")
    #expect(list.item(at: Point(x: 0, y: 1), in: Rect(width: 8, height: 2), state: state) == 2)
}

@Test func selectionPaddingRevealsOnNavigationAndPreservesManualScrolling() {
    let list = List((0..<20).map { ListItem(id: $0, "Row") })
    var state = SelectionState(selectedID: 7)
    state.revealPadding = 1
    let area = Rect(width: 8, height: 5)
    list.update(in: area, state: &state)
    #expect(state.scroll.offset == 4)
    state.scroll.scroll(to: 0)
    list.update(in: area, state: &state)
    #expect(state.scroll.offset == 0)
    state.moveSelection(by: 1)
    #expect(state.scroll.offset == 5)
}

@Test func tablePrefixAndIndependentColumnSelectionShareGeometry() {
    var table = Table(
        columns: [TableColumn("A"), TableColumn("B")],
        rows: [
            TableRow(id: 1, cells: [TableCell("a"), TableCell("b")]),
            TableRow(id: 2, cells: [TableCell("c"), TableCell("d")]),
        ])
    table.selectionSymbol = "> "
    table.prefixReservation = .always
    table.columnSelectionPatch = StylePatch(background: .indexed(4), bold: true)
    table.cellSelectionPatch = StylePatch(bold: false)
    var state = TableState(selectedID: 1)
    let area = Rect(width: 9, height: 3)
    table.update(in: area, state: &state)
    state.highlightColumn(1)
    state.selectCell(row: 1, column: 1)
    var frame = Frame(width: 9, height: 3)
    frame.render(table, in: area, state: &state)
    #expect(table.cell(at: Point(x: 0, y: 1), in: area, state: state) == nil)
    #expect(table.cell(at: Point(x: 2, y: 1), in: area, state: state)?.column == 0)
    #expect(frame.buffer[6, 0].style.background == .indexed(4))
    #expect(!frame.buffer[6, 1].style.bold)
    #expect(frame.buffer[6, 2].style.bold)
    state.selectColumn(nil)
    #expect(state.highlightedColumn == 1)
}

@Test func scrollbarEndpointsReduceTrackAndInvalidSymbolsFallBack() {
    let state = ScrollState(contentLength: 20, viewportLength: 4)
    var bar = Scrollbar(state)
    bar.startSymbol = "^"
    bar.endSymbol = "v"
    bar.thumbSymbol = "界"
    let area = Rect(width: 1, height: 6)
    #expect(bar.trackArea(in: area) == Rect(x: 0, y: 1, width: 1, height: 4))
    var frame = Frame(width: 1, height: 6)
    frame.render(bar, in: area)
    #expect(frame.buffer[0, 0].symbol == "^")
    #expect(frame.buffer[0, 1].symbol == "█")
    #expect(frame.buffer[0, 5].symbol == "v")
}

@Test func scrollbarDragUsesEndpointAdjustedTrack() {
    var state = ScrollState(contentLength: 100, viewportLength: 20)
    var bar = Scrollbar(state)
    bar.startSymbol = "^"
    bar.endSymbol = "v"
    let area = Rect(x: 2, y: 2, width: 1, height: 7)
    var drag: ScrollbarDrag?
    #expect(bar.handle(MouseEvent(kind: .down, position: Point(x: 2, y: 3)), in: area, state: &state, drag: &drag))
    #expect(drag != nil)
    #expect(bar.handle(MouseEvent(kind: .drag, position: Point(x: 2, y: 7)), in: area, state: &state, drag: &drag))
    #expect(state.offset == state.maximumOffset)
    #expect(bar.handle(MouseEvent(kind: .up, position: Point(x: 2, y: 7)), in: area, state: &state, drag: &drag))
    #expect(drag == nil)
    #expect(bar.handle(MouseEvent(kind: .down, position: Point(x: 2, y: 2)), in: area, state: &state, drag: &drag))
    #expect(state.offset == state.maximumOffset - 1)
}

@Test func collectionSpanPatchResetsInheritedModifiersBeforeSelection() {
    var list = List([ListItem(id: 1, spans: [TextSpan("X", patch: StylePatch(bold: false))])])
    list.style = Style(foreground: .indexed(2), bold: true)
    list.selectionPatch = StylePatch(foreground: .terminalDefault, underlined: true)
    var state = SelectionState(selectedID: 1)
    var frame = Frame(width: 3, height: 1)
    frame.render(list, in: Rect(width: 3, height: 1), state: &state)
    #expect(!frame.buffer[0, 0].style.bold)
    #expect(frame.buffer[0, 0].style.foreground == .terminalDefault)
    #expect(frame.buffer[0, 0].style.underlined)
    #expect(frame.buffer[0, 0].style.reversed)
}

@Test func scrollbarEndpointsPreserveGlyphsCrossingTheirAssignedArea() {
    var buffer = Buffer(width: 4, height: 2)
    buffer.put("界", width: 2, at: Point(x: 0, y: 0))
    var bar = Scrollbar(ScrollState(contentLength: 10, viewportLength: 2))
    bar.startSymbol = "^"
    bar.render(in: Rect(x: 1, width: 1, height: 2), buffer: &buffer)
    #expect(buffer[0, 0].symbol == "界")
    #expect(buffer[1, 0].width == 0)
}

@Test func prefixReservationUsesTheSameTabExpansionAsItsRendering() {
    var list = List([ListItem(id: 1, "X")])
    list.selectionSymbol = "\t"
    list.prefixReservation = .always
    var state = SelectionState(selectedID: 1)
    var buffer = Buffer(width: 6, height: 1)
    list.render(in: buffer.area, buffer: &buffer, state: &state)
    #expect(buffer[4, 0].symbol == "X")
}
