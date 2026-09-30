import Testing

@testable import loom

@Test func windowFrameCentersWithinViewportAndLeavesBodyMouseInputAvailable() {
    var window = WindowFrame(
        viewport: Rect(width: 120, height: 40), preferredWidth: 100, preferredHeight: 36)
    #expect(window.bounds == Rect(x: 10, y: 2, width: 100, height: 36))
    #expect(window.contentArea == Rect(x: 11, y: 3, width: 98, height: 34))
    #expect(window.titleArea.y == window.bounds.y)
    #expect(window.expandButton.y == window.bounds.y + 1)
    #expect(window.minimizeButton.maxX + 1 == window.expandButton.x)
    #expect(window.resizeHandle == Rect(x: 107, y: 36, width: 3, height: 2))

    let body = Point(x: window.contentArea.x, y: window.contentArea.y)
    let bodyDown = window.handleMouse(MouseEvent(kind: .down, position: body))
    let bodyDrag = window.handleMouse(MouseEvent(kind: .drag, position: body))
    let bodyUp = window.handleMouse(MouseEvent(kind: .up, position: body))
    #expect(!bodyDown)
    #expect(!bodyDrag)
    #expect(!bodyUp)
    #expect(window.bounds == Rect(x: 10, y: 2, width: 100, height: 36))
}

@Test func titleDragMovesWindowAndClampsItToViewport() {
    var window = WindowFrame(
        viewport: Rect(width: 80, height: 30), preferredWidth: 40, preferredHeight: 15)
    let start = Point(x: window.titleArea.x + 2, y: window.titleArea.y)
    let down = window.handleMouse(MouseEvent(kind: .down, position: start))
    #expect(down)
    let moved = window.handleMouse(MouseEvent(kind: .drag, position: Point(x: start.x + 8, y: start.y + 3)))
    #expect(moved)
    #expect(window.bounds == Rect(x: 28, y: 10, width: 40, height: 15))
    let clampedRight = window.handleMouse(MouseEvent(kind: .drag, position: Point(x: 200, y: 200)))
    #expect(clampedRight)
    #expect(window.bounds == Rect(x: 40, y: 15, width: 40, height: 15))
    let clampedLeft = window.handleMouse(MouseEvent(kind: .drag, position: Point(x: -100, y: -100)))
    #expect(clampedLeft)
    #expect(window.bounds == Rect(x: 0, y: 0, width: 40, height: 15))
    let released = window.handleMouse(MouseEvent(kind: .up, position: Point(x: -100, y: -100)))
    let idleDrag = window.handleMouse(MouseEvent(kind: .drag, position: start))
    #expect(released)
    #expect(!idleDrag)
}

@Test func cornerDragResizesWithMinimumAndViewportLimits() {
    var window = WindowFrame(
        viewport: Rect(width: 80, height: 30), preferredWidth: 40, preferredHeight: 15,
        minimumWidth: 20, minimumHeight: 8)
    let corner = Point(x: window.bounds.maxX - 1, y: window.bounds.maxY - 1)
    let down = window.handleMouse(MouseEvent(kind: .down, position: corner))
    let expanded = window.handleMouse(MouseEvent(kind: .drag, position: Point(x: 200, y: 200)))
    #expect(down)
    #expect(expanded)
    #expect(window.bounds == Rect(x: 20, y: 7, width: 60, height: 23))
    let shrunk = window.handleMouse(MouseEvent(kind: .drag, position: Point(x: -100, y: -100)))
    #expect(shrunk)
    #expect(window.bounds == Rect(x: 20, y: 7, width: 20, height: 8))
    let released = window.handleMouse(MouseEvent(kind: .up, position: Point(x: -100, y: -100)))
    #expect(released)

    window.resize(byColumns: 10, rows: 4)
    #expect(window.bounds == Rect(x: 20, y: 7, width: 30, height: 12))
    window.move(byColumns: 100, rows: 100)
    #expect(window.bounds == Rect(x: 50, y: 18, width: 30, height: 12))
}

