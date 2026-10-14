import Testing

@testable import loom

@Test func gaugesClampRatiosAndDrawFractionalCells() {
    for (ratio, expected) in [(Double.nan, "    "), (.infinity, "    "), (-1, "    "), (2, "████"), (0.375, "█▌  ")] {
        var buffer = Buffer(width: 4, height: 1)
        Gauge(ratio: ratio).render(in: buffer.area, buffer: &buffer)
        #expect(buffer.plainText == expected)
    }
    var tiny = Buffer(width: 1, height: 1)
    Gauge(ratio: 0.5).render(in: tiny.area, buffer: &tiny)
    #expect(tiny.plainText == "▌")
    Gauge(ratio: 1).render(in: Rect(width: 0, height: 0), buffer: &tiny)
    #expect(tiny.plainText == "▌")
}

@Test func gaugesPlaceLabelsUsingTerminalCells() {
    var buffer = Buffer(width: 8, height: 2)
    Gauge(ratio: 1, label: "界", labelStyle: Style(bold: true)).render(
        in: Rect(width: 8, height: 1), buffer: &buffer)
    #expect(buffer[3, 0].symbol == "界")
    #expect(buffer[4, 0].width == 0)
    #expect(buffer[3, 0].style.bold)
    LineGauge(ratio: 0.5, label: "OK").render(in: Rect(y: 1, width: 8, height: 1), buffer: &buffer)
    #expect(buffer[0, 1].symbol == "O")
    #expect(buffer[3, 1].symbol == "█")
    #expect(buffer[5, 1].symbol == "▌")
}

@Test func fillAndClearPreserveWideGlyphsCrossingRectangleEdges() {
    var buffer = Buffer(width: 8, height: 1)
    buffer.put("界", width: 2, at: Point(x: 0, y: 0))
    buffer.put("界", width: 2, at: Point(x: 5, y: 0))
    Fill(".").render(in: Rect(x: 1, width: 5, height: 1), buffer: &buffer)
    #expect(buffer[0, 0].symbol == "界")
    #expect(buffer[1, 0].width == 0)
    #expect(buffer[2, 0].symbol == ".")
    #expect(buffer[5, 0].symbol == "界")
    #expect(buffer[6, 0].width == 0)
    Clear().render(in: Rect(x: 2, width: 2, height: 1), buffer: &buffer)
    #expect(buffer[2, 0].symbol == " ")
    #expect(buffer[4, 0].symbol == ".")
}

@Test func fillRejectsWideControlsAndMultipleGraphemes() {
    for symbol in ["界", "\n", "ab", "\u{301}"] {
        var buffer = Buffer(width: 3, height: 1)
        Fill(".").render(in: buffer.area, buffer: &buffer)
        Fill(symbol).render(in: buffer.area, buffer: &buffer)
        #expect(buffer.plainText == "...")
    }
    var buffer = Buffer(width: 1, height: 1)
    Fill("e\u{301}").render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == "e\u{301}")
}

@Test func tabsKeepSelectedVisibleAndHitTestPaintedPadding() {
    let tabs = Tabs([Tab(id: 10, label: "First"), Tab(id: 20, label: "界B")], selected: 20)
    var buffer = Buffer(width: 5, height: 2)
    tabs.render(in: Rect(width: 5, height: 1), buffer: &buffer)
    #expect(buffer[1, 0].symbol == "界")
    #expect(buffer[1, 0].style.reversed)
    for x in 0..<5 {
        #expect(tabs.hitTest(Point(x: x, y: 0), in: Rect(width: 5, height: 1)) == 20)
    }
    #expect(tabs.hitTest(Point(x: 1, y: 1), in: buffer.area) == nil)
    var tiny = Buffer(width: 1, height: 1)
    tabs.render(in: tiny.area, buffer: &tiny)
    #expect(tiny[0, 0].width == 1)
    #expect(tabs.hitTest(Point(x: 0, y: 0), in: tiny.area) == 20)
}

