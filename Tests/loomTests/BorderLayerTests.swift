import Testing

@testable import loom

@Test func customBordersRejectWideAndControlSymbols() {
    for glyph in ["界", "\u{1b}", "ab", "\u{301}"] {
        #expect(throws: BorderSymbols.ValidationError.self) {
            try BorderSymbols(
                horizontal: glyph, vertical: "|", topLeft: "+", topRight: "+",
                bottomLeft: "+", bottomRight: "+")
        }
    }
}

@Test func borderLayerMergesSharedEdgesAndUsesLaterAppearance() {
    var layer = BorderLayer()
    layer.insert(Panel(), in: Rect(width: 5, height: 3))
    layer.insert(Panel(borderType: .double), in: Rect(x: 4, width: 5, height: 3))
    var buffer = Buffer(width: 9, height: 4)
    layer.render(buffer: &buffer)
    #expect(buffer[4, 0].symbol == "╦")
    #expect(buffer[4, 2].symbol == "╩")
    buffer.put("X", width: 1, at: Point(x: 4, y: 0))
    #expect(buffer[4, 0].symbol == "X")
}

@Test func panelShadowRespectsEnclosingClipAndPanelInterior() throws {
    let panel = Panel(shadow: try PanelShadow(offsetX: 1, offsetY: 1, glyph: "."))
    var buffer = Buffer(width: 6, height: 5)
    buffer.withClip(Rect(width: 4, height: 4)) { target in
        panel.render(in: Rect(width: 4, height: 3), buffer: &target)
    }
    #expect(buffer[1, 1].symbol == " ")
    #expect(buffer[1, 3].symbol == ".")
    #expect(buffer[4, 2].symbol == " ")
}

@Test func borderLayerPreservesMixedAxisWeightsAndLaterStyle() {
    let laterStyle = Style(bold: true)
    for horizontalDouble in [false, true] {
        var layer = BorderLayer()
        layer.insert(
            Panel(borders: .left, borderType: horizontalDouble ? .single : .double),
            in: Rect(x: 2, y: 0, width: 3, height: 5))
        layer.insert(
            Panel(
                borders: .top, borderType: horizontalDouble ? .double : .single,
                borderStyle: laterStyle), in: Rect(x: 0, y: 2, width: 5, height: 3))
        var buffer = Buffer(width: 5, height: 5)
        layer.render(buffer: &buffer)
        #expect(buffer[2, 2].symbol == (horizontalDouble ? "╪" : "╫"))
        #expect(buffer[2, 2].style == laterStyle)
    }
}

@Test func mixedBorderGlyphsCoverCornersAndTees() {
    #expect(BorderType.double.symbol(for: 6, doubleConnections: 2) == "╒")
    #expect(BorderType.single.symbol(for: 9, doubleConnections: 1) == "╜")
    #expect(BorderType.double.symbol(for: 7, doubleConnections: 2) == "╞")
    #expect(BorderType.single.symbol(for: 14, doubleConnections: 4) == "╥")
}

@Test func shadowExtremeTranslationsAndDimensionsRemainClipped() throws {
    var buffer = Buffer(width: 4, height: 4)
    for offset in [Int.min, Int.max] {
        let panel = Panel(shadow: try PanelShadow(offsetX: offset, offsetY: offset, glyph: "."))
        panel.renderShadow(in: Rect(x: 1, y: 1, width: 2, height: 2), buffer: &buffer)
    }
    #expect(buffer.plainText == "    \n    \n    \n    ")
    let huge = Panel(shadow: try PanelShadow(offsetX: 0, offsetY: 1, glyph: "."))
    huge.renderShadow(in: Rect(x: 1, y: 0, width: Int.max, height: 2), buffer: &buffer)
    #expect(buffer[1, 2].symbol == ".")
    #expect(buffer[0, 2].symbol == " ")
}

@Test func borderLayerExtremeGeometryPreservesRealEdgesAndNestedClip() {
    var layer = BorderLayer()
    layer.insert(Panel(), in: Rect(x: 1, y: 1, width: Int.max, height: Int.max))
    layer.insert(Panel(), in: Rect(x: Int.min, y: Int.min, width: Int.max, height: Int.max))
    var buffer = Buffer(width: 5, height: 5)
    buffer.withClip(Rect(x: 1, y: 1, width: 3, height: 3)) { outer in
        outer.withClip(Rect(x: 2, y: 1, width: 2, height: 2)) { inner in
            layer.render(buffer: &inner)
        }
    }
    #expect(buffer[2, 1].symbol == "─")
    #expect(buffer[3, 1].symbol == "─")
    #expect(buffer[4, 1].symbol == " ")
    #expect(buffer[1, 1].symbol == " ")
    #expect(buffer[2, 2].symbol == " ")
}
