import Testing

@testable import loom

private let codePanelStyle = Style(foreground: .indexed(3), background: .indexed(1))
private let codeHeaderStyle = Style(foreground: .indexed(11), background: .indexed(2))
private let codePanelPalette = MarkdownPalette(code: codePanelStyle, codeBlockHeader: codeHeaderStyle)

@Test func markdownThematicBreakUsesThinRule() {
    let spans = MarkdownText.spans("before\n\n---\n\nafter", palette: codePanelPalette)
    #expect(spans.map(\.text).joined() == "before\n\n───\n\nafter")
}

@Test func codePanelsKeepCopyPayloadSeparateFromPresentation() throws {
    let code = "\tlet 日本 = \"e\u{301}\"\n    next()\n\n"
    let spans = MarkdownText.spans("```swift\n" + code + "```", palette: codePanelPalette)
    let header = try #require(spans.first { $0.isCodeBlockHeader })
    let block = try #require(header.codeBlock)
    #expect(block.language == "swift")
    #expect(block.code == code)
    #expect(header.text == " ")
    #expect(spans.filter(\.isCodeBlockHeader).count == 1)
    #expect(!spans.map(\.text).joined().contains("```"))
    #expect(spans.filter { $0.codeBlock != nil }.allSatisfy { $0.codeBlock == block })
}

@Test func streamingCodePanelsCopyOnlyReceivedContentAndKeepStableIdentity() throws {
    let partial = MarkdownText.spans("before\n\n~~~swift\n\tvalue", palette: codePanelPalette)
    let growing = MarkdownText.spans("before\n\n~~~swift\n\tvalue()\n", palette: codePanelPalette)
    let closed = MarkdownText.spans("before\n\n~~~swift\n\tvalue()\n~~~", palette: codePanelPalette)
    let partialBlock = try #require(partial.first(where: \.isCodeBlockHeader)?.codeBlock)
    let growingBlock = try #require(growing.first(where: \.isCodeBlockHeader)?.codeBlock)
    let closedBlock = try #require(closed.first(where: \.isCodeBlockHeader)?.codeBlock)
    #expect(partialBlock.code == "\tvalue")
    #expect(growingBlock.code == "\tvalue()\n")
    #expect(closedBlock.code == "\tvalue()\n")
    #expect(partialBlock.id == growingBlock.id)
    #expect(partialBlock.id == closedBlock.id)
}

@Test func codePanelsHandleEmptyIndentedAndDistinctBlocks() throws {
    let empty = MarkdownText.spans("```swift\n```", palette: codePanelPalette)
    #expect(empty.filter(\.isCodeBlockHeader).count == 1)
    #expect(empty.first?.codeBlock?.code == "")

    let indented = MarkdownText.spans("    let n = 1", palette: codePanelPalette)
    #expect(indented.first?.codeBlock?.code == "let n = 1")

    let distinct = MarkdownText.spans("```\nsame\n```\n\n```\nsame\n```", palette: codePanelPalette)
    let blocks = distinct.filter(\.isCodeBlockHeader).compactMap(\.codeBlock)
    #expect(blocks.count == 2)
    #expect(blocks[0].id != blocks[1].id)
    #expect(blocks[0].code == blocks[1].code)
}

@Test func nestedCodePanelsHaveOneHeaderAtEveryWidth() throws {
    let spans = MarkdownText.spans("> - ```swift\n>   日本()\n>   ```", palette: codePanelPalette)
    let block = try #require(spans.first(where: \.isCodeBlockHeader)?.codeBlock)
    #expect(block.code == "日本()\n")
    for width in [1, 4, 20] {
        let layout = TextLayout(spans, width: width)
        #expect(layout.lines.filter(\.isCodeBlockHeader).count == 1)
        #expect(layout.lines.allSatisfy { $0.codeBlock == block })
    }
}

@Test func indentedCodeKeepsRealNewlinesBeforeTrailingBlankSourceLines() {
    for source in ["    code\n    ", ">     code\n>     "] {
        let spans = MarkdownText.spans(source, palette: codePanelPalette)
        #expect(spans.first { $0.isCodeBlockHeader }?.codeBlock?.code == "code\n")
    }
    let unfinished = MarkdownText.spans("    code\n    second", palette: codePanelPalette)
    #expect(unfinished.first { $0.isCodeBlockHeader }?.codeBlock?.code == "code\nsecond")
}

@Test func codePanelsShadePaddingBlankRowsAndSoftWrappedRows() throws {
    let spans = MarkdownText.spans("```\n12345678\n\nx\n```", palette: codePanelPalette)
    let layout = TextLayout(spans, width: 5)
    #expect(layout.lines.count == 5)
    #expect(layout.lines.allSatisfy { $0.codeBlock != nil })
    #expect(layout.lines.first?.isCodeBlockHeader == true)
    #expect(layout.lines.dropFirst().allSatisfy { !$0.isCodeBlockHeader })
    var buffer = Buffer(width: 7, height: 7)
    layout.paint(in: Rect(x: 1, y: 1, width: 5, height: 5), buffer: &buffer)
    for row in 0..<layout.lines.count {
        let expected = row == 0 ? codeHeaderStyle.background : codePanelStyle.background
        for column in 1...5 {
            #expect(buffer[column, row + 1].style.background == expected)
        }
    }
    #expect(buffer[0, 1].style.background == .terminalDefault)
    #expect(buffer[6, 1].style.background == .terminalDefault)

    var scrolled = Buffer(width: 5, height: 2)
    layout.paint(in: Rect(width: 5, height: 2), rowOffset: 3, buffer: &scrolled)
    #expect(scrolled[4, 0].style.background == codePanelStyle.background)
    #expect(scrolled[4, 1].style.background == codePanelStyle.background)
}

