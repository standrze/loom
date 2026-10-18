import Testing

@testable import loom

private let canvasBounds = CanvasBounds(min: 0, max: 1)

@Test func canvasBrailleBitsFollowUnicodeDotPositions() {
    let points: [(Double, Double, Int)] = [
        (0, 1, 1), (0, 2.0 / 3, 2), (0, 1.0 / 3, 4), (0, 0, 64),
        (1, 1, 8), (1, 2.0 / 3, 16), (1, 1.0 / 3, 32), (1, 0, 128),
    ]
    for (x, y, bit) in points {
        var buffer = Buffer(width: 1, height: 1)
        Canvas(xBounds: canvasBounds, yBounds: canvasBounds) { context in
            context.point(at: CanvasPoint(x: x, y: y))
        }.render(in: buffer.area, buffer: &buffer)
        #expect(buffer[0, 0].symbol == String(UnicodeScalar(0x2800 + bit)!))
    }
}

@Test func canvasLayersCombineDotsThenReplaceWithLaterAppearance() {
    let style = Style(foreground: .indexed(2))
    var buffer = Buffer(width: 1, height: 1)
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds) { context in
        context.points([CanvasPoint(x: 0, y: 1), CanvasPoint(x: 1, y: 1)])
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == "⠉")
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds) { context in
        context.point(at: CanvasPoint(x: 0, y: 1))
        context.newLayer()
        context.point(at: CanvasPoint(x: 1, y: 0), style: style)
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == "⢀")
    #expect(buffer[0, 0].style == style)
}

@Test func canvasClipsCrossingLinesAndPreservesEnclosingClip() {
    var buffer = Buffer(width: 7, height: 3)
    buffer.withClip(Rect(x: 2, y: 1, width: 3, height: 1)) { target in
        Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
            context.line(from: CanvasPoint(x: -10, y: 0.5), to: CanvasPoint(x: 10, y: 0.5))
        }.render(in: Rect(x: 1, width: 5, height: 3), buffer: &target)
    }
    #expect(buffer.plainText == "       \n  ███  \n       ")
}

@Test func canvasTextKeepsWideGraphemesWholeAndPreservesCrossingOccupants() {
    var buffer = Buffer(width: 5, height: 1)
    buffer.put("界", width: 2, at: Point(x: 0, y: 0))
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
        context.point(at: CanvasPoint(x: 0, y: 1))
        context.print("界A界", at: CanvasPoint(x: 0, y: 1))
    }.render(in: Rect(x: 1, width: 3, height: 1), buffer: &buffer)
    #expect(buffer[0, 0].symbol == "界")
    #expect(buffer[1, 0].width == 0)
    #expect(buffer[3, 0].symbol == "A")
    #expect(buffer[4, 0].symbol == " ")
}

@Test func canvasInvalidBoundsAndNonfiniteShapesPaintNothing() {
    for bounds in [
        CanvasBounds(min: 1, max: 1), CanvasBounds(min: .nan, max: 1),
        CanvasBounds(min: 0, max: .infinity), CanvasBounds(min: 2, max: 1),
    ] {
        var buffer = Buffer(width: 2, height: 2)
        Canvas(xBounds: bounds, yBounds: canvasBounds) { context in
            context.point(at: CanvasPoint(x: 0, y: 0))
        }.render(in: buffer.area, buffer: &buffer)
        #expect(buffer.plainText == "  \n  ")
    }
    var buffer = Buffer(width: 2, height: 2)
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds) { context in
        context.point(at: CanvasPoint(x: .nan, y: 0))
        context.circle(center: CanvasPoint(x: 0, y: 0), radius: .infinity)
        context.line(from: CanvasPoint(x: 0, y: .nan), to: CanvasPoint(x: 1, y: 1))
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "  \n  ")
}

@Test func canvasDegenerateRectanglesAndTinyAreasAreBounded() {
    var buffer = Buffer(width: 1, height: 1)
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
        context.rectangle(origin: CanvasPoint(x: 0.5, y: 0.5), width: 0, height: 0)
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == "█")
    buffer.reset()
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
        context.point(at: CanvasPoint(x: 2, y: 2))
        context.line(from: CanvasPoint(x: -2, y: 0), to: CanvasPoint(x: -1, y: 1))
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == " ")
}

