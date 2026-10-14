import Foundation
import Testing
import loom

private final class WriteFailureControl {
    var fail = false
    var accepted = Data()
}

private struct PartialWriteBackend: Backend {
    let control: WriteFailureControl
    mutating func write(_ data: Data) throws {
        if control.fail {
            control.accepted.append(data.prefix(max(1, data.count / 2)))
            throw TestWriteFailure.failed
        }
        control.accepted.append(data)
    }
}

private enum TestWriteFailure: Error { case failed }

@Test func publicSnapshotsOwnTheirCellsAndDiagnoseDifferences() throws {
    var terminal = Terminal(backend: RecordingBackend(), width: 4, height: 2)
    #expect(terminal.snapshot == nil)
    try terminal.draw { frame in
        frame.buffer.put(
            "界", width: 2, at: Point(x: 0, y: 0), style: Style(dim: true), link: "https://example.com")
        frame.cursor = Point(x: 2, y: 1)
    }
    let first = try #require(terminal.snapshot)
    try terminal.draw { frame in
        frame.buffer.put("x", width: 1, at: Point(x: 0, y: 0))
    }
    let second = try #require(terminal.snapshot)
    #expect(first.buffer[0, 0].symbol == "界")
    #expect(first.buffer[1, 0].width == 0)
    #expect(first.buffer[0, 0].style.dim)
    #expect(first.buffer[0, 0].link == "https://example.com")
    #expect(first.cursor == Point(x: 2, y: 1))
    #expect(second.differences(from: first).contains { $0.contains("Cell (0, 0)") })
    #expect(second.differences(from: first).contains { $0.contains("Cursor:") })
    terminal.resize(width: 5, height: 2)
    #expect(terminal.snapshot == nil)
    try terminal.draw { _ in }
    terminal.invalidate()
    #expect(terminal.snapshot == nil)
}

@Test func fixedViewportUsesPhysicalOutputAndLocalCoordinates() throws {
    var terminal = Terminal(
        backend: RecordingBackend(), width: 12, height: 8, synchronizedOutput: false,
        viewport: .fixed(Rect(x: 3, y: 2, width: 4, height: 2)))
    try terminal.draw { frame in
        #expect(frame.area == Rect(width: 4, height: 2))
        frame.buffer.put("X", width: 1, at: Point(x: 0, y: 0))
        frame.cursor = Point(x: 1, y: 1)
    }
    let output = String(decoding: terminal.backend.data, as: UTF8.self)
    #expect(!output.contains("\u{1b}[2J"))
    #expect(output.contains("\u{1b}[3;4H"))
    #expect(output.contains("\u{1b}[4;5H\u{1b}[?25h"))
    #expect(terminal.localPoint(from: Point(x: 4, y: 3)) == Point(x: 1, y: 1))
    #expect(terminal.localPoint(from: Point(x: 0, y: 0)) == nil)
    #expect(terminal.physicalPoint(from: Point(x: 1, y: 1)) == Point(x: 4, y: 3))
    let stats = try terminal.draw { frame in
        frame.buffer.put("X", width: 1, at: Point(x: 0, y: 0))
        frame.cursor = Point(x: 1, y: 1)
    }
    #expect(stats.bytes == 0)
}

