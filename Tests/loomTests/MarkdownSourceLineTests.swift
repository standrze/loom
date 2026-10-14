import Testing

@testable import loom

@Test func markdownSourceLocationsSurviveStylesCodeTokensAndContainers() {
    var palette = MarkdownPalette(codeBlockPrefix: "")
    palette.preservesSoftBreaks = true
    palette.codeHighlighter = { code, _ in code.map { TextSpan(String($0), style: Style(bold: true)) } }
    let source = "# Héading\n\n> first **bold**\n> second\n\n```swift\nlet café = 1\nprint(café)\n```\n\n- task"
    let spans = MarkdownText.spans(source, palette: palette)
    #expect(spans.first { $0.text == "Héading" }?.sourceLine == 1)
    #expect(spans.first { $0.text == "bold" }?.sourceLine == 3)
    #expect(spans.first { $0.text == "second" }?.sourceLine == 4)
    let code = spans.filter { $0.style?.bold == true && $0.text.count == 1 }
    #expect(code.first { $0.text == "l" }?.sourceLine == 7)
    #expect(code.first { $0.text == "p" }?.sourceLine == 8)
    #expect(spans.first { $0.text == "task" }?.sourceLine == 11)
    #expect(spans.filter { $0.text == "│ " || $0.text == "• " }.allSatisfy { $0.sourceLine == nil })
}

@Test func markdownSourceLocationsPreserveSoftBreaksAndBlankLines() {
    var palette = MarkdownPalette()
    palette.preservesSoftBreaks = true
    let spans = MarkdownText.spans("\nTitle\n=====\n\nfirst\nsecond\n\n\nlast\n", palette: palette)
    #expect(spans.first?.sourceLine == 1)
    #expect(spans.first { $0.text == "Title" }?.sourceLine == 2)
    #expect(spans.first { $0.text == "second" }?.sourceLine == 6)
    #expect(spans.first { $0.text == "last" }?.sourceLine == 9)
    #expect(spans.contains { $0.text.isEmpty && $0.sourceLine == 7 })
    #expect(spans.contains { $0.text.isEmpty && $0.sourceLine == 8 })
}
