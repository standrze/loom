import Foundation
import Testing

@testable import loom

@Test func markdownStylesCommonChatBlocksAndKeepsSafeLinks() {
    let palette = MarkdownPalette(
        body: Style(), heading: Style(bold: true), emphasis: Style(italic: true),
        strong: Style(bold: true), code: Style(background: .indexed(1)),
        quote: Style(foreground: .indexed(8)), link: Style(underlined: true))
    let spans = MarkdownText.spans(
        "# Heading\n- **Strong** and *soft*\n> quoted\n```swift\nlet n = 1\n```\n[site](https://example.com/path)",
        palette: palette)
    let visible = spans.map(\.text).joined()
    #expect(visible.contains("Heading\n• Strong and soft\n│ quoted\n│ let n = 1"))
    #expect(!visible.contains("```"))
    #expect(spans.first?.style?.bold == true)
    #expect(spans.first(where: { $0.text == "Strong" })?.style?.bold == true)
    #expect(spans.first(where: { $0.text == "soft" })?.style?.italic == true)
    #expect(spans.first(where: { $0.text == "let n = 1" })?.style?.background == .indexed(1))
    #expect(spans.first(where: { $0.text == "site" })?.link == "https://example.com/path")
}

@Test func markdownLeavesUnclosedMarkupLiteralAndRejectsUnsafeDestinations() {
    let spans = MarkdownText.spans("unfinished **bold and [unsafe](javascript:alert(1))")
    let visible = spans.map(\.text).joined()
    #expect(visible.contains("**bold"))
    #expect(visible.contains("[unsafe](javascript:alert(1))"))
    #expect(spans.allSatisfy { $0.link == nil })
}

@Test func markdownComposesNestedStylesAndPreservesBodyColors() throws {
    let palette = MarkdownPalette(body: Style(foreground: .indexed(3)))
    let spans = MarkdownText.spans("**strong and *soft***", palette: palette)
    #expect(spans.map(\.text).joined() == "strong and soft")
    let soft = try #require(spans.first { $0.text == "soft" })
    #expect(soft.style?.bold == true)
    #expect(soft.style?.italic == true)
    #expect(soft.style?.foreground == .indexed(3))
}

@Test func markdownUsesCommonMarkEscapesEntitiesAndDelimiterRules() {
    let spans = MarkdownText.spans(#"snake_case_name \*literal\* &amp; "quoted" ..."#)
    #expect(spans.map(\.text).joined() == #"snake_case_name *literal* & "quoted" ..."#)
    #expect(spans.allSatisfy { $0.style?.italic == false })
}

@Test func markdownJoinsSoftBreaksAndKeepsExplicitLineBreaks() {
    let text = "\nfirst\ncontinued\n\n\nsecond\n"
    #expect(MarkdownText.spans(text).map(\.text).joined() == "\nfirst continued\n\n\nsecond\n")
    #expect(MarkdownText.spans("line  \nbreak").map(\.text).joined() == "line\nbreak")
    #expect(MarkdownText.spans("line\\\nbreak").map(\.text).joined() == "line\nbreak")
    #expect(MarkdownText.spans("line\r\nbreak").map(\.text).joined() == "line break")
}

@Test func markdownRendersNestedListsAndTaskStates() {
    let text = "3. first\n   - child\n     continued\n4. second\n\n- [x] complete\n- [ ] pending"
    #expect(
        MarkdownText.spans(text).map(\.text).joined()
            == "3. first\n   • child continued\n4. second\n\n• [x] complete\n• [ ] pending")
    #expect(MarkdownText.spans("- first\n\n- second\n\n").map(\.text).joined() == "• first\n\n• second\n\n")
}

@Test func markdownRendersNestedQuotesAndUnfinishedFences() {
    let palette = MarkdownPalette(code: Style(background: .indexed(1)))
    let spans = MarkdownText.spans(
        "> outer\n> > inner\n\n~~~swift\nlet text = \"**literal**\"\n```\nstill code", palette: palette)
    #expect(
        spans.map(\.text).joined()
            == "│ outer\n│ │ inner\n\n│ let text = \"**literal**\"\n│ ```\n│ still code")
    #expect(spans.first { $0.text == "still code" }?.style?.background == .indexed(1))
    #expect(MarkdownText.spans("```swift\ncode\n\n").map(\.text).joined() == "│ code\n│ \n")
    #expect(
        MarkdownText.spans("before **unfinished [partial](https://example").map(\.text).joined()
            == "before **unfinished [partial](https://example")
}

