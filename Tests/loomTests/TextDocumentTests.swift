import Foundation
import Testing

@testable import loom

@Test func trailingReservationReflowsWithTheViewportWithoutChangingCopiedText() throws {
    var document = TextDocument(width: 20)
    let id = document.append("abcdefghijklmnopqrstuvwxyz", wrapping: .word)
    document.setTrailingReservedColumns(10, for: id)
    #expect(document.layouts[0].width == 10)
    #expect(document.layouts[0].lines.count == 3)
    #expect(document.spans(for: id)?.map(\.text).joined() == "abcdefghijklmnopqrstuvwxyz")
    document.resize(width: 30)
    #expect(document.layouts[0].width == 20)
    #expect(document.layouts[0].lines.count == 2)
    document.setWidthLimit(15, for: id)
    #expect(document.layouts[0].width == 15)
    document.setWidthLimit(nil, for: id)
    document.setTrailingReservedColumns(0, for: id)
    #expect(document.layouts[0].width == 30)
    #expect(document.layouts[0].lines.count == 1)
}

@Test func documentInsertionPreservesExistingEntriesAndUpdatesFollowingRows() throws {
    var document = TextDocument(width: 20)
    let prompt = document.append("prompt")
    let answer = document.append("answer", wrapping: .word)
    let footer = document.append("footer")
    let builds = document.layoutBuildCount
    let inserted = document.insert([TextSpan("first\nsecond")], before: answer, wrapping: .word)
    let reasoning = try #require(inserted)
    #expect(document.layoutBuildCount == builds + 1)
    #expect(document.row(for: prompt) == 0)
    #expect(document.row(for: reasoning) == 2)
    #expect(document.row(for: answer) == 5)
    #expect(document.row(for: footer) == 7)
    #expect(document.spans(for: answer)?.map(\.text).joined() == "answer")
    document.setCollapsed(true, for: reasoning, summary: [TextSpan("thinking")])
    #expect(document.row(for: answer) == 4)
    document.replace(answer, with: [TextSpan("answer changed")])
    document.resize(width: 8)
    #expect(document.entryID(at: try #require(document.row(for: answer))) == answer)
    #expect(document.isCollapsed(reasoning))
    #expect(document.wrapping(for: answer) == .word)
    let count = document.layouts.count
    let missing = document.insert([TextSpan("orphan")], before: TextDocumentEntryID(rawValue: -1))
    #expect(missing == nil)
    #expect(document.layouts.count == count)
}

@Test func hiddenEntryKeepsSourceAndFoldWhileRemovingItsRows() throws {
    var document = TextDocument(width: 12)
    let first = document.append("prompt")
    let thought = document.append("private thought")
    let answer = document.append("answer")
    document.setCollapsed(true, for: thought, summary: [TextSpan("Thinking")])
    #expect(document.row(for: answer) == 4)

    document.setHidden(true, for: thought)
    #expect(document.row(for: thought) == nil)
    #expect(document.row(for: answer) == 2)
    #expect(document.rowCount == 3)
    #expect(document.spans(for: thought)?.map(\.text).joined() == "private thought")
    #expect(document.find("private thought") == thought)
    #expect(
        document.selectedText(TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 12, y: 2))) == "prompt\n\nanswer")
    #expect(document.entryID(at: 2) == answer)
    var buffer = Buffer(width: 12, height: 3)
    document.paint(in: buffer.area, scroll: 0, selection: nil, buffer: &buffer)
    #expect(!buffer.plainText.contains("Thinking"))

    document.resize(width: 6)
    document.setHidden(false, for: thought)
    #expect(document.row(for: first) == 0)
    #expect(document.isCollapsed(thought))
    #expect(document.row(for: thought) == 2)
    #expect(document.spans(for: thought)?.map(\.text).joined() == "private thought")
}

@Test func cachedDocumentNeedsNoLayoutWorkForScrollingAndSelection() {
    var document = TextDocument(width: 20)
    for i in 0..<100 {
        document.append("Entry \(i)\n" + String(repeating: "word ", count: 10))
    }
    let builds = document.layoutBuildCount
    var buffer = Buffer(width: 20, height: 5)
    for row in 0..<50 {
        document.paint(
            in: buffer.area, scroll: row,
            selection: TextSelection(anchor: Point(x: 0, y: row), head: Point(x: 12, y: row + 1)), buffer: &buffer)
    }
    #expect(document.layoutBuildCount == builds)
    document.replaceLast("A streamed addition")
    #expect(document.layoutBuildCount == builds + 1)
    document.resize(width: 30)
    #expect(document.layoutBuildCount == builds + 101)
}

