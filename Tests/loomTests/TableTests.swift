import Testing

@testable import loom

private func sampleTable() -> Table<Int> {
    Table(
        columns: [TableColumn("Name", width: .length(6)), TableColumn("Count", alignment: .right)],
        rows: (0..<8).map { TableRow(id: $0, cells: [TableCell("row\($0)"), TableCell("\($0 * 10)")]) })
}

@Test func tableKeepsHeadersFootersAndSelectionWhileScrolling() {
    var table = sampleTable()
    table.footer = [TableCell("Total"), TableCell("280")]
    let area = Rect(x: 1, y: 1, width: 12, height: 5)
    var state = TableState(selectedID: 6, selectedColumn: 1)
    var buffer = Buffer(width: 15, height: 7)
    table.render(in: area, buffer: &buffer, state: &state)
    #expect(state.rows.scroll.offset == 4)
    #expect(table.bodyArea(in: area) == Rect(x: 1, y: 2, width: 12, height: 3))
    #expect(buffer[1, 1].symbol == "N")
    #expect(buffer[1, 5].symbol == "T")
    #expect(buffer[4, 2].symbol == "4")
    #expect(buffer[4, 4].symbol == "6")
    #expect(buffer[11, 4].symbol == "6")
    #expect(buffer[12, 4].symbol == "0")
    #expect(buffer[12, 4].style.reversed)
    #expect(buffer[12, 4].style.underlined)
    #expect(!buffer[1, 4].style.underlined)
    #expect(!buffer[1, 1].style.reversed)
    #expect(table.cell(at: Point(x: 12, y: 4), in: area, state: state)?.row == 6)
    #expect(table.cell(at: Point(x: 12, y: 4), in: area, state: state)?.column == 1)
    #expect(table.cell(at: Point(x: 7, y: 4), in: area, state: state) == nil)
    #expect(table.cell(at: Point(x: 2, y: 1), in: area, state: state) == nil)
    #expect(table.cell(at: Point(x: 2, y: 5), in: area, state: state) == nil)
}

@Test func horizontalTableScrollMovesHeadersAndBodyTogether() {
    var table = Table(
        columns: [TableColumn("First", width: .length(4)), TableColumn("Second", width: .length(6))],
        rows: [
            TableRow(id: 1, cells: [TableCell("AAAA"), TableCell("世界AB")])
        ])
    table.minimumWidth = 11
    var state = TableState(selectedID: 1)
    let area = Rect(x: 1, width: 5, height: 2)
    table.update(in: area, state: &state)
    state.horizontal.scroll(to: 6)
    var buffer = Buffer(width: 8, height: 3)
    table.render(in: area, buffer: &buffer, state: &state)
    #expect(state.horizontal.offset == 6)
    #expect(buffer[1, 0].symbol == "e")
    #expect(buffer[1, 1].symbol == " ")
    #expect(buffer[2, 1].symbol == "界")
    #expect(buffer[3, 1].width == 0)
    #expect(buffer[4, 1].symbol == "A")
    #expect(buffer[5, 1].symbol == "B")
    #expect(buffer[0, 1].symbol == " ")
    #expect(buffer[6, 1].symbol == " ")
    #expect(table.cell(at: Point(x: 4, y: 1), in: area, state: state)?.column == 1)
}

@Test func tableNavigationRevealsCellsAndReconcilesRemovedColumns() {
    var table = sampleTable()
    table.minimumWidth = 30
    let area = Rect(width: 10, height: 4)
    var state = TableState(selectedID: 0, selectedColumn: 0)
    table.update(in: area, state: &state)
    #expect(state.handle(.key(.right)) == true)
    #expect(state.selectedColumn == 1)
    #expect(state.horizontal.offset == 7)
    #expect(state.handle(.key(.end)) == true)
    #expect(state.rows.selectedID == 7)
    state.rows.toggleMarked(7)
    table.rows.reverse()
    table.update(in: area, state: &state)
    #expect(state.rows.selectedID == 7)
    #expect(state.rows.selectedIndex == 0)
    #expect(state.rows.markedIDs == [7])
    table.columns.removeLast()
    table.update(in: area, state: &state)
    #expect(state.selectedColumn == 0)
    #expect(state.horizontal.offset == 0)
    table.columns.removeAll()
    table.update(in: area, state: &state)
    #expect(state.selectedColumn == nil)
}

