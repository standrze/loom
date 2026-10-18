import Foundation
import Testing

@testable import loom

@Test func forcedCellRepaintsUnchangedFrame() {
    var buffer = Buffer(width: 3, height: 1)
    buffer.put("界", width: 2, at: Point(x: 0, y: 0), diffPolicy: .alwaysUpdate)
    var diff = CellDiff(synchronizedOutput: false)
    let (bytes, stats) = diff.encode(buffer, previous: buffer, cursor: nil)
    #expect(String(decoding: bytes, as: UTF8.self).contains("界"))
    #expect(stats.changedCells == 2)
    buffer.setDiffPolicy(.automatic, in: buffer.area)
    #expect(diff.encode(buffer, previous: buffer, cursor: nil).0.isEmpty)
}

@Test func skippedCellsPreventDestructiveFullClear() {
    var buffer = Buffer(width: 3, height: 1)
    buffer.put("X", width: 1, at: Point(x: 1, y: 0), diffPolicy: .skip)
    var diff = CellDiff(synchronizedOutput: false)
    let (bytes, _) = diff.encode(buffer, previous: nil, cursor: nil)
    let output = String(decoding: bytes, as: UTF8.self)
    #expect(!output.contains("\u{1b}[2J"))
    #expect(!output.contains("X"))
    #expect(output.contains(" "))
}

@Test func skippedHalfProtectsPreviousWideGlyphInBothBackends() throws {
    var old = Buffer(width: 3, height: 1)
    old.put("界", width: 2, at: Point(x: 0, y: 0))
    var next = Buffer(width: 3, height: 1)
    next.put("A", width: 1, at: Point(x: 0, y: 0))
    next.put("X", width: 1, at: Point(x: 1, y: 0), diffPolicy: .skip)
    var diff = CellDiff(synchronizedOutput: false)
    #expect(diff.encode(next, previous: old, cursor: nil).0.isEmpty)
    var backend = TestBackend(width: 3, height: 1)
    func present(_ buffer: Buffer, previous: Buffer?) -> RenderUpdate {
        .frame(
            RenderPresentation(
                next: FrameSnapshot(buffer: buffer, cursor: nil),
                previous: previous.map { FrameSnapshot(buffer: $0, cursor: nil) },
                terminalSize: RenderSize(width: 3, height: 1), area: buffer.area, clearScreen: true))
    }
    _ = try backend.render(present(old, previous: nil))
    _ = try backend.render(present(next, previous: old))
    #expect(backend.screen[0, 0].symbol == "界")
    #expect(backend.screen[1, 0].width == 0)
    // A full repaint also preserves managed cells.
    _ = try backend.render(present(next, previous: nil))
    #expect(backend.screen[0, 0].symbol == "界")
}

@Test func compositionRetainsPolicyAndOrdinaryOverwriteResetsIt() {
    var source = Buffer(width: 3, height: 1)
    source.put("界", width: 2, at: Point(x: 0, y: 0))
    source.setDiffPolicy(.skip, in: Rect(width: 2, height: 1))
    var target = Buffer(width: 3, height: 1)
    target.compose(source)
    #expect(target[0, 0].diffPolicy == .skip)
    #expect(target[1, 0].diffPolicy == .skip)
    target.put("a", width: 1, at: Point(x: 1, y: 0))
    #expect(target[0, 0] == Cell())
    #expect(target[1, 0].diffPolicy == .automatic)
    source.setDiffPolicy(.alwaysUpdate, in: Rect(x: 1, width: 1, height: 1))
    #expect(source[0, 0].diffPolicy == .skip)
}

