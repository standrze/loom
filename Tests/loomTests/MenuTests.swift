import Testing

@testable import loom

@Test func menuAlignsHintsAndSharesHitGeometry() {
    let menu = Menu([MenuItem("Models", hint: "/models"), MenuItem("Help")], selectedIndex: 0)
    let area = Rect(x: 2, y: 1, width: 24, height: 2)
    var buffer = Buffer(width: 30, height: 5)
    menu.render(in: area, buffer: &buffer)
    #expect(buffer[2, 1].symbol == "M")
    #expect(buffer[19, 1].symbol == "/")
    #expect(buffer[25, 1].symbol == "s")
    #expect(buffer[12, 1].style.reversed)
    #expect(!buffer[2, 2].style.reversed)
    #expect(menu.item(at: Point(x: 25, y: 2), in: area) == 1)
    #expect(menu.item(at: Point(x: 26, y: 2), in: area) == nil)
}

@Test func menuClipsLabelsAndHidesHintsInNarrowAreas() {
    let menu = Menu([MenuItem("中中中中", hint: "/help"), MenuItem("Hidden")])
    var buffer = Buffer(width: 8, height: 3)
    menu.render(in: Rect(x: 1, y: 1, width: 5, height: 1), buffer: &buffer)
    #expect(buffer[1, 1].symbol == "中")
    #expect(buffer[3, 1].symbol == "中")
    #expect(buffer[5, 1].symbol == " ")
    #expect(buffer[6, 1].symbol == " ")
    #expect(buffer[1, 2].symbol == " ")
}