@Test func markdownSupportsReferenceLinksAndNestedLinkStyles() throws {
    let spans = MarkdownText.spans("[**site**][docs] and <https://example.com>\n\n[docs]: https://example.com/docs")
    let site = try #require(spans.first { $0.text == "site" })
    #expect(site.style?.bold == true)
    #expect(site.style?.underlined == true)
    #expect(site.link == "https://example.com/docs")
    #expect(spans.first { $0.text == "https://example.com" }?.link == "https://example.com")
    #expect(!spans.map(\.text).joined().contains("[docs]:"))
}

@Test func markdownRetainsUnsupportedAndUnsafeMarkupAtUnicodeSourceOffsets() {
    let text = "日本 [unsafe](javascript:alert(1)) ![image](https://example.com/image) <kbd>key</kbd>"
    let spans = MarkdownText.spans(text)
    #expect(spans.map(\.text).joined() == text)
    #expect(spans.allSatisfy { $0.link == nil })

    let longDestination = "https://example.com/" + String(repeating: "x", count: 2048)
    let longLink = "[long](\(longDestination))"
    #expect(MarkdownText.spans(longLink).map(\.text).joined() == longLink)
    #expect(MarkdownText.spans(longLink).allSatisfy { $0.link == nil })
}

@Test func markdownKeepsUnsupportedBlocksAndStrikethroughAsLiteralSource() {
    for source in [
        "<div>\nraw **text**\n</div>",
        "| a | b |\n| - | - |\n| c | d |",
        "before ~~struck~~ after",
    ] {
        #expect(MarkdownText.spans(source).map(\.text).joined() == source)
    }
}

@Test func markdownLayoutRetainsUnicodeGeometryAndFiltersTerminalControls() {
    let spans = MarkdownText.spans("**日本** e\u{301} \u{1b}[2J [bad](https://example.com/\u{7})")
    let layout = TextLayout(spans, width: 8)
    #expect(layout.source.hasPrefix("日本 e\u{301}"))
    #expect(!layout.source.contains("\u{1b}"))
    #expect(!layout.source.contains("\u{7}"))
    #expect(layout.lines[0].glyphs.prefix(2).map(\.width) == [2, 2])
    #expect(layout.lines[0].glyphs.first { $0.text == "e\u{301}" }?.width == 1)
    #expect(spans.allSatisfy { $0.link == nil })
}

@Test func wordWrappingKeepsWordsTogetherAndCopiesOriginalSpacing() {
    let layout = TextLayout("hello world wideword", width: 8, wrapping: .word)
    #expect(layout.lines.count == 3)
    #expect(layout.lines[0].glyphs.map(\.text).joined() == "hello ")
    #expect(layout.lines[1].glyphs.map(\.text).joined() == "world ")
    let selection = TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 7, y: 2))
    #expect(layout.selectedText(selection) == "hello world wideword")
}

@Test func hyperlinksAreEmittedOnlyWhenEnabledAndAreClosed() throws {
    let layout = TextLayout([TextSpan("link", link: "https://example.com")], width: 10)
    var linked = Terminal(backend: MemoryBackend(), width: 10, height: 1, hyperlinks: true)
    try linked.draw { frame in frame.render(Paragraph(layout), in: frame.area) }
    let output = String(decoding: linked.backend.writes[0], as: UTF8.self)
    #expect(output.contains("\u{1b}]8;;https://example.com\u{1b}\\"))
    #expect(output.contains("\u{1b}]8;;\u{1b}\\"))

    var plain = Terminal(backend: MemoryBackend(), width: 10, height: 1, hyperlinks: false)
    try plain.draw { frame in frame.render(Paragraph(layout), in: frame.area) }
    #expect(!String(decoding: plain.backend.writes[0], as: UTF8.self).contains("\u{1b}]8;"))
}
