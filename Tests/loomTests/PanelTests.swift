import Foundation
import Testing

@testable import loom

@Test func panelDrawsSelectedEdgesAndReturnsPaddedInnerArea() {
    let panel = Panel(
        borders: [.top, .bottom], borderType: .rounded,
        padding: PanelPadding(left: 2, right: 1, top: 1)
    )
    let area = Rect(x: 2, y: 1, width: 10, height: 5)
    #expect(panel.inner(area) == Rect(x: 4, y: 3, width: 7, height: 2))
    var buffer = Buffer(width: 14, height: 7)
    panel.render(in: area, buffer: &buffer)
    #expect(buffer[2, 1].symbol == "─")
    #expect(buffer[11, 1].symbol == "─")
    #expect(buffer[2, 2].symbol == " ")
    #expect(buffer[11, 2].symbol == " ")
    #expect(buffer[2, 5].symbol == "─")
}

@Test func roundedAndDoubleBordersKeepTitlesInsideCorners() {
    let area = Rect(x: 1, y: 1, width: 12, height: 4)
    var rounded = Buffer(width: 14, height: 6)
    Panel(borderType: .rounded, title: "Hi").render(in: area, buffer: &rounded)
    #expect(rounded[1, 1].symbol == "╭")
    #expect(rounded[12, 1].symbol == "╮")
    #expect(rounded[2, 1].symbol == " ")
    #expect(rounded[3, 1].symbol == "H")
    #expect(rounded[1, 4].symbol == "╰")

    var double = Buffer(width: 14, height: 6)
    Panel(borderType: .double, title: "Hi", titleAlignment: .right).render(in: area, buffer: &double)
    #expect(double[1, 1].symbol == "╔")
    #expect(double[12, 1].symbol == "╗")
    #expect(double[8, 1].symbol == " ")
    #expect(double[9, 1].symbol == "H")
    #expect(double[1, 2].symbol == "║")
    #expect(double[12, 4].symbol == "╝")
}

@Test func panelPaddingClampsWhenAreaIsTooSmall() {
    let panel = Panel(padding: PanelPadding(all: 20))
    #expect(panel.inner(Rect(x: 4, y: 8, width: 3, height: 2)) == Rect(x: 7, y: 10, width: 0, height: 0))
}

@Test func panelBorderlessTitlesReserveOnlyOptedInRowsAndKeepDefaultGeometry() {
    let area = Rect(x: 1, y: 1, width: 10, height: 5)
    var panel = Panel(
        borders: [], title: "Header",
        titles: [
            PanelTitle([TextSpan("界")], alignment: .right, position: .bottom)
        ])
    #expect(panel.inner(area) == area)
    var buffer = Buffer(width: 12, height: 7)
    panel.render(in: area, buffer: &buffer)
    #expect(buffer.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    panel.titlesWithoutBorders = true
    #expect(panel.inner(area) == Rect(x: 1, y: 2, width: 10, height: 3))
    panel.render(in: area, buffer: &buffer)
    #expect(buffer[2, 1].symbol == "H")
    #expect(buffer[8, 5].symbol == "界")
    #expect(buffer[9, 5].width == 0)
    #expect(buffer[1, 2].symbol == " ")
    panel.borders = [.left, .right, .top]
    #expect(panel.inner(area) == Rect(x: 2, y: 2, width: 8, height: 3))
}

@Test func borderlessTitlesAgreeInPanelAndMergedLayerIncludingClippedAndTinyRows() {
    let panel = Panel(
        borders: [], title: "L",
        titles: [
            PanelTitle([TextSpan("R")], alignment: .right),
            PanelTitle([TextSpan("底")], alignment: .center, position: .bottom),
        ], titlesWithoutBorders: true)
    for area in [
        Rect(width: 8, height: 3), Rect(width: 8, height: 1), Rect(width: 1, height: 1), Rect(width: 0, height: 0),
    ] {
        var direct = Buffer(width: 8, height: 3)
        var merged = direct
        direct.withClip(Rect(x: 1, width: 6, height: 3)) { panel.render(in: area, buffer: &$0) }
        var layer = BorderLayer()
        layer.insert(panel, in: area)
        merged.withClip(Rect(x: 1, width: 6, height: 3)) { layer.render(buffer: &$0) }
        #expect(direct.plainText == merged.plainText)
        #expect(panel.inner(area).height >= 0)
    }
}
