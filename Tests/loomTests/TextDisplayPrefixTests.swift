import Testing

@testable import loom

@Test(arguments: [TextWrapping.word, .grapheme])
func displayPrefixUsesBlankContinuationForSoftWrapAndExplicitNewline(wrapping: TextWrapping) {
    let source = "one two three four five\nsecond explicit line"
    var document = TextDocument(width: 12)
    let id = document.append(source, wrapping: wrapping)
    document.setDisplayPrefix(TextSpan("❯ "), continuation: "  ", for: id)

    for width in [12, 18, 8] {
        document.resize(width: width)
        let layout = document.layouts[0]
        let rows = layout.lines.map { $0.glyphs.map(\.text).joined() }
        #expect(rows.count > 2)
        #expect(rows[0].hasPrefix("❯ "))
        #expect(rows.dropFirst().allSatisfy { $0.hasPrefix("  ") && !$0.contains("❯") })
        let selection = TextSelection(
            anchor: Point(x: 0, y: 0), head: Point(x: width - 1, y: layout.lines.count - 1))
        #expect(document.selectedText(selection) == source)
    }
}
