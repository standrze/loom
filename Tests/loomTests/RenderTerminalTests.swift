import Testing

@testable import loom

private enum RenderFailure: Error { case output }

private struct FailingRenderBackend: RenderBackend {
    var surface: TestBackend
    var attempts = 0
    var failAttempt: Int

    mutating func render(_ update: RenderUpdate) throws -> RenderStats {
        attempts += 1
        if attempts == failAttempt {
            surface.failure = .afterStep(2)
            defer { surface.failure = nil }
            _ = try surface.render(update)
            throw RenderFailure.output
        }
        return try surface.render(update)
    }
}

@Test func semanticDriverUsesLocalFramesAndClearsMovedFixedFootprints() throws {
    var terminal = RenderTerminal(
        backend: TestBackend(width: 8, height: 4), width: 8, height: 4,
        viewport: .fixed(Rect(x: 2, y: 1, width: 4, height: 2)))
    try terminal.draw { frame in
        #expect(frame.area == Rect(width: 4, height: 2))
        frame.buffer.put("界", width: 2, at: Point(x: 0, y: 0), style: Style(hidden: true))
        frame.cursor = Point(x: 1, y: 1)
    }
    #expect(terminal.backend.screen[2, 1].symbol == "界")
    #expect(terminal.backend.screen[2, 1].style.hidden)
    #expect(terminal.backend.cursor == Point(x: 3, y: 2))
    #expect(terminal.snapshot?.cursor == Point(x: 1, y: 1))
    terminal.setViewport(.fixed(Rect(x: 5, y: 0, width: 2, height: 1)))
    #expect(terminal.snapshot == nil)
    try terminal.draw { $0.buffer.put("N", width: 1, at: Point(x: 0, y: 0)) }
    #expect(terminal.backend.screen[2, 1] == Cell())
    #expect(terminal.backend.screen[3, 1] == Cell())
    #expect(terminal.backend.screen[5, 0].symbol == "N")
    #expect(terminal.localPoint(from: Point(x: 5, y: 0)) == Point(x: 0, y: 0))
}

@Test func semanticInlineInsertionScrollsAndRetainsPrompt() throws {
    var terminal = RenderTerminal(
        backend: TestBackend(width: 4, height: 3), width: 4, height: 3,
        viewport: .inline(height: 1, anchor: Point(x: 0, y: 2)))
    try terminal.draw {
        $0.buffer.put(">", width: 1, at: Point(x: 0, y: 0))
        $0.cursor = Point(x: 1, y: 0)
    }
    try terminal.insertBefore(height: 4) { frame in
        for row in 0..<4 { frame.buffer.put(String(row), width: 1, at: Point(x: 0, y: row)) }
    }
    #expect(terminal.backend.scrollback.count == 4)
    #expect(terminal.backend.screen.plainText == "2   \n3   \n>   ")
    #expect(terminal.backend.cursor == Point(x: 1, y: 2))
    #expect(terminal.snapshot?.buffer.plainText == ">   ")
    #expect(!terminal.requiresReanchor)
}

@Test func semanticDriverInvalidatesAfterPartialFrameAndRecovers() throws {
    let backend = FailingRenderBackend(surface: TestBackend(width: 3, height: 2), failAttempt: 1)
    var terminal = RenderTerminal(backend: backend, width: 3, height: 2)
    #expect(throws: (any Error).self) {
        try terminal.draw { $0.buffer.put("A", width: 1, at: Point(x: 0, y: 0)) }
    }
    #expect(terminal.snapshot == nil)
    #expect(!terminal.requiresReanchor)
    try terminal.draw { $0.buffer.put("B", width: 1, at: Point(x: 0, y: 0)) }
    #expect(terminal.snapshot?.buffer[0, 0].symbol == "B")
    #expect(terminal.backend.surface.screen[0, 0].symbol == "B")
}

@Test func semanticDriverRequiresReanchorAfterUncertainInsertion() throws {
    let backend = FailingRenderBackend(surface: TestBackend(width: 3, height: 3), failAttempt: 2)
    var terminal = RenderTerminal(
        backend: backend, width: 3, height: 3, viewport: .inline(height: 1, anchor: Point(x: 0, y: 2)))
    try terminal.draw { $0.buffer.put(">", width: 1, at: Point(x: 0, y: 0)) }
    #expect(throws: (any Error).self) { try terminal.insertBefore(height: 1) { _ in } }
    #expect(terminal.snapshot == nil && terminal.requiresReanchor)
    #expect(throws: ViewportError.reanchorRequired) { try terminal.draw { _ in } }
    try terminal.reanchor(at: Point(x: 0, y: 2))
    try terminal.draw { $0.buffer.put("R", width: 1, at: Point(x: 0, y: 0)) }
    #expect(terminal.backend.surface.screen[0, 2].symbol == "R")
    #expect(!terminal.requiresReanchor)
}

@Test func semanticResizeInvalidatesSnapshotAndInlineAnchor() throws {
    var terminal = RenderTerminal(
        backend: TestBackend(width: 4, height: 4), width: 4, height: 4,
        viewport: .inline(height: 2, anchor: Point(x: 0, y: 2)))
    try terminal.draw { _ in }
    terminal.resize(width: 3, height: 3)
    #expect(terminal.snapshot == nil && terminal.requiresReanchor)
    try terminal.reanchor(at: Point(x: 0, y: 1))
    try terminal.draw { #expect($0.area == Rect(width: 3, height: 2)) }
    #expect(terminal.backend.screen.area == Rect(width: 3, height: 3))
}