@Test func documentSelectionCrossesEntriesAndPaintClipsToViewport() {
    var document = TextDocument(width: 10)
    document.append("first")
    document.append("second")
    let selection = TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 9, y: 2))
    #expect(document.selectedText(selection) == "first\n\nsecond")
    var buffer = Buffer(width: 20, height: 8)
    document.paint(in: Rect(x: 2, y: 3, width: 10, height: 1), scroll: 2, selection: selection, buffer: &buffer)
    #expect(buffer[2, 3].symbol == "s")
    #expect(buffer[2, 3].style.reversed)
    #expect(buffer[2, 2].symbol == " " && buffer[2, 4].symbol == " ")
}

@Test func documentPreservesSpanStylesAndUnicodeCopyAcrossReflow() {
    let accent = Style(foreground: .rgb(35, 101, 209), bold: true)
    let spans = [TextSpan("界e\u{301}", style: accent), TextSpan(" tail")]
    var document = TextDocument(width: 20)
    document.append(spans)
    document.append("second")
    document.resize(width: 4)
    #expect(document.layouts[0].source == "界e\u{301} tail")
    #expect(document.layouts[0].lines[0].glyphs[0].style == accent)
    #expect(document.layouts[0].lines[0].glyphs[1].style == accent)
    let selection = TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 3, y: document.rowCount - 1))
    #expect(document.selectedText(selection) == "界e\u{301} tail\n\nsecond")
}

@Test func wordAndParagraphSelectionFollowSourceAcrossSoftWraps() throws {
    var document = TextDocument(width: 6)
    let id = document.append("αβ_code! next\nsecond line", wrapping: .word)
    let first = try #require(document.wordSelection(at: Point(x: 1, y: 0)))
    #expect(document.selectedText(first) == "αβ_code")
    let punctuation = try #require(document.wordSelection(at: Point(x: 1, y: 1)))
    #expect(document.selectedText(punctuation) == "!")
    let paragraph = try #require(document.paragraphSelection(at: Point(x: 1, y: 0)))
    #expect(document.selectedText(paragraph) == "αβ_code! next")
    #expect(paragraph.last.y > paragraph.first.y)
    #expect(document.wordSelection(at: Point(x: 5, y: 1)) == nil)
    #expect(document.entryID(at: paragraph.first.y) == id)
}

@Test func restylingDocumentPreservesFoldedSourceAndCodeMetadata() throws {
    let source = Style(foreground: .indexed(1), background: .indexed(2), bold: true)
    let block = TextCodeBlock(id: 7, language: "swift", code: "let value = 1")
    var document = TextDocument(width: 20)
    let first = document.append(
        [TextSpan("code", style: source, link: "https://example.com", codeBlock: block, isCodeBlockHeader: true)],
        background: .indexed(2))
    let second = document.append([TextSpan("reasoning", style: source)])
    document.setCollapsed(true, for: second, summary: [TextSpan("Thinking", style: source)])
    let builds = document.layoutBuildCount

    document.restyle(
        style: { old in
            var updated = old
            updated.foreground = .indexed(3)
            updated.background = .indexed(4)
            return updated
        }, background: { $0 == .indexed(2) ? .indexed(4) : $0 })

    #expect(document.layoutBuildCount == builds + 2)
    #expect(document.row(for: first) == 0)
    #expect(document.isCollapsed(second))
    #expect(document.layouts[1].source == "Thinking")
    #expect(document.layouts[1].lines[0].glyphs[0].style?.foreground == .indexed(3))
    let span = try #require(document.spans(for: first)?.first)
    #expect(span.text == "code")
    #expect(span.link == "https://example.com")
    #expect(span.codeBlock == block)
    #expect(span.isCodeBlockHeader)
    #expect(span.style?.bold == true)
    #expect(document.layouts[0].lines[0].glyphs[0].style?.background == .indexed(4))
    document.setCollapsed(false, for: second)
    #expect(document.layouts[1].source == "reasoning")
    #expect(document.layouts[1].lines[0].glyphs[0].style?.foreground == .indexed(3))
}

@Test func documentUpdatesChangedStylesAndCachesUnchangedSpans() {
    var document = TextDocument(width: 12)
    let plain = [TextSpan("same text")]
    document.replaceLast(plain)
    let initialBuilds = document.layoutBuildCount
    document.replaceLast(plain)
    #expect(document.layoutBuildCount == initialBuilds)
    let bold = [TextSpan("same text", style: Style(bold: true))]
    document.replaceLast(bold)
    #expect(document.layoutBuildCount == initialBuilds + 1)
    #expect(document.layouts[0].lines[0].glyphs[0].style?.bold == true)
    document.clear()
    document.append("fresh")
    document.resize(width: 3)
    #expect(document.layouts.count == 1)
    #expect(document.layouts[0].source == "fresh")
}