@Test func movingFixedViewportErasesItsOldFootprintWithoutScreenClear() throws {
    var terminal = Terminal(
        backend: RecordingBackend(), width: 10, height: 6, synchronizedOutput: false,
        viewport: .fixed(Rect(x: 2, y: 1, width: 4, height: 2)))
    try terminal.draw { frame in
        frame.buffer.put("x", width: 1, at: Point(x: 0, y: 0))
    }
    terminal.setViewport(.fixed(Rect(x: 4, y: 3, width: 2, height: 1)))
    #expect(terminal.snapshot == nil)
    try terminal.draw { frame in
        frame.buffer.put("y", width: 1, at: Point(x: 0, y: 0))
    }
    let output = String(decoding: try #require(terminal.backend.writes.last), as: UTF8.self)
    #expect(output.contains("\u{1b}[2;3H    \u{1b}[3;3H    "))
    #expect(output.contains("\u{1b}[4;5H"))
    #expect(!output.contains("\u{1b}[2J"))
    #expect(!output.contains("\u{1b}[1;1H"))
}

@Test func failedOrdinaryFrameCanRepaintButSnapshotIsInvalid() throws {
    let control = WriteFailureControl()
    var terminal = Terminal(
        backend: PartialWriteBackend(control: control), width: 8, height: 3,
        viewport: .fixed(Rect(x: 1, y: 1, width: 3, height: 1)))
    control.fail = true
    #expect(throws: TestWriteFailure.self) {
        try terminal.draw { frame in frame.buffer.put("x", width: 1, at: Point(x: 0, y: 0)) }
    }
    #expect(terminal.snapshot == nil)
    #expect(!terminal.requiresReanchor)
    control.fail = false
    try terminal.draw { frame in frame.buffer.put("x", width: 1, at: Point(x: 0, y: 0)) }
    #expect(terminal.snapshot?.buffer[0, 0].symbol == "x")
}

@Test func inlineBottomReservationAndInsertionRetainLocalFrame() throws {
    var terminal = Terminal(
        backend: RecordingBackend(), width: 6, height: 5, synchronizedOutput: false,
        viewport: .inline(height: 2, anchor: Point(x: 0, y: 4)))
    try terminal.draw { frame in
        frame.buffer.put("U", width: 1, at: Point(x: 0, y: 0))
        frame.cursor = Point(x: 1, y: 1)
    }
    #expect(terminal.viewportArea == Rect(x: 0, y: 3, width: 6, height: 2))
    let reserve = String(decoding: terminal.backend.writes[0], as: UTF8.self)
    #expect(reserve.hasPrefix("\u{1b}[5;1H\n"))
    try terminal.insertBefore(height: 2) { frame in
        frame.buffer.put("A", width: 1, at: Point(x: 0, y: 0), style: Style(bold: true))
        frame.buffer.put("B", width: 1, at: Point(x: 0, y: 1))
    }
    let insertion = String(decoding: try #require(terminal.backend.writes.last), as: UTF8.self)
    #expect(!insertion.contains("\u{1b}[2J"))
    #expect(insertion.contains("\u{1b}[0;1mA"))
    #expect(insertion.contains("\r\n"))
    #expect(insertion.contains("U"))
    #expect(terminal.snapshot?.buffer[0, 0].symbol == "U")
    #expect(terminal.snapshot?.cursor == Point(x: 1, y: 1))
    #expect(terminal.viewportArea.y == 3)
    terminal.resize(width: 7, height: 6)
    #expect(terminal.requiresReanchor && terminal.snapshot == nil)
    #expect(throws: ViewportError.reanchorRequired) { try terminal.draw { _ in } }
    try terminal.reanchor(at: Point(x: 0, y: 4))
    try terminal.draw { _ in }
    #expect(!terminal.requiresReanchor)
}

@Test func partiallyFailedInlineInsertionRequiresExplicitReanchorAndNeverReplays() throws {
    let control = WriteFailureControl()
    var terminal = Terminal(
        backend: PartialWriteBackend(control: control), width: 8, height: 4,
        viewport: .inline(height: 2, anchor: Point(x: 0, y: 2)))
    try terminal.draw { frame in frame.buffer.put("U", width: 1, at: Point(x: 0, y: 0)) }
    control.fail = true
    #expect(throws: TestWriteFailure.self) {
        try terminal.insertBefore(height: 1) { frame in
            frame.buffer.put("L", width: 1, at: Point(x: 0, y: 0))
        }
    }
    #expect(terminal.requiresReanchor && terminal.snapshot == nil)
    let acceptedCount = control.accepted.count
    control.fail = false
    #expect(throws: ViewportError.reanchorRequired) { try terminal.draw { _ in } }
    #expect(throws: ViewportError.reanchorRequired) { try terminal.insertBefore(Buffer(width: 1, height: 1)) }
    #expect(control.accepted.count == acceptedCount)
    try terminal.reanchor(at: Point(x: 0, y: 1))
    try terminal.draw { frame in frame.buffer.put("R", width: 1, at: Point(x: 0, y: 0)) }
    let resumed = String(decoding: control.accepted.dropFirst(acceptedCount), as: UTF8.self)
    #expect(resumed.contains("R") && !resumed.contains("L"))
}

