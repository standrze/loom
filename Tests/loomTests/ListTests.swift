import Testing

@testable import loom

@Test func listSelectionScrollsAndHitTestingUsesSameRows() {
    let list = List((0..<10).map { ListItem(id: $0, "Row \($0)") })
    var state = SelectionState(selectedID: 7)
    let area = Rect(x: 2, y: 1, width: 8, height: 3)
    var frame = Frame(width: 12, height: 5)
    frame.render(list, in: area, state: &state)
    #expect(state.scroll.offset == 5)
    #expect(frame.buffer[6, 1].symbol == "5")
    #expect(frame.buffer[6, 3].symbol == "7")
    #expect(frame.buffer[9, 3].style.reversed)
    #expect(!frame.buffer[9, 2].style.reversed)
    #expect(list.item(at: Point(x: 3, y: 1), in: area, state: state) == 5)
    #expect(list.item(at: Point(x: 9, y: 3), in: area, state: state) == 7)
    #expect(list.item(at: Point(x: 10, y: 3), in: area, state: state) == nil)
    state.scroll.scroll(to: 0)
    frame.render(list, in: area, state: &state)
    #expect(frame.buffer[6, 1].symbol == "0")
    #expect(state.selectedID == 7)
}

@Test func customListRowsAreClippedAndOnlyVisibleRowsAreCalled() {
    var rendered: [Int] = []
    var list = List((0..<20).map { ListItem(id: $0, "Row", height: 2) })
    list.renderRow = { item, appearance, area, buffer in
        rendered.append(item.id)
        for y in (area.y - 1)..<(area.maxY + 1) {
            for x in 0..<buffer.width {
                buffer.put(String(item.id), width: 1, at: Point(x: x, y: y), style: appearance.style)
            }
        }
    }
    var state = SelectionState(selectedID: 2)
    let area = Rect(x: 2, y: 1, width: 3, height: 3)
    list.update(in: area, state: &state)
    state.scroll.scroll(to: 3)
    var buffer = Buffer(width: 7, height: 5)
    list.render(in: area, buffer: &buffer, state: &state)
    #expect(rendered == [1, 2])
    #expect(buffer[2, 1].symbol == "1")
    #expect(buffer[2, 2].symbol == "2")
    #expect(buffer[2, 3].symbol == "2")
    #expect(buffer[2, 3].style.reversed)
    #expect(buffer[1, 2].symbol == " ")
    #expect(buffer[5, 2].symbol == " ")
    #expect(buffer[2, 0].symbol == " ")
    #expect(buffer[2, 4].symbol == " ")
}

@Test func listPreservesRichTextLinksAndWholeWideGlyphs() {
    let list = List([
        ListItem(id: 1, spans: [TextSpan("A中界", style: Style(italic: true), link: "https://example.com")])
    ])
    var state = SelectionState(selectedID: 1)
    var buffer = Buffer(width: 7, height: 2)
    list.render(in: Rect(x: 1, width: 4, height: 1), buffer: &buffer, state: &state)
    #expect(buffer[1, 0].symbol == "A")
    #expect(buffer[2, 0].symbol == "中")
    #expect(buffer[3, 0].width == 0)
    #expect(buffer[4, 0].symbol == " ")
    #expect(buffer[2, 0].style.italic)
    #expect(buffer[2, 0].style.reversed)
    #expect(buffer[2, 0].link == "https://example.com")
}

@Test func emptyAndZeroSizedListsClearSelectionAndDoNotHitPadding() {
    var state = SelectionState(selectedID: 1)
    var buffer = Buffer(width: 12, height: 3)
    List([ListItem(id: 1, "one")]).render(in: buffer.area, buffer: &buffer, state: &state)
    let empty = List<Int>([])
    empty.render(in: buffer.area, buffer: &buffer, state: &state)
    #expect(buffer.plainText.contains("No items"))
    #expect(state.selectedID == nil)
    #expect(empty.item(at: Point(x: 0, y: 0), in: buffer.area, state: state) == nil)
    empty.render(in: Rect(width: 0, height: 0), buffer: &buffer, state: &state)
    #expect(state.visibleIndices.isEmpty)
    let short = List([ListItem(id: 1, "one")])
    short.update(in: buffer.area, state: &state)
    #expect(short.item(at: Point(x: 0, y: 2), in: buffer.area, state: state) == nil)
}

@Test func nestedBufferClipsRestoreAndDoNotSplitNewWideGlyphs() {
    var buffer = Buffer(width: 8, height: 2)
    buffer.withClip(Rect(x: 2, width: 4, height: 1)) { buffer in
        buffer.put("X", width: 1, at: Point(x: 0, y: 0))
        buffer.put("中", width: 2, at: Point(x: 5, y: 0))
        buffer.withClip(Rect(x: 3, width: 1, height: 1)) { buffer in
            buffer.put("X", width: 1, at: Point(x: 2, y: 0))
            buffer.put("Y", width: 1, at: Point(x: 3, y: 0))
        }
        buffer.put("Z", width: 1, at: Point(x: 2, y: 0))
    }
    buffer.put("A", width: 1, at: Point(x: 0, y: 1))
    #expect(buffer[0, 0].symbol == " ")
    #expect(buffer[2, 0].symbol == "Z")
    #expect(buffer[3, 0].symbol == "Y")
    #expect(buffer[5, 0].symbol == " ")
    #expect(buffer[6, 0].symbol == " ")
    #expect(buffer[0, 1].symbol == "A")
}
