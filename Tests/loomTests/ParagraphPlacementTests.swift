import Testing
import loom

@Test func alignedParagraphMappingAgreesWithSelectionAndCopying() {
    let layout = TextLayout("ab\n界e\u{301}", width: 8)
    let area = Rect(x: 2, y: 1, width: 8, height: 2)
    var paragraph = Paragraph(layout, alignment: .right)
    #expect(paragraph.contentPoint(at: Point(x: 8, y: 1), in: area) == Point(x: 0, y: 0))
    #expect(paragraph.contentPoint(at: Point(x: 9, y: 2), in: area) == Point(x: 2, y: 1))
    #expect(paragraph.contentPoint(at: Point(x: 2, y: 1), in: area) == nil)
    #expect(paragraph.viewportPoint(for: Point(x: 0, y: 1), in: area) == Point(x: 7, y: 2))
    paragraph.selection = TextSelection(anchor: Point(x: 0, y: 1), head: Point(x: 2, y: 1))
    var buffer = Buffer(width: 12, height: 4)
    paragraph.render(in: area, buffer: &buffer)
    #expect(buffer[7, 2].symbol == "界")
    #expect(buffer[8, 2].width == 0)
    #expect(buffer[9, 2].style.reversed)
    #expect(layout.selectedText(paragraph.selection!) == "界e\u{301}")
}

@Test func unwrappedParagraphScrollClipsWholeGraphemesAndMapsHits() {
    let layout = TextLayout("a界bc\nsecond", width: 3, wrapping: .none)
    #expect(layout.lines.count == 2)
    #expect(layout.lines[0].glyphs.map(\.column) == [0, 1, 3, 4])
    let area = Rect(x: 1, width: 3, height: 1)
    var paragraph = Paragraph(layout, horizontalScroll: 2, alignment: .right)
    var buffer = Buffer(width: 6, height: 1)
    paragraph.render(in: area, buffer: &buffer)
    #expect(buffer[1, 0].symbol == " ")
    #expect(buffer[2, 0].symbol == "b")
    #expect(buffer[3, 0].symbol == "c")
    #expect(paragraph.contentPoint(at: Point(x: 1, y: 0), in: area) == nil)
    let anchor = paragraph.contentPoint(at: Point(x: 2, y: 0), in: area)!
    let head = paragraph.contentPoint(at: Point(x: 3, y: 0), in: area)!
    paragraph.selection = TextSelection(anchor: anchor, head: head)
    #expect(layout.selectedText(paragraph.selection!) == "bc")
    paragraph.scroll = 1
    paragraph.horizontalScroll = 0
    #expect(paragraph.contentPoint(at: Point(x: 1, y: 0), in: area) == Point(x: 0, y: 1))
}

@Test func alignedParagraphClipsAgainstNestedBufferRegion() {
    var buffer = Buffer(width: 6, height: 1)
    buffer.put("界", width: 2, at: Point(x: 1, y: 0))
    buffer.withClip(Rect(x: 2, width: 3, height: 1)) { target in
        Paragraph(TextLayout("xyz", width: 3)).render(in: Rect(x: 2, width: 3, height: 1), buffer: &target)
    }
    #expect(buffer[1, 0].symbol == "界")
    #expect(buffer[2, 0].width == 0)
    #expect(buffer[3, 0].symbol == "y")
    #expect(buffer[4, 0].symbol == "z")
}
