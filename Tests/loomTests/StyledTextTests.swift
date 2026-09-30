import Foundation
import Testing

@testable import loom

@Test func styledSpansKeepSourceSelectionAndWrapTogether() {
    let accent = Style(foreground: .rgb(30, 80, 120), bold: true)
    let layout = TextLayout(
        [TextSpan("ab", style: accent), TextSpan("界", style: Style(underlined: true)), TextSpan("e\u{301}z")],
        width: 4
    )
    #expect(layout.source == "ab界e\u{301}z")
    #expect(layout.lines.count == 2)
    #expect(layout.lines[0].glyphs.map(\.column) == [0, 1, 2])
    #expect(layout.lines[1].glyphs.map(\.column) == [0, 1])
    #expect(layout.lines[0].glyphs[0].style == accent)
    #expect(layout.lines[0].glyphs[2].style == Style(underlined: true))
    let selection = TextSelection(anchor: Point(x: 1, y: 0), head: Point(x: 0, y: 1))
    #expect(layout.selectedText(selection) == "b界e\u{301}")

    var buffer = Buffer(width: 4, height: 2)
    layout.paint(in: buffer.area, style: Style(italic: true), buffer: &buffer)
    #expect(buffer[0, 0].style == accent)
    #expect(buffer[2, 0].style == Style(underlined: true))
    #expect(buffer[0, 1].style == Style(italic: true))
}

@Test func stylesEncodeToAnsiWithoutChangingPlainText() throws {
    var terminal = Terminal(backend: MemoryBackend(), width: 15, height: 2, synchronizedOutput: false)
    let layout = TextLayout(
        [
            TextSpan(
                "RGB",
                style: Style(foreground: .rgb(1, 2, 3), background: .rgb(4, 5, 6), italic: true, underlined: true))
        ],
        width: 15
    )
    _ = try terminal.draw { frame in
        frame.render(Paragraph(layout), in: frame.area)
    }
    let output = String(decoding: terminal.backend.writes[0], as: UTF8.self)
    #expect(output.contains("\u{1b}[0;3;4;38;2;1;2;3;48;2;4;5;6mRGB"))
    #expect(!output.contains("\u{1b}[?2026h"))
    #expect(layout.source == "RGB")
}

@Test func cellRepaintHidesCursorAndRestoresItAfterDrawing() throws {
    var terminal = Terminal(backend: MemoryBackend(), width: 8, height: 2, synchronizedOutput: false)
    _ = try terminal.draw { frame in
        frame.render(Paragraph(TextLayout("before", width: 8)), in: frame.area)
        frame.cursor = Point(x: 3, y: 1)
    }
    _ = try terminal.draw { frame in
        frame.render(Paragraph(TextLayout("AFTER", width: 8)), in: frame.area)
        frame.cursor = Point(x: 3, y: 1)
    }
    let output = String(decoding: terminal.backend.writes[1], as: UTF8.self)
    let hide = try #require(output.range(of: "\u{1b}[?25l"))
    let text = try #require(output.range(of: "AFTER"))
    let move = try #require(output.range(of: "\u{1b}[2;4H"))
    let show = try #require(output.range(of: "\u{1b}[?25h"))
    #expect(hide.lowerBound < text.lowerBound)
    #expect(text.upperBound < move.lowerBound)
    #expect(move.upperBound <= show.lowerBound)
    #expect(
        try terminal.draw { frame in
            frame.render(Paragraph(TextLayout("AFTER", width: 8)), in: frame.area)
            frame.cursor = Point(x: 3, y: 1)
        }.bytes == 0)
}
