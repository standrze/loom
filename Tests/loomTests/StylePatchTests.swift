import Foundation
import Testing
import loom

@Test func stylePatchesInheritResetAndDisableAttributes() {
    let base = Style(
        foreground: .indexed(4), background: .rgb(1, 2, 3), bold: true,
        italic: true, underlined: true, reversed: true, dim: true, strikethrough: true)
    #expect(base.applying(StylePatch()) == base)
    let result = base.applying(
        StylePatch(foreground: .terminalDefault, bold: false, italic: false, dim: false, strikethrough: false))
    #expect(result.foreground == .terminalDefault)
    #expect(result.background == base.background)
    #expect(!result.bold && !result.italic && !result.dim && !result.strikethrough)
    #expect(result.underlined && result.reversed)
    #expect(base.applying(StylePatch(background: .terminalDefault)).background == .terminalDefault)
}

@Test func composedStylePatchesApplyInOrder() {
    let base = Style(foreground: .indexed(2), background: .indexed(5), italic: true)
    let first = StylePatch(foreground: .indexed(4), bold: true, underlined: true, dim: true)
    let second = StylePatch(
        foreground: .terminalDefault, bold: false, underlined: false, reversed: true,
        dim: false, strikethrough: true)
    #expect(base.applying(first.applying(second)) == base.applying(first).applying(second))
    #expect(first.applying(StylePatch()) == first)
    #expect(StylePatch().applying(first) == first)
}

@Test func spanPatchesApplyAfterInheritedOrReplacementStyles() {
    let base = Style(foreground: .indexed(4), background: .indexed(5), bold: true)
    let replacement = Style(foreground: .indexed(1), italic: true)
    let layout = TextLayout(
        [
            TextSpan("a", patch: StylePatch(underlined: true)),
            TextSpan("b", style: replacement, patch: StylePatch(bold: true)),
            TextSpan("c", patch: StylePatch(foreground: .terminalDefault, bold: false)),
            TextSpan("d", style: Style()),
        ], width: 4)
    var buffer = Buffer(width: 4, height: 1)
    layout.paint(in: buffer.area, style: base, buffer: &buffer)
    #expect(buffer[0, 0].style == base.applying(StylePatch(underlined: true)))
    #expect(buffer[1, 0].style == replacement.applying(StylePatch(bold: true)))
    #expect(buffer[2, 0].style == base.applying(StylePatch(foreground: .terminalDefault, bold: false)))
    #expect(buffer[3, 0].style == Style())
}

@Test func spanPatchesPreserveGraphemeSourceLinksAndWrappedPrefixes() {
    let patch = StylePatch(dim: true, strikethrough: true)
    let link = "https://example.com"
    let layout = TextLayout(
        [TextSpan("e", link: link, patch: patch), TextSpan("\u{301}界\tz")], width: 4,
        continuationPrefix: TextSpan(">", copyable: false, patch: StylePatch(bold: true)))
    #expect(layout.lines[0].glyphs[0].text == "e\u{301}")
    #expect(layout.lines[0].glyphs[0].patch == patch)
    #expect(layout.lines[0].glyphs[0].link == link)
    #expect(layout.lines[1].glyphs[0].patch == StylePatch(bold: true))
    let selection = TextSelection(anchor: Point(x: 0, y: 0), head: Point(x: 3, y: 2))
    #expect(layout.selectedText(selection) == "e\u{301}界\tz")
    var buffer = Buffer(width: 4, height: 3)
    layout.paint(in: buffer.area, style: Style(foreground: .indexed(3)), buffer: &buffer)
    #expect(buffer[0, 0].style.dim && buffer[0, 0].style.strikethrough)
    #expect(buffer[0, 0].link == link)
    #expect(buffer[0, 1].style.bold)
    #expect(buffer[0, 1].style.foreground == .indexed(3))
}

@Test func dimAndStrikethroughEncodeAndIdenticalFramesStaySilent() {
    var buffer = Buffer(width: 2, height: 1)
    buffer.put("x", width: 1, at: Point(x: 0, y: 0), style: Style(bold: true, dim: true, strikethrough: true))
    var encoder = CellDiff(synchronizedOutput: false)
    let (first, _) = encoder.encode(buffer, previous: nil, cursor: nil)
    #expect(String(decoding: first, as: UTF8.self).contains("\u{1b}[0;1;2;9mx"))
    let (unchanged, stats) = encoder.encode(buffer, previous: buffer, cursor: nil)
    #expect(unchanged.isEmpty && stats.bytes == 0)
    let previous = buffer
    buffer.put("x", width: 1, at: Point(x: 0, y: 0), style: Style())
    let (removed, _) = encoder.encode(buffer, previous: previous, cursor: nil)
    #expect(String(decoding: removed, as: UTF8.self).contains("\u{1b}[0mx"))
}