@Test func expandRestoresPreviousBoundsAfterTerminalResize() {
    var window = WindowFrame(
        viewport: Rect(width: 80, height: 30), preferredWidth: 40, preferredHeight: 15)
    window.move(byColumns: 5, rows: 3)
    let control = Point(x: window.expandButton.x + 1, y: window.expandButton.y)
    let expanded = window.handleMouse(MouseEvent(kind: .down, position: control))
    #expect(expanded)
    #expect(window.isExpanded)
    #expect(window.bounds == Rect(width: 80, height: 30))
    #expect(window.resizeHandle.width == 0)

    window.resizeViewport(to: Rect(width: 50, height: 20))
    #expect(window.bounds == Rect(width: 50, height: 20))
    window.move(byColumns: 3, rows: 2)
    window.resize(byColumns: -10, rows: -4)
    #expect(window.bounds == Rect(width: 50, height: 20))
    window.toggleExpanded()
    #expect(!window.isExpanded)
    #expect(window.bounds == Rect(x: 10, y: 5, width: 40, height: 15))

    window.resizeViewport(to: Rect(width: 18, height: 7))
    #expect(window.bounds == Rect(width: 18, height: 7))
    window.resizeViewport(to: Rect(width: 80, height: 30))
    #expect(window.bounds == Rect(x: 25, y: 10, width: 40, height: 15))
}

@Test func windowFrameRendersVisibleChromeAtItsHitAreas() {
    let window = WindowFrame(
        viewport: Rect(width: 60, height: 24), preferredWidth: 40, preferredHeight: 16)
    var buffer = Buffer(width: 60, height: 24)
    window.render(in: window.bounds, buffer: &buffer)

    #expect(buffer[window.bounds.x, window.bounds.y].symbol == "┌")
    #expect(buffer[window.bounds.maxX - 1, window.bounds.y].symbol == "┐")
    #expect(buffer[window.bounds.x, window.bounds.maxY - 1].symbol == "└")
    #expect(buffer[window.bounds.maxX - 1, window.bounds.maxY - 1].symbol == "┘")
    for x in window.titleArea.x..<window.titleArea.maxX {
        #expect(buffer[x, window.bounds.y].symbol == "─")
        #expect(buffer[x, window.bounds.maxY - 1].symbol == "─")
    }
    for y in (window.bounds.y + 1)..<(window.bounds.maxY - 1) {
        #expect(buffer[window.bounds.x, y].symbol == "│")
        #expect(buffer[window.bounds.maxX - 1, y].symbol == "│")
    }
    #expect(buffer[window.expandButton.x + 1, window.expandButton.y].symbol == "□")
    #expect(buffer[window.minimizeButton.x + 1, window.minimizeButton.y].symbol == "−")
    #expect(!buffer.plainText.contains("◢"))
}

@Test func insetWindowIgnoresBordersAwayFromLowerRightResizeRegion() {
    var window = WindowFrame(
        viewport: Rect(width: 100, height: 40), preferredWidth: 40, preferredHeight: 16)
    window.insetTitle = true
    let original = window.bounds
    let edges = [
        Point(x: original.x, y: original.y),
        Point(x: original.maxX - 1, y: original.y),
        Point(x: original.x, y: original.maxY - 1),
        Point(x: original.x, y: original.y + original.height / 2),
        Point(x: original.maxX - 1, y: original.y + original.height / 2),
        Point(x: original.x + original.width / 2, y: original.y),
        Point(x: original.x + original.width / 2, y: original.maxY - 1),
        Point(x: original.maxX - 4, y: original.maxY - 1),
        Point(x: original.maxX - 1, y: original.maxY - 3),
    ]
    for point in edges {
        let pressed = window.handleMouse(.init(kind: .down, position: point))
        #expect(!pressed)
        let dragged = window.handleMouse(.init(kind: .drag, position: Point(x: point.x + 6, y: point.y + 3)))
        #expect(!dragged)
        let released = window.handleMouse(.init(kind: .up, position: point))
        #expect(!released)
        #expect(window.bounds == original)
    }
}