@Test func documentRetainsCodeMetadataWhenReflowingAndReplacingPayload() throws {
    var document = TextDocument(width: 12)
    let original = TextCodeBlock(id: 0, language: "swift", code: "one")
    let replacement = TextCodeBlock(id: 0, language: "swift", code: "two")
    let entry = document.append(
        [TextSpan(" ", codeBlock: original, isCodeBlockHeader: true)], background: .indexed(1))
    #expect(document.layouts[0].lines[0].codeBlock == original)
    document.replace(entry, with: [TextSpan(" ", codeBlock: replacement, isCodeBlockHeader: true)])
    #expect(document.layouts[0].lines[0].codeBlock == replacement)
    document.resize(width: 1)
    #expect(document.layouts[0].lines[0].isCodeBlockHeader)
    #expect(document.layouts[0].lines[0].codeBlock == replacement)
    document.setCollapsed(true, for: entry)
    #expect(document.layouts[0].lines.allSatisfy { $0.codeBlock == nil })
    document.setCollapsed(false, for: entry)
    #expect(document.layouts[0].lines[0].codeBlock == replacement)
}

@Test func inlineCodeKeepsItsExistingRenderingInsidePanelPalette() {
    let spans = MarkdownText.spans("Use `inline()` here.", palette: codePanelPalette)
    #expect(spans.map(\.text).joined() == "Use inline() here.")
    #expect(spans.allSatisfy { $0.codeBlock == nil && !$0.isCodeBlockHeader })
    #expect(spans.first { $0.text == "inline()" }?.style == codePanelStyle)
}

@Test func compactCodeSummariesReserveThreeCanvasRowsAndRetainLongCode() throws {
    let body = Style(foreground: .indexed(7), background: .indexed(0))
    let palette = MarkdownPalette(
        body: body, code: codePanelStyle, codeBlockHeader: codeHeaderStyle, compactCodeBlocks: true)
    let code = (0..<120).map { "\tlet 日本\($0) = \"e\u{301}\"\n" }.joined()
    let spans = MarkdownText.spans("```swift\n" + code + "```", palette: palette)
    #expect(spans.map(\.text).joined() == " \n \n ")
    let block = try #require(spans.first { $0.isCodeBlockHeader }?.codeBlock)
    #expect(block.isCompact)
    #expect(block.language == "swift")
    #expect(block.code == code)
    for width in [1, 8, 80] {
        let layout = TextLayout(spans, width: width)
        #expect(layout.lines.count == 3)
        #expect(layout.lines.map(\.isCodeBlockHeader) == [false, true, false])
        #expect(layout.lines.allSatisfy { $0.codeBlock == block && $0.codeBlockStyle == body })
        var buffer = Buffer(width: width, height: 3)
        layout.paint(in: Rect(width: width, height: 3), buffer: &buffer)
        for row in 0..<3 {
            #expect(buffer[width - 1, row].style.background == body.background)
        }
    }
}

@Test func compactCodeSummariesKeepRawStreamingContentWithoutChangingHeight() throws {
    let palette = MarkdownPalette(codeBlockHeader: codeHeaderStyle, compactCodeBlocks: true)
    let partialCode = "\tprint(\"界\")"
    let finishedCode = partialCode + "\n\nnext()\n"
    let fixtures = [
        ("~~~swift", ""),
        ("~~~swift\n" + partialCode, partialCode),
        ("~~~swift\n" + finishedCode + "~~~", finishedCode),
    ]
    var previousID: Int?
    for (source, expected) in fixtures {
        let spans = MarkdownText.spans(source, palette: palette)
        let block = try #require(spans.first { $0.isCodeBlockHeader }?.codeBlock)
        #expect(block.code == expected)
        #expect(block.isCompact)
        if let previousID { #expect(block.id == previousID) }
        previousID = block.id
        let layout = TextLayout(spans, width: 1)
        #expect(layout.lines.count == 3)
        #expect(layout.lines.filter(\.isCodeBlockHeader).count == 1)
    }
}

@Test func compactCodeSummariesSuppressNestedContainerPrefixesAtNarrowWidths() throws {
    let palette = MarkdownPalette(codeBlockHeader: codeHeaderStyle, compactCodeBlocks: true)
    let spans = MarkdownText.spans("> - ```swift\n>   日本()\n>   ```", palette: palette)
    #expect(spans.map(\.text).joined() == " \n \n ")
    let block = try #require(spans.first { $0.isCodeBlockHeader }?.codeBlock)
    #expect(block.code == "日本()\n")
    for width in [1, 4, 80] {
        let layout = TextLayout(spans, width: width)
        #expect(layout.lines.count == 3)
        #expect(layout.lines.allSatisfy { $0.codeBlock == block })
        #expect(layout.lines.map(\.isCodeBlockHeader) == [false, true, false])
    }
}

@Test func compactCodeSummariesRequireExplicitHeaderOptIn() {
    let palette = MarkdownPalette(compactCodeBlocks: true)
    let spans = MarkdownText.spans("```swift\ncode\n```", palette: palette)
    #expect(spans.map(\.text).joined() == "│ code")
    #expect(spans.allSatisfy { $0.codeBlock == nil })
    #expect(!TextCodeBlock(id: 0, code: "code").isCompact)
}