@Test func partiallyFailedInlineReservationAlsoRequiresReanchor() {
    let control = WriteFailureControl()
    control.fail = true
    var terminal = Terminal(
        backend: PartialWriteBackend(control: control), width: 8, height: 4,
        viewport: .inline(height: 2, anchor: Point(x: 3, y: 3)))
    #expect(throws: TestWriteFailure.self) { try terminal.draw { _ in } }
    #expect(terminal.requiresReanchor && terminal.snapshot == nil)
}

/// A deliberately small ASCII screen model for the CUP/SGR/LF output used below.
///
/// It does not claim general ANSI emulation or live terminal verification.
private struct ViewportScreenModel {
    let width: Int
    let height: Int
    var rows: [[Character]]
    var scrollback: [String] = []
    var x = 0
    var y = 0

    init(width: Int, height: Int, fill: Character = ".") {
        self.width = width
        self.height = height
        rows = Array(repeating: Array(repeating: fill, count: width), count: height)
    }

    mutating func consume(_ bytes: Data) {
        let characters = Array(String(decoding: bytes, as: UTF8.self))
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\u{1b}", index + 1 < characters.count, characters[index + 1] == "[" {
                index += 2
                var parameters = ""
                while index < characters.count && !("@"..."~").contains(characters[index]) {
                    parameters.append(characters[index])
                    index += 1
                }
                guard index < characters.count else { return }
                if characters[index] == "H" {
                    let values = parameters.split(separator: ";").compactMap { Int($0) }
                    y = min(height - 1, max(0, (values.first ?? 1) - 1))
                    x = min(width - 1, max(0, (values.last ?? 1) - 1))
                } else if characters[index] == "J" && parameters == "2" {
                    rows = Array(repeating: Array(repeating: " ", count: width), count: height)
                }
            } else if character == "\r\n" {
                // Swift treats CRLF as a single grapheme; terminals execute both controls.
                x = 0
                lineFeed()
            } else if character == "\r" {
                x = 0
            } else if character == "\n" {
                lineFeed()
            } else {
                if x == width {
                    x = 0
                    lineFeed()
                }
                rows[y][x] = character
                x += 1
            }
            index += 1
        }
    }

    private mutating func lineFeed() {
        if y == height - 1 {
            scrollback.append(String(rows.removeFirst()))
            rows.append(Array(repeating: " ", count: width))
        } else {
            y += 1
        }
    }
}

@Test func fixedViewportRepaintsAndMovesPreserveSurroundingSentinels() throws {
    var model = ViewportScreenModel(width: 10, height: 5)
    var terminal = Terminal(
        backend: RecordingBackend(), width: 10, height: 5, synchronizedOutput: false,
        viewport: .fixed(Rect(x: 2, y: 1, width: 4, height: 2)))
    try terminal.draw { frame in
        frame.buffer.put("A", width: 1, at: Point(x: 0, y: 0))
    }
    model.consume(terminal.backend.writes[0])
    for y in 0..<5 {
        for x in 0..<10 where !(2..<6).contains(x) || !(1..<3).contains(y) {
            #expect(model.rows[y][x] == ".")
        }
    }
    terminal.setViewport(.fixed(Rect(x: 6, y: 3, width: 2, height: 1)))
    try terminal.draw { frame in
        frame.buffer.put("B", width: 1, at: Point(x: 0, y: 0))
    }
    model.consume(terminal.backend.writes[1])
    #expect(String(model.rows[1]) == "..    ....")
    #expect(String(model.rows[2]) == "..    ....")
    #expect(String(model.rows[3]) == "......B ..")
    #expect(String(model.rows[0]) == "..........")
    #expect(String(model.rows[4]) == "..........")
    #expect(model.scrollback.isEmpty)
}

