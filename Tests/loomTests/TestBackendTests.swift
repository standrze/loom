import Testing

@testable import loom

private func headlessPresentation(_ buffer: Buffer, width: Int, height: Int) -> RenderUpdate {
    .frame(
        RenderPresentation(
            next: FrameSnapshot(buffer: buffer, cursor: Point(x: 0, y: 0)), previous: nil,
            terminalSize: RenderSize(width: width, height: height),
            area: Rect(width: buffer.width, height: buffer.height), clearScreen: false))
}

@Test func headlessBackendPreservesCellsLinksAndResizes() throws {
    var buffer = Buffer(width: 4, height: 1)
    buffer.put("界", width: 2, at: Point(x: 1, y: 0), style: Style(bold: true), link: "https://example.com")
    var backend = TestBackend(width: 4, height: 2)
    _ = try backend.render(headlessPresentation(buffer, width: 4, height: 2))
    #expect(backend.screen[1, 0] == buffer[1, 0])
    #expect(backend.screen[2, 0] == buffer[2, 0])
    #expect(backend.cursor == Point(x: 0, y: 0))
    _ = try backend.render(headlessPresentation(Buffer(width: 0, height: 0), width: 3, height: 3))
    #expect(backend.screen[1, 0] == buffer[1, 0])
    #expect(backend.screen.height == 3)
    #expect(backend.operations.count == 2)
}

@Test func headlessInsertionScrollsAndRepaintsRetainedFrame() throws {
    var initial = Buffer(width: 3, height: 3)
    initial.put("A", width: 1, at: Point(x: 0, y: 0))
    initial.put("B", width: 1, at: Point(x: 0, y: 1))
    var backend = TestBackend(width: 3, height: 3)
    _ = try backend.render(headlessPresentation(initial, width: 3, height: 3))
    var content = Buffer(width: 3, height: 2)
    content.put("X", width: 1, at: Point(x: 0, y: 0))
    content.put("Y", width: 1, at: Point(x: 0, y: 1))
    var retained = Buffer(width: 3, height: 1)
    retained.put("R", width: 1, at: Point(x: 0, y: 0))
    _ = try backend.render(
        .insertion(
            RenderInsertion(
                content: content, retained: FrameSnapshot(buffer: retained, cursor: nil),
                terminalSize: RenderSize(width: 3, height: 3),
                oldArea: Rect(y: 2, width: 3, height: 1), newArea: Rect(y: 2, width: 3, height: 1))))
    #expect(backend.scrollback.map(\.plainText) == ["A  ", "B  "])
    #expect(backend.screen.plainText == "X  \nY  \nR  ")
    #expect(backend.cursor == nil)
}

@Test func headlessFailureRetainsOnlyCompletedPrimitiveChanges() throws {
    var buffer = Buffer(width: 2, height: 1)
    buffer.put("X", width: 1, at: Point(x: 0, y: 0))
    var before = TestBackend(width: 2, height: 1, failure: .beforeStep(1))
    #expect(throws: TestBackendError(failure: .beforeStep(1))) {
        _ = try before.render(headlessPresentation(buffer, width: 2, height: 1))
    }
    #expect(before.screen.plainText == "  ")
    #expect(before.completedSteps == 0)
    var after = TestBackend(width: 2, height: 1, failure: .afterStep(1))
    #expect(throws: TestBackendError(failure: .afterStep(1))) {
        _ = try after.render(headlessPresentation(buffer, width: 2, height: 1))
    }
    #expect(after.screen.plainText == "X ")
    #expect(after.completedSteps == 1)
    after.failure = nil
    _ = try after.render(headlessPresentation(buffer, width: 2, height: 1))
    #expect(after.operations.count == 2)
}

@Test func headlessClearPermissionDoesNotClearSameSizeFrame() throws {
    var initial = Buffer(width: 4, height: 2)
    initial.put("Z", width: 1, at: Point(x: 3, y: 1))
    var backend = TestBackend(width: 4, height: 2)
    _ = try backend.render(headlessPresentation(initial, width: 4, height: 2))
    let local = Buffer(width: 1, height: 1)
    _ = try backend.render(
        .frame(
            RenderPresentation(
                next: FrameSnapshot(buffer: local, cursor: Point(x: 1, y: 0)),
                previous: FrameSnapshot(buffer: local, cursor: nil),
                terminalSize: RenderSize(width: 4, height: 2), area: Rect(width: 1, height: 1), clearScreen: true)))
    #expect(backend.screen[3, 1].symbol == "Z")
    #expect(backend.cursor == nil)
    let steps = backend.completedSteps
    backend.reset()
    #expect(backend.operations.count == 2)
    #expect(backend.completedSteps == steps)
    _ = try backend.render(
        .frame(
            RenderPresentation(
                next: FrameSnapshot(buffer: local, cursor: nil), previous: nil,
                terminalSize: RenderSize(width: 4, height: 2), area: Rect(width: 1, height: 1), clearScreen: true)))
    #expect(backend.screen[3, 1].symbol == " ")
}

@Test func headlessInsertionPadsNarrowRowsAndRetainsFailureHistory() throws {
    var initial = Buffer(width: 4, height: 2)
    initial.fill(initial.area, symbol: "Z")
    var backend = TestBackend(width: 4, height: 2)
    _ = try backend.render(headlessPresentation(initial, width: 4, height: 2))
    var content = Buffer(width: 1, height: 1)
    content.put("X", width: 1, at: Point(x: 0, y: 0))
    _ = try backend.render(
        .insertion(
            RenderInsertion(
                content: content, retained: FrameSnapshot(buffer: Buffer(width: 0, height: 0), cursor: nil),
                terminalSize: RenderSize(width: 4, height: 2),
                oldArea: Rect(width: 1, height: 1), newArea: Rect(width: 0, height: 0))))
    #expect(backend.screen.plainText == "X   \nZZZZ")
    backend.failure = .afterStep(1)
    #expect(throws: TestBackendError(failure: .afterStep(1))) {
        _ = try backend.render(headlessPresentation(content, width: 4, height: 2))
    }
    backend.reset()
    #expect(backend.operations.count == 3)
    #expect(backend.completedSteps == 1)
}