@Test(arguments: [false, true])
func lowerRightResizeRegionUsesOnlyConnectedOuterBorderCells(insetTitle: Bool) {
    var window = WindowFrame(
        viewport: Rect(width: 60, height: 24), preferredWidth: 40, preferredHeight: 16)
    window.insetTitle = insetTitle
    let original = window.bounds
    let corner = Point(x: original.maxX - 1, y: original.maxY - 1)
    #expect(window.resizeHandle == Rect(x: original.maxX - 3, y: original.maxY - 2, width: 3, height: 2))
    var buffer = Buffer(width: 60, height: 24)
    let content = Point(x: original.maxX - 2, y: original.maxY - 2)
    buffer.put("x", width: 1, at: content, style: Style())
    window.render(in: window.bounds, buffer: &buffer)
    #expect(buffer[corner.x, corner.y].symbol == "┘")
    #expect(buffer[corner.x - 1, corner.y].symbol == "─")
    #expect(buffer[corner.x, corner.y - 1].symbol == "│")
    #expect(buffer[content.x, content.y].symbol == "x")
    #expect(!buffer.plainText.contains("◢"))
    for column in window.resizeHandle.x..<corner.x {
        let body = Point(x: column, y: content.y)
        #expect(!window.isResizeHandle(at: body))
        let pressed = window.handleMouse(.init(kind: .down, position: body))
        #expect(!pressed)
        let dragged = window.handleMouse(.init(kind: .drag, position: corner))
        #expect(!dragged)
        let released = window.handleMouse(.init(kind: .up, position: corner))
        #expect(!released)
        #expect(window.bounds == original)
    }
    for point in [
        corner, Point(x: corner.x - 1, y: corner.y), Point(x: corner.x - 2, y: corner.y),
        Point(x: corner.x, y: corner.y - 1),
    ] {
        var resized = window
        #expect(resized.isResizeHandle(at: point))
        let pressed = resized.handleMouse(.init(kind: .down, position: point))
        #expect(pressed)
        let released = resized.handleMouse(.init(kind: .up, position: Point(x: point.x + 3, y: point.y + 2)))
        #expect(released)
        #expect(
            resized.bounds
                == Rect(x: original.x, y: original.y, width: original.width + 3, height: original.height + 2))
    }

    window.toggleExpanded()
    buffer = Buffer(width: 60, height: 24)
    window.render(in: window.bounds, buffer: &buffer)
    #expect(window.resizeHandle.width == 0)
    #expect(!window.isResizeHandle(at: Point(x: window.bounds.maxX - 1, y: window.bounds.maxY - 1)))
    #expect(!buffer.plainText.contains("◢"))
}

@Test func repeatedViewportLayoutPreservesEveryTitleDragAndFinalRelease() {
    let viewport = Rect(width: 100, height: 50)
    var window = WindowFrame(viewport: viewport, preferredWidth: 40, preferredHeight: 16)
    window.insetTitle = true
    let original = window.bounds
    let start = Point(x: window.titleArea.x + 2, y: window.titleArea.y)
    let pressed = window.handleMouse(.init(kind: .down, position: start))
    #expect(pressed)
    for step in 1...5 {
        window.resizeViewport(to: viewport)
        let dragged = window.handleMouse(.init(kind: .drag, position: Point(x: start.x + step, y: start.y + step)))
        #expect(dragged)
        #expect(
            window.bounds
                == Rect(x: original.x + step, y: original.y + step, width: original.width, height: original.height))
    }
    window.resizeViewport(to: viewport)
    let end = Point(x: start.x + 7, y: start.y + 6)
    let released = window.handleMouse(.init(kind: .up, position: end))
    #expect(released)
    #expect(window.bounds == Rect(x: original.x + 7, y: original.y + 6, width: original.width, height: original.height))
    let dragged2 = window.handleMouse(.init(kind: .drag, position: start))
    #expect(!dragged2)
}

