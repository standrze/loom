import Foundation
import Testing

@testable import loom

@Test func selectionAndPaintAgreeOnSecondHalfOfWideGrapheme() {
    let layout = TextLayout("A中e\u{301} 👩🏽‍💻 🇵🇱Z", width: 30)
    let selection = TextSelection(anchor: Point(x: 2, y: 0), head: Point(x: 2, y: 0))
    #expect(layout.selectedText(selection) == "中")
    var buffer = Buffer(width: 30, height: 1)
    layout.paint(in: buffer.area, selection: selection, buffer: &buffer)
    #expect(buffer[1, 0].symbol == "中")
    #expect(buffer[1, 0].style.reversed && buffer[2, 0].style.reversed)
    #expect(!buffer[0, 0].style.reversed && !buffer[3, 0].style.reversed)
    #expect(terminalCellWidth("👩🏽‍💻") == 2)
    #expect(terminalCellWidth("🇵🇱") == 2)
    #expect(terminalCellWidth("e\u{301}") == 1)
}

@Test func softWrapCopyKeepsOriginalWhitespaceAndExplicitLines() {
    let text = "abcdef ghijkl\n\n\t中 café 👩🏽‍💻"
    let layout = TextLayout(text, width: 7)
    let forward = TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 6, y: layout.lines.count - 1))
    let backward = TextSelection(anchor: forward.head, head: forward.anchor)
    #expect(layout.selectedText(forward) == text)
    #expect(layout.selectedText(backward) == text)
    #expect(layout.lines.count > text.split(separator: "\n", omittingEmptySubsequences: false).count)
}