@Test func tableVariableRowsKeepStylesAndAlignmentInsideCells() {
    let table = Table(
        columns: [TableColumn("A", width: .length(5)), TableColumn("B", alignment: .center)],
        rows: [TableRow(id: 1, cells: [TableCell("one\ntwo"), TableCell("中", style: Style(italic: true))], height: 2)])
    var state = TableState(selectedID: 1)
    var buffer = Buffer(width: 11, height: 4)
    table.render(in: buffer.area, buffer: &buffer, state: &state)
    #expect(buffer[0, 1].symbol == "o")
    #expect(buffer[0, 2].symbol == "t")
    #expect(buffer[7, 1].symbol == "中")
    #expect(buffer[7, 1].style.italic)
    #expect(buffer[7, 1].style.reversed)
    #expect(table.cell(at: Point(x: 7, y: 2), in: buffer.area, state: state)?.row == 1)
    #expect(table.cell(at: Point(x: 7, y: 3), in: buffer.area, state: state) == nil)
}

@Test func tableHandlesEmptyTinyAndOffscreenAreas() {
    var table = sampleTable()
    var state = TableState(selectedID: 7, selectedColumn: 1)
    var buffer = Buffer(width: 8, height: 3)
    table.render(in: Rect(x: -1, y: -1, width: 4, height: 3), buffer: &buffer, state: &state)
    table.render(in: Rect(width: 1, height: 1), buffer: &buffer, state: &state)
    #expect(state.rows.scroll.viewportLength == 0)
    table.render(in: Rect(width: 0, height: 0), buffer: &buffer, state: &state)
    table.rows = []
    table.render(in: buffer.area, buffer: &buffer, state: &state)
    #expect(state.rows.selectedID == nil)
    #expect(buffer.plainText.contains("No rows"))
}

@Test func tableColumnFlexSharesLayoutGeometryWithPaintingAndHitTesting() {
    var table = Table(
        columns: [TableColumn("A", width: .length(2)), TableColumn("B", width: .length(2))],
        rows: [TableRow(id: 1, cells: [TableCell("界"), TableCell("XY")])])
    let area = Rect(x: 1, y: 1, width: 12, height: 2)
    for flex in Flex.allCases {
        table.columnFlex = flex
        let expected = Layout(.horizontal, [.length(2), .length(2)], spacing: 1, flex: flex)
            .split(Rect(width: area.width, height: 1))
        #expect(table.columnAreas(width: area.width) == expected)
        var state = TableState<Int>()
        var buffer = Buffer(width: 14, height: 4)
        table.render(in: area, buffer: &buffer, state: &state)
        #expect(buffer[area.x + expected[0].x, area.y + 1].symbol == "界")
        #expect(buffer[area.x + expected[0].x + 1, area.y + 1].width == 0)
        #expect(buffer[area.x + expected[1].x, area.y].symbol == "B")
        for x in 0..<area.width {
            let column = expected.firstIndex { x >= $0.x && x < $0.maxX }
            #expect(table.cell(at: Point(x: area.x + x, y: area.y + 1), in: area, state: state)?.column == column)
        }
    }
}

@Test func tableColumnFlexClampsTinyAreasAndPreservesScrollingAndPrefixGeometry() {
    var table = Table(
        columns: [TableColumn("A", width: .length(2)), TableColumn("B", width: .length(2))],
        rows: [TableRow(id: 1, cells: [TableCell("界"), TableCell("XY")])])
    table.columnFlex = .end
    table.selectionSymbol = "> "
    table.prefixReservation = .always
    table.minimumWidth = 10
    var state = TableState(selectedID: 1, selectedColumn: 1)
    let area = Rect(width: 6, height: 2)
    var buffer = Buffer(width: 6, height: 2)
    table.render(in: area, buffer: &buffer, state: &state)
    #expect(state.horizontal.offset == 6)
    #expect(buffer[0, 1].symbol == ">")
    #expect(buffer[4, 1].symbol == "X")
    #expect(table.cell(at: Point(x: 0, y: 1), in: area, state: state) == nil)
    #expect(table.cell(at: Point(x: 4, y: 1), in: area, state: state)?.column == 1)
    table.minimumWidth = 0
    table.prefixReservation = .never
    for flex in Flex.allCases {
        table.columnFlex = flex
        for width in 0...2 {
            let tiny = Rect(width: width, height: 2)
            table.render(in: tiny, buffer: &buffer, state: &state)
            let regions = table.columnAreas(width: width)
            #expect(regions.allSatisfy { $0.x >= 0 && $0.maxX <= width })
            #expect(table.cell(at: Point(x: width, y: 1), in: tiny, state: state) == nil)
        }
    }
}
