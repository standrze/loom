import Testing
import loom

@Test func lineAlignmentsOverrideParagraphWithoutChangingCopyGeometry() throws {
    let layout = TextLayout(
        lines: [
            TextLine("界e\u{301}", alignment: .right),
            TextLine("xy"),
            TextLine("abcdef", alignment: .center),
        ], width: 4)
    let area = Rect(x: 2, y: 1, width: 8, height: 4)
    var paragraph = Paragraph(layout, alignment: .left)
    var buffer = Buffer(width: 12, height: 6)
    paragraph.render(in: area, buffer: &buffer)
    #expect(buffer[7, 1].symbol == "界")
    #expect(buffer[9, 1].symbol == "e\u{301}")
    #expect(buffer[2, 2].symbol == "x")
    #expect(buffer[4, 3].symbol == "a")
    #expect(buffer[5, 4].symbol == "e")
    #expect(paragraph.contentPoint(at: Point(x: 6, y: 1), in: area) == nil)
    for (row, line) in layout.lines.enumerated() {
        for glyph in line.glyphs {
            for column in glyph.column..<glyph.column + glyph.width {
                let content = Point(x: column, y: row)
                let viewport = try #require(paragraph.viewportPoint(for: content, in: area))
                #expect(paragraph.contentPoint(at: viewport, in: area) == content)
            }
        }
    }
    paragraph.selection = TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 1, y: 3))
    #expect(layout.selectedText(paragraph.selection!) == "界e\u{301}\nxy\nabcdef")
    paragraph.render(in: area, buffer: &buffer)
    #expect(buffer[7, 1].style.reversed && buffer[8, 1].style.reversed)
    #expect(buffer[5, 4].style.reversed)
}

@Test func explicitAndSoftLineAlignmentSurvivesTransformsAndScroll() {
    let layout = TextLayout(
        lines: [
            TextLine([TextSpan("abcd\nef", style: Style(bold: true))], alignment: .right),
            TextLine(""), TextLine("界z", alignment: .center),
        ], width: 3)
    #expect(layout.lines.map(\.alignment) == [.right, .right, .right, nil, .center])
    let padded = layout.paddedVertically(1)
    #expect(padded.lines[2].alignment == .right)
    let preview = layout.headPreview(rows: 2)
    #expect(preview.lines.first?.alignment == .right)
    let area = Rect(x: 1, width: 4, height: 2)
    let paragraph = Paragraph(layout, scroll: 1, horizontalScroll: 0, alignment: .left)
    var buffer = Buffer(width: 6, height: 2)
    paragraph.render(in: area, buffer: &buffer)
    #expect(buffer[4, 0].symbol == "d")
    #expect(buffer[3, 1].symbol == "e")
    #expect(paragraph.contentPoint(at: Point(x: 4, y: 0), in: area) == Point(x: 0, y: 1))
    #expect(paragraph.contentPoint(at: Point(x: 1, y: 1), in: area) == nil)
}

@Test func optionalLogicalLineAlignmentPreservesDefaultsAndClipsWholeGlyphs() {
    let layout = TextLayout("a\n界b\nz", width: 3, lineAlignments: [.right, .center])
    #expect(layout.horizontalOrigin(forRow: 0, viewportWidth: 5) == 4)
    #expect(layout.horizontalOrigin(forRow: 1, viewportWidth: 5) == 1)
    #expect(layout.horizontalOrigin(forRow: 2, viewportWidth: 5, alignment: .center) == 2)
    var buffer = Buffer(width: 3, height: 1)
    let paragraph = Paragraph(TextLayout(lines: [TextLine("界b", alignment: .right)], width: 3), horizontalScroll: 1)
    paragraph.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == " ")
    #expect(buffer[1, 0].symbol == "b")
    #expect(paragraph.contentPoint(at: Point(x: 0, y: 0), in: buffer.area) == nil)
    #expect(paragraph.contentPoint(at: Point(x: 1, y: 0), in: buffer.area) == Point(x: 2, y: 0))
    #expect(TextLayout("ab", width: 5).horizontalOrigin(forRow: 0, viewportWidth: 5) == 0)
}