@Test func canvasFilledShapesAndExtremeOffscreenAreaRemainBounded() {
    var buffer = Buffer(width: 3, height: 2)
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .halfBlock) { context in
        context.rectangle(origin: CanvasPoint(x: 0, y: 0), width: 1, height: 1, filled: true)
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "███\n███")
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds) { context in
        context.rectangle(origin: CanvasPoint(x: -100, y: -100), width: 200, height: 200, filled: true)
    }.render(in: Rect(x: 1, y: 1, width: Int.max, height: Int.max), buffer: &buffer)
    #expect(buffer[0, 0].symbol == "█")
}

@Test func canvasOffscreenFilledRectangleDoesNotCollapseIntoTinyViewport() {
    var buffer = Buffer(width: 1, height: 1)
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .dot) { context in
        context.rectangle(origin: CanvasPoint(x: 3, y: 3), width: 1, height: 1, filled: true)
        context.print("outside", at: CanvasPoint(x: 3, y: 3))
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == " ")
}

@Test func canvasCircleAndDotMarkerPaintFiniteOutline() {
    var buffer = Buffer(width: 5, height: 5)
    Canvas(xBounds: CanvasBounds(min: -1, max: 1), yBounds: CanvasBounds(min: -1, max: 1), marker: .dot) { context in
        context.circle(center: CanvasPoint(x: 0, y: 0), radius: 1)
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[2, 0].symbol == "•")
    #expect(buffer[0, 2].symbol == "•")
    #expect(buffer[4, 2].symbol == "•")
    #expect(buffer[2, 4].symbol == "•")
    #expect(buffer[2, 2].symbol == " ")
}

@Test func canvasExtremeFiniteLinesKeepBothClipBoundaries() {
    let huge = Double.greatestFiniteMagnitude
    let endpoints: [(CanvasPoint, CanvasPoint)] = [
        (CanvasPoint(x: -huge, y: 0.5), CanvasPoint(x: huge, y: 0.5)),
        (CanvasPoint(x: 0.5, y: -huge), CanvasPoint(x: 0.5, y: huge)),
        (CanvasPoint(x: -huge, y: -huge), CanvasPoint(x: huge, y: huge)),
    ]
    for (index, segment) in endpoints.enumerated() {
        var buffer = Buffer(width: 3, height: 3)
        Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
            context.line(from: segment.0, to: segment.1)
        }.render(in: buffer.area, buffer: &buffer)
        let expected = ["   \n███\n   ", " █ \n █ \n █ ", "  █\n █ \n█  "]
        #expect(buffer.plainText == expected[index])
    }
}

@Test func canvasCustomShapesComposeDrawingCommands() {
    struct Shape: CanvasShape {
        func draw(in context: inout CanvasContext) {
            context.point(at: CanvasPoint(x: 0, y: 1))
        }
    }
    var buffer = Buffer(width: 1, height: 1)
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds) { context in
        context.draw(Shape())
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == "⠁")
}

@Test func canvasExtremeFiniteCrossingsRetainNonunitSlope() {
    let huge = Double.greatestFiniteMagnitude
    var buffer = Buffer(width: 5, height: 5)
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
        context.line(from: CanvasPoint(x: -huge, y: -huge / 2), to: CanvasPoint(x: huge, y: huge / 2))
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 4].symbol == "█")
    #expect(buffer[4, 2].symbol == "█")
    #expect(buffer[4, 0].symbol == " ")
    #expect(buffer[2, 2].symbol == " ")
    buffer.reset()
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
        context.line(from: CanvasPoint(x: -huge / 2, y: -huge), to: CanvasPoint(x: huge / 2, y: huge))
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 4].symbol == "█")
    #expect(buffer[2, 0].symbol == "█")
    #expect(buffer[4, 0].symbol == " ")
}

@Test func canvasClippingRejectsLinesBeyondCornersWithoutFabricatingDiagonals() {
    var buffer = Buffer(width: 5, height: 5)
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
        context.line(from: CanvasPoint(x: -2, y: 4.1), to: CanvasPoint(x: 4.1, y: -2))
        context.line(from: CanvasPoint(x: -4.1, y: 2), to: CanvasPoint(x: 2, y: -4.1))
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "     \n     \n     \n     \n     ")
    Canvas(xBounds: canvasBounds, yBounds: canvasBounds, marker: .block) { context in
        context.line(from: CanvasPoint(x: -2, y: 2.1), to: CanvasPoint(x: 2.1, y: -2))
    }.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 4].symbol == "█")
    #expect(buffer[4, 0].symbol == " ")
}