@Test func documentEntryBackgroundFillsVisibleRowsAndSurvivesReplacement() {
    let background = Color.rgb(246, 246, 246)
    var document = TextDocument(width: 10)
    document.append([TextSpan("first")], background: background)
    document.replaceLast([TextSpan("界ab cdef", style: Style(bold: true))])
    document.resize(width: 5)
    document.append("next")
    var buffer = Buffer(width: 8, height: 5)
    let selection = TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 1, y: 0))
    document.paint(in: Rect(x: 1, y: 1, width: 5, height: 4), scroll: 0, selection: selection, buffer: &buffer)
    #expect(buffer[1, 1].style.background == background)
    #expect(buffer[1, 1].style.bold)
    #expect(buffer[1, 1].style.reversed)
    #expect(buffer[5, 2].symbol == " ")
    #expect(buffer[5, 2].style.background == background)
    #expect(buffer[0, 1].style.background == .terminalDefault)
    #expect(buffer[6, 1].style.background == .terminalDefault)
    #expect(buffer[1, 3].style.background == .terminalDefault)
    #expect(buffer[1, 4].symbol == "n")
    let builds = document.layoutBuildCount
    document.paint(in: buffer.area, scroll: 1, selection: nil, buffer: &buffer)
    #expect(document.layoutBuildCount == builds)
}

@Test func documentIdentitySearchAndFoldingSurviveReflow() {
    var document = TextDocument(width: 12)
    let first = document.append("first entry")
    let second = document.append("second needle entry", wrapping: .word)
    let third = document.append("third entry")
    #expect(document.row(for: first) == 0)
    #expect(document.find("NEEDLE", after: 0) == second)
    let oldThirdRow = document.row(for: third)
    document.setCollapsed(true, for: second, summary: [TextSpan("▶ second")])
    #expect(document.isCollapsed(second))
    #expect(document.layouts[1].source == "▶ second")
    #expect(document.row(for: third)! < oldThirdRow!)
    #expect(document.find("needle", after: 0) == second)
    document.resize(width: 5)
    #expect(document.isCollapsed(second))
    #expect(document.row(for: second) != nil)
    document.setCollapsed(false, for: second)
    #expect(document.layouts[1].source == "second needle entry")
    document.replace(first, with: [TextSpan("updated")])
    #expect(document.row(for: first) == 0)
    #expect(document.layouts[0].source == "updated")
}

@Test func paddedEntriesPreserveExactSourceAndSelectionAfterReflow() throws {
    var document = TextDocument(width: 30)
    let source = "hello 世界\nsecond line"
    let id = document.append([TextSpan(source)], verticalPadding: 1)
    #expect(document.layouts[0].lines.count == 4)
    #expect(document.layouts[0].source == source)
    #expect(document.selectedText(TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 30, y: 4))) == source)
    document.setVerticalPadding(0, for: id)
    #expect(document.layouts[0].lines.count == 2)
    #expect(document.layouts[0].source == source)
    document.resize(width: 6)
    #expect(document.spans(for: id)?.map(\.text).joined() == source)
    #expect(
        document.selectedText(TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 30, y: document.rowCount)))
            == source)
}

@Test func tailPreviewPreservesSourceAndCopiesOnlyVisibleRows() throws {
    var document = TextDocument(width: 40)
    let source = " \nfirst\nsecond\nthird\nfourth"
    let id = document.append(source)
    document.setTailPreview(2, for: id, reservedHeaderRows: 1)
    #expect(document.layouts[0].lines.count == 4)
    #expect(document.spans(for: id)?.map(\.text).joined() == source)
    #expect(document.find("first") == id)
    let selection = TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 40, y: 3))
    #expect(document.selectedText(selection) == "third\nfourth")
    #expect(document.selectedText(TextSelection(anchor: Point(x: 0, y: 1), head: Point(x: 1, y: 1))).isEmpty)
    document.replace(id, with: [TextSpan(source + "\nfifth")])
    #expect(document.selectedText(selection) == "fourth\nfifth")
    document.resize(width: 3)
    #expect(document.layouts[0].lines.count == 4)
    #expect(document.layouts[0].source == source + "\nfifth")
    document.setTailPreview(nil, for: id)
    #expect(document.layouts[0].lines.count > 4)
    #expect(document.layouts[0].source == source + "\nfifth")
}

@Test func headPreviewKeepsThreeWrappedRowsAndRestoresFullSource() {
    var document = TextDocument(width: 20)
    let source = "first line\nsecond line\nthird line\nfourth line\nfifth line"
    let id = document.append([TextSpan(source)], wrapping: .word, verticalPadding: 1)
    document.setHeadPreview(3, for: id)
    #expect(document.layouts[0].lines.count == 5)
    #expect(document.layouts[0].lines[3].glyphs.last?.text == "…")
    #expect(document.spans(for: id)?.map(\.text).joined() == source)
    #expect(document.find("fifth line") == id)
    document.resize(width: 12)
    #expect(document.layouts[0].lines.count == 5)
    document.setHeadPreview(nil, for: id)
    #expect(document.layouts[0].lines.count > 5)
    #expect(document.layouts[0].source == source)
}