@Test func explicitWidthPayloadUsesWholeSpanWithoutChangingUnicodeLayout() throws {
    var buffer = Buffer(width: 6, height: 1)
    buffer.put("abc", width: 4, at: Point(x: 1, y: 0), diffPolicy: .forcedWidth(4))
    #expect(buffer[1, 0].symbol == "abc")
    #expect(buffer[4, 0].width == 0)
    var copy = Buffer(width: 6, height: 1)
    copy.compose(buffer)
    #expect(copy[1, 0] == buffer[1, 0])
    copy.put("X", width: 1, at: Point(x: 4, y: 0))
    #expect(copy[1, 0] == Cell())
    #expect(copy[2, 0] == Cell())
    #expect(copy[3, 0] == Cell())
    #expect(copy[4, 0].symbol == "X")
    var diff = CellDiff(synchronizedOutput: false)
    let bytes = diff.encode(buffer, previous: nil, cursor: nil, clearScreen: false).0
    #expect(String(decoding: bytes, as: UTF8.self).contains("abc"))
    var terminal = RenderTerminal(backend: TestBackend(width: 6, height: 1), width: 6, height: 1)
    try terminal.draw { $0.buffer = buffer }
    #expect(terminal.backend.screen[1, 0].symbol == "abc")
    #expect(terminal.backend.screen[4, 0].width == 0)
    buffer.put("\u{1b}[31m", width: 3, at: Point(x: 0, y: 0), diffPolicy: .forcedWidth(3))
    #expect(buffer[1, 0].symbol == "abc")
}

@Test func skippedOccupancySurvivesSeveralLogicalFramesAndReleasesCleanly() throws {
    var old = Buffer(width: 3, height: 1)
    old.put("界", width: 2, at: Point(x: 0, y: 0))
    var skipped = Buffer(width: 3, height: 1)
    skipped.put("X", width: 1, at: Point(x: 1, y: 0), diffPolicy: .skip)
    var changed = skipped
    changed.put("A", width: 1, at: Point(x: 0, y: 0))
    var diff = CellDiff(synchronizedOutput: false)
    _ = diff.encode(old, previous: nil, cursor: nil)
    #expect(diff.encode(skipped, previous: old, cursor: nil).0.isEmpty)
    #expect(diff.encode(changed, previous: skipped, cursor: nil).0.isEmpty)
    #expect(diff.encode(changed, previous: changed, cursor: nil).0.isEmpty)
    var backend = TestBackend(width: 3, height: 1)
    func present(_ buffer: Buffer, previous: Buffer?) -> RenderUpdate {
        .frame(
            RenderPresentation(
                next: FrameSnapshot(buffer: buffer, cursor: nil),
                previous: previous.map { FrameSnapshot(buffer: $0, cursor: nil) },
                terminalSize: RenderSize(width: 3, height: 1), area: buffer.area, clearScreen: true))
    }
    _ = try backend.render(present(old, previous: nil))
    _ = try backend.render(present(skipped, previous: old))
    _ = try backend.render(present(changed, previous: skipped))
    #expect(backend.screen[0, 0].symbol == "界")
    var released = changed
    released.setDiffPolicy(.automatic, in: released.area)
    let releasedBytes = diff.encode(released, previous: changed, cursor: nil).0
    #expect(String(decoding: releasedBytes, as: UTF8.self).contains("A"))
    _ = try backend.render(present(released, previous: changed))
    #expect(backend.screen[0, 0].symbol == "A")
    #expect(backend.screen[1, 0].symbol == "X")
    #expect(diff.encode(released, previous: released, cursor: nil).0.isEmpty)
}

@Test func physicalOccupancyResizesAndResetRequiresRepaint() {
    var old = Buffer(width: 3, height: 1)
    old.put("界", width: 2, at: Point(x: 0, y: 0))
    var diff = CellDiff(synchronizedOutput: false)
    _ = diff.encode(old, previous: nil, cursor: nil)
    var larger = Buffer(width: 5, height: 1)
    larger.put("X", width: 1, at: Point(x: 1, y: 0), diffPolicy: .skip)
    let resized = String(decoding: diff.encode(larger, previous: old, cursor: nil).0, as: UTF8.self)
    #expect(!resized.contains("\u{1b}[1;1H"))
    var changed = larger
    changed.put("A", width: 1, at: Point(x: 0, y: 0))
    #expect(diff.encode(changed, previous: larger, cursor: nil).0.isEmpty)
    diff.reset()
    changed.setDiffPolicy(.automatic, in: changed.area)
    let recovered = String(decoding: diff.encode(changed, previous: nil, cursor: nil).0, as: UTF8.self)
    #expect(recovered.contains("\u{1b}[2J"))
    #expect(recovered.contains("A"))
    #expect(diff.encode(changed, previous: changed, cursor: nil).0.isEmpty)
}

