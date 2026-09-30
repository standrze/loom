import Testing

@testable import loom

@Test func characterArtPreservesSpacingAndTrailingEmptyRows() {
    let style = Style(foreground: .indexed(3), background: .indexed(0))
    let art = CharacterArt(" A  \nB\n", style: style)
    #expect(art.width == 4)
    #expect(art.height == 3)
    var buffer = Buffer(width: 5, height: 4)
    buffer.put("x", width: 1, at: Point(x: 3, y: 2))
    art.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == " A   \nB    \n     \n     ")
    #expect(buffer[3, 2].style == style)
    #expect(buffer[4, 2] == Cell())
    #expect(buffer[0, 3] == Cell())
    #expect(CharacterArt("").width == 0)
    #expect(CharacterArt("").height == 1)
}

@Test func characterArtClipsWithoutWrappingAndPreservesOffscreenCoordinates() {
    let art = CharacterArt("abcdef\nghijkl\nmnopqr")
    var buffer = Buffer(width: 5, height: 3)
    art.render(in: Rect(x: 1, y: 1, width: 3, height: 1), buffer: &buffer)
    #expect(buffer.plainText == "     \n abc \n     ")
    buffer.reset()
    art.render(in: Rect(x: -2, y: -1, width: 6, height: 3), buffer: &buffer)
    #expect(buffer.plainText == "ijkl \nopqr \n     ")
}

@Test func characterArtClipsWholeWideGraphemesAtEveryEdge() {
    let art = CharacterArt("界A界")
    #expect(art.width == 5)
    var buffer = Buffer(width: 4, height: 1)
    art.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[0, 0].symbol == "界")
    #expect(buffer[1, 0].width == 0)
    #expect(buffer[2, 0].symbol == "A")
    #expect(buffer[3, 0].symbol == " ")

    buffer.reset()
    art.render(in: Rect(x: -1, width: 5, height: 1), buffer: &buffer)
    #expect(buffer[0, 0].symbol == " ")
    #expect(buffer[1, 0].symbol == "A")
    #expect(buffer[2, 0].symbol == "界")
    #expect(buffer[3, 0].width == 0)

    buffer.reset()
    art.render(in: Rect(x: 3, width: 5, height: 1), buffer: &buffer)
    #expect(buffer[3, 0].symbol == " ")
}

@Test func characterArtUsesFourSpaceTabsControlFilteringAndGraphemeGeometry() {
    let art = CharacterArt("A\tB\u{07}\u{1B}\u{009B}\ne\u{0301}\tC")
    #expect(art.width == 6)
    #expect(art.height == 2)
    var buffer = Buffer(width: 6, height: 2)
    art.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "A    B\ne\u{0301}    C")
    #expect(buffer[0, 1].width == 1)
}

@Test func characterArtIgnoresEmptyAndExtremelyOffscreenAreas() {
    let art = CharacterArt("ABC\nDEF")
    var buffer = Buffer(width: 2, height: 2)
    let areas = [
        Rect(width: 0, height: 1), Rect(width: 1, height: 0),
        Rect(x: Int.min, y: Int.min, width: Int.max, height: Int.max),
        Rect(x: Int.max, y: Int.max, width: Int.max, height: Int.max),
    ]
    for area in areas {
        art.render(in: area, buffer: &buffer)
    }
    #expect(buffer.plainText == "  \n  ")
    var empty = Buffer(width: 0, height: 0)
    art.render(in: Rect(width: 1, height: 1), buffer: &empty)
    #expect(empty.plainText.isEmpty)
}