@Test func tabsExcludeSeparatorsFromHitTesting() {
    let tabs = Tabs([Tab(id: "a", label: "A"), Tab(id: "b", label: "B")], padding: 0)
    let area = Rect(x: 2, y: 1, width: 3, height: 1)
    var buffer = Buffer(width: 6, height: 3)
    tabs.render(in: area, buffer: &buffer)
    #expect(buffer[3, 1].symbol == "│")
    #expect(tabs.hitTest(Point(x: 3, y: 1), in: area) == nil)
    #expect(tabs.hitTest(Point(x: 4, y: 1), in: area) == "b")
}

@Test func richPanelTitlesStyleBothEdgesAndEarlierTitlesWin() {
    var buffer = Buffer(width: 14, height: 4)
    Panel(
        titles: [
            PanelTitle([TextSpan("A", style: Style(bold: true))]),
            PanelTitle([TextSpan("B")]),
            PanelTitle([TextSpan("界")], alignment: .right, position: .bottom),
        ], borderStyle: Style(dim: true), titleStyle: Style(italic: true)
    ).render(in: buffer.area, buffer: &buffer)
    #expect(buffer[2, 0].symbol == "A")
    #expect(buffer[2, 0].style.bold)
    #expect(!buffer[2, 0].style.dim)
    #expect(buffer[5, 0].style.dim)
    #expect(buffer[10, 3].symbol == "界")
    #expect(buffer[10, 3].style.italic)
    #expect(buffer[11, 3].width == 0)
}

@Test func panelTitlesClipWholeUnicodeGlyphsAndRespectDisabledEdges() {
    var tiny = Buffer(width: 3, height: 2)
    Panel(titles: [PanelTitle([TextSpan("界")])]).render(in: tiny.area, buffer: &tiny)
    #expect(tiny[0, 0].symbol == "┌")
    #expect(tiny[1, 0].symbol == " ")
    #expect(tiny[2, 0].symbol == "┐")
    var buffer = Buffer(width: 6, height: 3)
    Panel(borders: [.bottom], titles: [PanelTitle([TextSpan("Top")])]).render(
        in: buffer.area, buffer: &buffer)
    #expect(buffer[1, 0].symbol == " ")
    #expect(buffer[1, 2].symbol == "─")
}

@Test func richPanelTitlePatchesInheritTitleAppearance() {
    var buffer = Buffer(width: 8, height: 3)
    Panel(
        titles: [PanelTitle([TextSpan("A", patch: StylePatch(bold: true))])],
        titleStyle: Style(foreground: .indexed(3))
    ).render(in: buffer.area, buffer: &buffer)
    #expect(buffer[2, 0].style.bold)
    #expect(buffer[2, 0].style.foreground == .indexed(3))
}

@Test func panelBordersPreserveWideGlyphCrossingAssignedArea() {
    var buffer = Buffer(width: 6, height: 2)
    buffer.put("界", width: 2, at: Point(x: 0, y: 0))
    buffer.put("界", width: 2, at: Point(x: 3, y: 1))
    Panel().render(in: Rect(x: 1, width: 3, height: 2), buffer: &buffer)
    #expect(buffer[0, 0].symbol == "界")
    #expect(buffer[1, 0].width == 0)
    #expect(buffer[3, 1].symbol == "界")
    #expect(buffer[4, 1].width == 0)
    #expect(buffer[2, 0].symbol == "─")
}

@Test func lineGaugeLabelSeparatorPreservesWideGlyphCrossingAssignedArea() {
    var buffer = Buffer(width: 5, height: 1)
    buffer.put("界", width: 2, at: Point(x: 2, y: 0))
    LineGauge(ratio: 0.5, label: "A").render(in: Rect(x: 1, width: 2, height: 1), buffer: &buffer)
    #expect(buffer[1, 0].symbol == "A")
    #expect(buffer[2, 0].symbol == "界")
    #expect(buffer[3, 0].width == 0)
}

@Test func narrowTabsOmitWholeWideGraphemesInsteadOfSubstitution() {
    var buffer = Buffer(width: 1, height: 1)
    let tabs = Tabs([Tab(id: 1, label: "界")], selected: 1, padding: 0)
    tabs.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == " ")
    #expect(tabs.hitTest(Point(x: 0, y: 0), in: buffer.area) == 1)
}