@Test func repeatedViewportLayoutPreservesResizeDragAndFinalRelease() {
    let viewport = Rect(width: 100, height: 50)
    var window = WindowFrame(viewport: viewport, preferredWidth: 40, preferredHeight: 16)
    window.insetTitle = true
    let original = window.bounds
    let start = Point(x: window.bounds.maxX - 1, y: window.bounds.maxY - 1)
    let pressed = window.handleMouse(.init(kind: .down, position: start))
    #expect(pressed)
    for step in 1...5 {
        window.resizeViewport(to: viewport)
        let dragged = window.handleMouse(.init(kind: .drag, position: Point(x: start.x + step, y: start.y + step)))
        #expect(dragged)
        #expect(
            window.bounds
                == Rect(x: original.x, y: original.y, width: original.width + step, height: original.height + step))
    }
    window.resizeViewport(to: viewport)
    let released = window.handleMouse(.init(kind: .up, position: Point(x: start.x + 7, y: start.y + 6)))
    #expect(released)
    #expect(window.bounds == Rect(x: original.x, y: original.y, width: original.width + 7, height: original.height + 6))
    let dragged2 = window.handleMouse(.init(kind: .drag, position: start))
    #expect(!dragged2)
}

@Test func titleDragReentersViewportWithoutChangingPointerAnchor() {
    var window = WindowFrame(
        viewport: Rect(x: 3, y: 2, width: 100, height: 40), preferredWidth: 40, preferredHeight: 16)
    window.insetTitle = true
    let original = window.bounds
    let start = Point(x: window.titleArea.x + 2, y: window.titleArea.y)
    let pressed = window.handleMouse(.init(kind: .down, position: start))
    #expect(pressed)
    let dragged = window.handleMouse(.init(kind: .drag, position: Point(x: 1_000, y: 1_000)))
    #expect(dragged)
    #expect(window.bounds == Rect(x: 63, y: 26, width: 40, height: 16))
    let dragged2 = window.handleMouse(.init(kind: .drag, position: Point(x: start.x + 2, y: start.y + 1)))
    #expect(dragged2)
    #expect(window.bounds == Rect(x: original.x + 2, y: original.y + 1, width: 40, height: 16))
    let dragged3 = window.handleMouse(.init(kind: .drag, position: Point(x: -1_000, y: -1_000)))
    #expect(dragged3)
    #expect(window.bounds == Rect(x: 3, y: 2, width: 40, height: 16))
    let released = window.handleMouse(.init(kind: .up, position: start))
    #expect(released)
    #expect(window.bounds == original)
}

@Test func changedViewportCancelsDragAndClampsWindow() {
    var window = WindowFrame(
        viewport: Rect(width: 100, height: 40), preferredWidth: 40, preferredHeight: 16)
    window.insetTitle = true
    let start = Point(x: window.titleArea.x + 2, y: window.titleArea.y)
    let pressed = window.handleMouse(.init(kind: .down, position: start))
    #expect(pressed)
    window.resizeViewport(to: Rect(width: 30, height: 10))
    let dragged = window.handleMouse(.init(kind: .drag, position: Point(x: 100, y: 100)))
    #expect(!dragged)
    let released = window.handleMouse(.init(kind: .up, position: Point(x: 100, y: 100)))
    #expect(!released)
    #expect(window.bounds == Rect(width: 30, height: 10))
}