@Test func forcedWidthPolicyRejectsMismatchedExistingSpans() {
    var buffer = Buffer(width: 4, height: 1)
    buffer.put("界", width: 2, at: Point(x: 0, y: 0))
    buffer.setDiffPolicy(.forcedWidth(3), in: buffer.area)
    #expect(buffer[0, 0].diffPolicy == .automatic)
    #expect(buffer[2, 0].diffPolicy == .automatic)
    buffer.setDiffPolicy(.forcedWidth(2), in: buffer.area)
    #expect(buffer[0, 0].diffPolicy == .forcedWidth(2))
    #expect(buffer[1, 0].diffPolicy == .forcedWidth(2))
    #expect(buffer[2, 0].diffPolicy == .automatic)
}

@Test func explicitClearInvalidatesANSIPhysicalOccupancyAndRepaints() throws {
    var original = Buffer(width: 3, height: 1)
    original.put("界", width: 2, at: Point(x: 0, y: 0))
    var skipped = Buffer(width: 3, height: 1)
    skipped.put("A", width: 1, at: Point(x: 0, y: 0))
    skipped.put("X", width: 1, at: Point(x: 1, y: 0), diffPolicy: .skip)
    func present(_ buffer: Buffer, previous: Buffer?, clears: [Rect] = []) -> RenderUpdate {
        .frame(
            RenderPresentation(
                next: FrameSnapshot(buffer: buffer, cursor: nil),
                previous: previous.map { FrameSnapshot(buffer: $0, cursor: nil) },
                terminalSize: RenderSize(width: 3, height: 1), area: buffer.area,
                clearScreen: true, clears: clears))
    }
    var ansi = ANSIRenderBackend(backend: MemoryBackend(), synchronizedOutput: false)
    var headless = TestBackend(width: 3, height: 1)
    _ = try ansi.render(present(original, previous: nil))
    _ = try headless.render(present(original, previous: nil))
    _ = try ansi.render(present(skipped, previous: original))
    _ = try headless.render(present(skipped, previous: original))
    let before = ansi.backend.writes.count
    _ = try ansi.render(present(skipped, previous: skipped, clears: [skipped.area]))
    _ = try headless.render(present(skipped, previous: skipped, clears: [skipped.area]))
    #expect(ansi.backend.writes.count == before + 1)
    let bytes = String(decoding: ansi.backend.writes.last!, as: UTF8.self)
    #expect(bytes.contains("A"))
    #expect(!bytes.contains("X"))
    #expect(!bytes.contains("\u{1b}[2J"))
    #expect(headless.screen[0, 0].symbol == "A")
    #expect(headless.screen[1, 0].symbol == " ")
}

@Test func longExplicitSpanRetainsWholeGlyphOwnershipAcrossPresentation() throws {
    let span = 1024
    let payload = String(repeating: "a", count: span)
    var original = Buffer(width: span + 2, height: 1)
    original.put(payload, width: span, at: Point(x: 1, y: 0), diffPolicy: .forcedWidth(span))
    var diff = CellDiff(synchronizedOutput: false)
    _ = diff.encode(original, previous: nil, cursor: nil)
    #expect(diff.encode(original, previous: original, cursor: nil).0.isEmpty)
    var skipped = Buffer(width: span + 2, height: 1)
    skipped.put("X", width: 1, at: Point(x: span, y: 0), diffPolicy: .skip)
    #expect(diff.encode(skipped, previous: original, cursor: nil).0.isEmpty)
    skipped.put("Z", width: 1, at: Point(x: 1, y: 0))
    #expect(diff.encode(skipped, previous: skipped, cursor: nil).0.isEmpty)
    var terminal = RenderTerminal(
        backend: TestBackend(width: span + 2, height: 1), width: span + 2, height: 1)
    try terminal.draw { $0.buffer = original }
    try terminal.draw { $0.buffer = skipped }
    #expect(terminal.backend.screen[1, 0].symbol == payload)
    #expect(terminal.backend.screen[span, 0].width == 0)
    var copied = Buffer(width: span + 2, height: 1)
    copied.compose(original)
    copied.put("Z", width: 1, at: Point(x: span, y: 0))
    #expect(copied[1, 0] == Cell())
    #expect(copied[span - 1, 0] == Cell())
    #expect(copied[span, 0].symbol == "Z")
    original.put("b", width: span, at: Point(x: 1, y: 0), diffPolicy: .forcedWidth(span))
    #expect(original[1, 0].symbol == "b")
    #expect(original[span, 0].width == 0)
}