@Test func inlineInsertionScrollsTranscriptAboveRetainedUiInScreenModel() throws {
    var model = ViewportScreenModel(width: 6, height: 5)
    var terminal = Terminal(
        backend: RecordingBackend(), width: 6, height: 5, synchronizedOutput: false,
        viewport: .inline(height: 2, anchor: Point(x: 0, y: 4)))
    try terminal.draw { frame in
        frame.buffer.put("U", width: 1, at: Point(x: 0, y: 0))
        frame.cursor = Point(x: 1, y: 1)
    }
    model.consume(terminal.backend.writes[0])
    try terminal.insertBefore(height: 2) { frame in
        frame.buffer.put("A", width: 1, at: Point(x: 0, y: 0))
        frame.buffer.put("B", width: 1, at: Point(x: 0, y: 1))
    }
    model.consume(terminal.backend.writes[1])
    #expect(String(model.rows[1]) == "A     ")
    #expect(String(model.rows[2]) == "B     ")
    #expect(String(model.rows[3]) == "U     ")
    #expect(String(model.rows[4]) == "      ")
    #expect(model.scrollback == ["......", "......", "......"])
    #expect(model.x == 1 && model.y == 4)
}

@Test func inlineOrdinaryRepaintFailureKeepsKnownAnchorRetryable() throws {
    let control = WriteFailureControl()
    var terminal = Terminal(
        backend: PartialWriteBackend(control: control), width: 6, height: 4,
        viewport: .inline(height: 2, anchor: Point(x: 0, y: 1)))
    try terminal.draw { _ in }
    control.fail = true
    #expect(throws: TestWriteFailure.self) {
        try terminal.draw { frame in frame.buffer.put("F", width: 1, at: Point(x: 0, y: 0)) }
    }
    #expect(!terminal.requiresReanchor && terminal.snapshot == nil)
    control.fail = false
    try terminal.draw { frame in frame.buffer.put("R", width: 1, at: Point(x: 0, y: 0)) }
    #expect(terminal.snapshot?.buffer[0, 0].symbol == "R")
}

@Test func inlineReservationWithoutLineFeedsRemainsSafelyRetryable() throws {
    let control = WriteFailureControl()
    control.fail = true
    var terminal = Terminal(
        backend: PartialWriteBackend(control: control), width: 6, height: 4,
        viewport: .inline(height: 1, anchor: Point(x: 0, y: 1)))
    #expect(throws: TestWriteFailure.self) { try terminal.draw { _ in } }
    #expect(!terminal.requiresReanchor)
    control.fail = false
    try terminal.draw { _ in }
    #expect(terminal.snapshot != nil)
}

@Test func repeatedReanchorUsesOnlyTheLatestConfirmedCursor() throws {
    var terminal = Terminal(
        backend: RecordingBackend(), width: 6, height: 6, synchronizedOutput: false,
        viewport: .inline(height: 2, anchor: Point(x: 0, y: 4)))
    try terminal.draw { _ in }
    terminal.invalidate()
    try terminal.reanchor(at: Point(x: 0, y: 1))
    try terminal.reanchor(at: Point(x: 0, y: 3))
    try terminal.draw { _ in }
    let output = String(decoding: try #require(terminal.backend.writes.last), as: UTF8.self)
    #expect(output.hasPrefix("\u{1b}[4;1H\n"))
    #expect(!output.contains("\u{1b}[2;1H"))
    #expect(terminal.viewportArea.y == 3)
}

@Test func fullscreenResizeRetainsLegacyWholeScreenClearWithoutFootprintErase() throws {
    var terminal = Terminal(backend: RecordingBackend(), width: 6, height: 4, synchronizedOutput: false)
    try terminal.draw { _ in }
    terminal.resize(width: 7, height: 5)
    try terminal.draw { _ in }
    let output = String(decoding: try #require(terminal.backend.writes.last), as: UTF8.self)
    #expect(output.hasPrefix("\u{1b}[2J"))
    #expect(!output.contains("      "))
}
