import Testing
import loom

@Test func documentPreservesPatchesThroughPrefixesBackgroundRestylingAndReflow() throws {
    var document = TextDocument(width: 5)
    let patch = StylePatch(bold: false, dim: true)
    let id = document.append(
        [TextSpan("abcdef\ngh", style: Style(bold: true), patch: patch)], background: .indexed(4))
    document.setDisplayPrefix(TextSpan(">", patch: StylePatch(strikethrough: true)), continuation: " ", for: id)
    document.restyle(style: { $0.applying(StylePatch(foreground: .indexed(2))) }, background: { $0 })
    document.resize(width: 7)
    let layout = try #require(document.layouts.first)
    let glyphs = layout.lines.flatMap(\.glyphs)
    #expect(glyphs.filter(\.copyable).allSatisfy { $0.patch == patch })
    #expect(glyphs.filter { !$0.copyable }.allSatisfy { $0.patch?.strikethrough == true })
    var buffer = Buffer(width: 7, height: layout.lines.count)
    layout.paint(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].style.strikethrough)
    #expect(buffer[1, 0].style.dim && !buffer[1, 0].style.bold)
    #expect(buffer[1, 0].style.background == .indexed(4))
    #expect(
        layout.selectedText(TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 6, y: layout.lines.count - 1)))
            == "abcdef\ngh")
}

@Test func markdownHighlighterPatchesSurviveLineSplittingAndCodePanels() {
    for header in [Style?.none, Style?.some(Style(bold: true))] {
        let palette = MarkdownPalette(
            body: Style(foreground: .indexed(4)), code: Style(dim: true), codeBlockHeader: header,
            codeHighlighter: { code, _ in [TextSpan(code, patch: StylePatch(strikethrough: true))] })
        let spans = MarkdownText.spans("```swift\nalpha\nbeta\n```", palette: palette)
        let content = spans.filter { $0.text.contains("alpha") || $0.text.contains("beta") }
        #expect(content.count == 2)
        #expect(content.allSatisfy { $0.patch?.strikethrough == true })
        let layout = TextLayout(spans, width: 20)
        var buffer = Buffer(width: 20, height: layout.lines.count)
        layout.paint(in: buffer.area, buffer: &buffer)
        let row = header == nil ? 0 : 1
        #expect(buffer[2, row].style.strikethrough)
        #expect(buffer[2, row].style.dim)
    }
}
