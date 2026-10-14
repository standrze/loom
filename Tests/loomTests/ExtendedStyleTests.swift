import Foundation
import Testing
import loom

@Test func extendedStylePatchesInheritAndExplicitlyReset() {
    let base = Style(underlined: true, underlineColor: .rgb(10, 20, 30), hidden: true, blink: .rapid)
    #expect(base.applying(StylePatch()) == base)
    let patch = StylePatch(underlineColor: .terminalDefault, hidden: false, blink: Blink.none)
    let result = base.applying(patch)
    #expect(result.underlined)
    #expect(result.underlineColor == .terminalDefault)
    #expect(!result.hidden && result.blink == .none)
    let first = StylePatch(underlineColor: .indexed(6), hidden: true, blink: .slow)
    #expect(base.applying(first.applying(patch)) == base.applying(first).applying(patch))
}

@Test func underlineHiddenAndBlinkEncodeAndResetWithoutChangingText() {
    var buffer = Buffer(width: 2, height: 1)
    let appearance = Style(underlined: true, underlineColor: .rgb(1, 2, 3), hidden: true, blink: .rapid)
    buffer.put("界", width: 2, at: Point(x: 0, y: 0), style: appearance)
    var diff = CellDiff(synchronizedOutput: false)
    let (bytes, _) = diff.encode(buffer, previous: nil, cursor: nil)
    let output = String(decoding: bytes, as: UTF8.self)
    #expect(output.contains("\u{1b}[0;4;8;6;58;2;1;2;3m界"))
    #expect(buffer.plainText == "界")
    let (silent, _) = diff.encode(buffer, previous: buffer, cursor: nil)
    #expect(silent.isEmpty)
    let previous = buffer
    buffer.put("界", width: 2, at: Point(x: 0, y: 0))
    let (reset, _) = diff.encode(buffer, previous: previous, cursor: nil)
    #expect(String(decoding: reset, as: UTF8.self).contains("\u{1b}[0m界"))
}

@Test func underlineColorDowngradesAndMonochromeSuppressesIt() {
    var buffer = Buffer(width: 1, height: 1)
    buffer.put("x", width: 1, at: Point(x: 0, y: 0), style: Style(underlineColor: .rgb(255, 0, 0), blink: .slow))
    var palette = CellDiff(synchronizedOutput: false, colorDepth: .ansi16)
    let (indexed, _) = palette.encode(buffer, previous: nil, cursor: nil)
    #expect(String(decoding: indexed, as: UTF8.self).contains("58;5;9"))
    var mono = CellDiff(synchronizedOutput: false, colorDepth: .monochrome)
    let (plain, _) = mono.encode(buffer, previous: nil, cursor: nil)
    #expect(!String(decoding: plain, as: UTF8.self).contains("58;"))
    #expect(String(decoding: plain, as: UTF8.self).contains("0;5m"))
}

@Test func extendedStyleSurvivesCollectionOverlayAndSpanPatches() {
    var list = List([ListItem(id: 1, spans: [TextSpan("a", patch: StylePatch(hidden: false))])])
    list.style = Style(underlineColor: .indexed(3), hidden: true, blink: .slow)
    var state = SelectionState<Int>(selectedID: 1)
    var buffer = Buffer(width: 2, height: 1)
    list.render(in: buffer.area, buffer: &buffer, state: &state)
    #expect(buffer[0, 0].style.underlineColor == .indexed(3))
    #expect(buffer[0, 0].style.blink == .slow)
    #expect(!buffer[0, 0].style.hidden)
    #expect(buffer[0, 0].style.reversed)
}

@Test func underlineColorExplicitlyResetsBetweenAdjacentCells() {
    var buffer = Buffer(width: 2, height: 1)
    buffer.put("a", width: 1, at: Point(x: 0, y: 0), style: Style(underlineColor: .indexed(2)))
    buffer.put("b", width: 1, at: Point(x: 1, y: 0))
    var diff = CellDiff(synchronizedOutput: false)
    let (bytes, _) = diff.encode(buffer, previous: nil, cursor: nil)
    #expect(String(decoding: bytes, as: UTF8.self).contains("\u{1b}[0;59mb"))
}

private struct PublicSemanticBackend: RenderBackend {
    mutating func render(_ update: RenderUpdate) throws -> RenderStats {
        RenderStats(changedCells: 0, bytes: 0)
    }
}

@Test func semanticBackendCanConformUsingOnlyPublicAPI() throws {
    var terminal = RenderTerminal(backend: PublicSemanticBackend(), width: 2, height: 1)
    let stats = try terminal.draw { _ in }
    #expect(stats.bytes == 0)
    #expect(terminal.snapshot?.buffer.width == 2)
}