@Test func tinyWindowsClampResizeRegionToTheirOuterBorder() {
    for viewport in [
        Rect(width: 0, height: 0), Rect(width: 1, height: 1), Rect(width: 1, height: 2),
        Rect(width: 2, height: 1), Rect(width: 7, height: 3), Rect(width: 4, height: 4),
    ] {
        var window = WindowFrame(viewport: viewport, preferredWidth: 40, preferredHeight: 16)
        window.insetTitle = true
        var buffer = Buffer(width: viewport.width, height: viewport.height)
        window.render(in: window.bounds, buffer: &buffer)
        let hasRegion = viewport.width > 0 && viewport.height > 0
        #expect((window.resizeHandle.width > 0) == hasRegion)
        #expect(!buffer.plainText.contains("◢"))
        if hasRegion {
            #expect(window.resizeHandle.width == min(3, viewport.width))
            #expect(window.resizeHandle.height == min(2, viewport.height))
            #expect(window.resizeHandle.maxX == viewport.maxX)
            #expect(window.resizeHandle.maxY == viewport.maxY)
        }
        for point in [
            Point(x: 0, y: 0), Point(x: viewport.maxX - 1, y: 0),
            Point(x: 0, y: viewport.maxY - 1), Point(x: viewport.maxX - 1, y: viewport.maxY - 1),
        ] {
            let canResize = window.isResizeHandle(at: point)
            let pressed = window.handleMouse(.init(kind: .down, position: point))
            #expect(pressed == canResize)
            let dragged = window.handleMouse(.init(kind: .drag, position: Point(x: -100, y: -100)))
            #expect(dragged == canResize)
            let released = window.handleMouse(.init(kind: .up, position: point))
            #expect(released == canResize)
            #expect(window.bounds == viewport)
        }
    }
}

@Test func insetTitleMovesWindowAndLeavesContentSelectionAvailable() {
    var window = WindowFrame(
        viewport: Rect(width: 100, height: 40), preferredWidth: 50, preferredHeight: 20)
    window.insetTitle = true
    let original = window.bounds
    #expect(window.titleArea.y == original.y + 1)
    let title = Point(x: window.titleArea.x + 2, y: window.titleArea.y)
    let end = Point(x: title.x + 4, y: title.y + 2)
    let pressed = window.handleMouse(.init(kind: .down, position: title))
    #expect(pressed)
    let dragged = window.handleMouse(.init(kind: .drag, position: end))
    #expect(dragged)
    let released = window.handleMouse(.init(kind: .up, position: end))
    #expect(released)
    #expect(window.bounds == Rect(x: original.x + 4, y: original.y + 2, width: original.width, height: original.height))
    let content = Point(x: window.bounds.x + 4, y: window.bounds.y + 4)
    let pressed2 = window.handleMouse(.init(kind: .down, position: content))
    #expect(!pressed2)
    let dragged2 = window.handleMouse(.init(kind: .drag, position: content))
    #expect(!dragged2)
    let released2 = window.handleMouse(.init(kind: .up, position: content))
    #expect(!released2)
}

@Test func newBodyPressDropsStaleTitleDrag() {
    var window = WindowFrame(
        viewport: Rect(width: 100, height: 40), preferredWidth: 50, preferredHeight: 20)
    window.insetTitle = true
    let original = window.bounds
    let title = Point(x: window.titleArea.x + 2, y: window.titleArea.y)
    let pressed = window.handleMouse(.init(kind: .down, position: title))
    #expect(pressed)
    let content = Point(x: original.x + 4, y: original.y + 4)
    let pressed2 = window.handleMouse(.init(kind: .down, position: content))
    #expect(!pressed2)
    let dragged = window.handleMouse(.init(kind: .drag, position: Point(x: content.x + 4, y: content.y + 2)))
    #expect(!dragged)
    let released = window.handleMouse(.init(kind: .up, position: content))
    #expect(!released)
    #expect(window.bounds == original)
}

@Test func expandedWindowsDisableCornerResizingAndRestoreTheirNormalGeometry() {
    var window = WindowFrame(
        viewport: Rect(width: 100, height: 40), preferredWidth: 50, preferredHeight: 20)
    window.insetTitle = true
    let normal = window.bounds
    window.toggleExpanded()
    #expect(window.resizeHandle.width == 0)
    let pressed = window.handleMouse(.init(kind: .down, position: Point(x: 0, y: 0)))
    #expect(!pressed)
    let dragged = window.handleMouse(.init(kind: .drag, position: Point(x: 10, y: 10)))
    #expect(!dragged)
    #expect(window.bounds == window.viewport)
    window.toggleExpanded()
    #expect(window.bounds == normal)
}
