import Foundation
import Testing

@testable import loom

@Test func unchangedFrameEmitsNothingAndCursorOnlyChangesAreSmall() throws {
    var terminal = Terminal(backend: MemoryBackend(), width: 20, height: 4)
    let paragraph = Paragraph(TextLayout("Hello, 世界", width: 20))

    func render(_ frame: inout Frame) {
        frame.render(paragraph, in: frame.area)
        frame.cursor = Point(x: 0, y: 3)
    }
    let first = try terminal.draw(render)
    #expect(first.bytes > 0)
    let same = try terminal.draw(render)
    #expect(same.bytes == 0)
    #expect(same.changedCells == 0)
    #expect(terminal.backend.writes.count == 1)
    let cursor = try terminal.draw {
        frame in
        render(&frame)
        frame.cursor = Point(x: 1, y: 3)
    }
    #expect(cursor.changedCells == 0)
    #expect(cursor.bytes < first.bytes)
    terminal.resize(width: 30, height: 6)
    #expect(try terminal.draw(render).bytes > 0)
}

@Test func selectionDiffChangesStylesWithoutReprintingWholeFrame() throws {
    var terminal = Terminal(backend: MemoryBackend(), width: 80, height: 24)
    let layout = TextLayout(String(repeating: "abcdefghij", count: 80), width: 80)
    let first = try terminal.draw {
        frame in frame.render(Paragraph(layout), in: frame.area)
    }
    let selection = TextSelection(anchor: Point(x: 2, y: 0), head: Point(x: 5, y: 0))
    let highlighted = try terminal.draw {
        frame in frame.render(Paragraph(layout, selection: selection), in: frame.area)
    }
    #expect(highlighted.changedCells == 4)
    #expect(highlighted.bytes < first.bytes / 5)
}

@Test func fullRepaintLeavesClearedBlankCellsUntouched() throws {
    var terminal = Terminal(backend: MemoryBackend(), width: 120, height: 40)
    let stats = try terminal.draw { frame in
        frame.render(Paragraph(TextLayout("Top", width: 120)), in: frame.area)
    }
    let output = String(decoding: terminal.backend.writes[0], as: UTF8.self)
    #expect(output.contains("\u{1b}[2J"))
    #expect(output.contains("Top"))
    #expect(stats.changedCells == 3)
    #expect(stats.bytes < 200)
}

@Test func colorDepthFallsBackWithoutChangingVisibleCells() throws {
    let style = Style(foreground: .rgb(242, 187, 91), background: .rgb(16, 14, 10))
    let paragraph = Paragraph(TextLayout([TextSpan("amber", style: style)], width: 10))
    var limited = Terminal(
        backend: MemoryBackend(), width: 10, height: 1,
        synchronizedOutput: false, colorDepth: .ansi16)
    try limited.draw { frame in frame.render(paragraph, in: frame.area) }
    let limitedOutput = String(decoding: limited.backend.writes[0], as: UTF8.self)
    #expect(!limitedOutput.contains("38;2;") && !limitedOutput.contains("48;2;"))
    #expect(!limitedOutput.contains("?2026h"))
    #expect(limitedOutput.contains("amber"))

    var monochrome = Terminal(
        backend: MemoryBackend(), width: 10, height: 1,
        synchronizedOutput: false, colorDepth: .monochrome)
    try monochrome.draw { frame in frame.render(paragraph, in: frame.area) }
    let plainOutput = String(decoding: monochrome.backend.writes[0], as: UTF8.self)
    #expect(!plainOutput.contains("38;") && !plainOutput.contains("48;"))
    #expect(plainOutput.contains("amber"))
}

@Test func invalidationClearsUntrackedNativeOutputAndRestoresCursor() throws {
    var terminal = Terminal(backend: MemoryBackend(), width: 20, height: 4)
    func render(_ frame: inout Frame) {
        frame.render(Paragraph(TextLayout("prompt", width: 20)), in: frame.area)
        frame.cursor = Point(x: 6, y: 0)
    }
    try terminal.draw(render)
    #expect(try terminal.draw(render).bytes == 0)
    terminal.invalidate()
    #expect(try terminal.draw(render).bytes > 0)
    let repaint = String(decoding: terminal.backend.writes.last!, as: UTF8.self)
    #expect(repaint.contains("\u{1b}[2J"))
    #expect(repaint.contains("prompt"))
    #expect(try terminal.draw(render).bytes == 0)
}
