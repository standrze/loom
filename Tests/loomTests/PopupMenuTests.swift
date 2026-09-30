import Testing

@testable import loom

@Test func popupErasesUnderlyingTextAndKeepsHitTestingAlignedWithScroll() {
    let items = (0..<12).map { PopupMenuItem("item\($0)", detail: "Description \($0)") }
    let menu = PopupMenu(items, selectedIndex: 8)
    let area = Rect(x: 2, y: 2, width: 38, height: 6)
    var buffer = Buffer(width: 42, height: 10)
    Paragraph(TextLayout(String(repeating: "x", count: 420), width: 42)).render(in: buffer.area, buffer: &buffer)
    menu.render(in: area, buffer: &buffer)
    #expect(menu.visibleRange(in: area) == 6..<10)
    #expect(menu.item(at: Point(x: 4, y: 3), in: area) == 6)
    #expect(menu.item(at: Point(x: 4, y: 5), in: area) == 8)
    #expect(menu.item(at: Point(x: 4, y: 2), in: area) == nil)
    #expect(menu.item(at: Point(x: 39, y: 5), in: area) == nil)
    #expect(buffer[3, 5].symbol == "❯")
    #expect(buffer[20, 5].style.reversed)
    #expect(!buffer[20, 4].style.reversed)
    #expect(buffer[35, 4].symbol == " ")
    #expect(buffer[0, 0].symbol == "x")
    #expect(buffer[39, 5].symbol == "█")
}

@Test func popupKeepsUnicodeColumnsAndDoesNotPaintOutsideItsArea() {
    let menu = PopupMenu([PopupMenuItem("中中", detail: "wide"), PopupMenuItem("abc", detail: "short")])
    let area = Rect(x: 1, y: 1, width: 24, height: 4)
    var buffer = Buffer(width: 28, height: 6)
    menu.render(in: area, buffer: &buffer)
    #expect(buffer[4, 2].symbol == "中")
    #expect(buffer[5, 2].width == 0)
    #expect(buffer[6, 2].symbol == "中")
    #expect(buffer[10, 2].symbol == "w")
    #expect(buffer[10, 3].symbol == "s")
    #expect(buffer[0, 2].symbol == " ")
    #expect(buffer[25, 2].symbol == " ")
    #expect(menu.height(maximumRows: 1) == 3)
}

@Test func emptyAndClippedPopupsAreSafeAndHaveNoSelectableRows() {
    let menu = PopupMenu([])
    var buffer = Buffer(width: 24, height: 6)
    let area = Rect(width: 24, height: 3)
    menu.render(in: area, buffer: &buffer)
    #expect(buffer.plainText.contains("No matches"))
    #expect(menu.visibleRange(in: area).isEmpty)
    #expect(menu.item(at: Point(x: 2, y: 1), in: area) == nil)
    for x in [-30, -1, 0, 23, 50] {
        for width in 0...5 {
            for height in 0...4 {
                menu.render(in: Rect(x: x, y: x, width: width, height: height), buffer: &buffer)
            }
        }
    }
}

@Test func popupHoverKeepsScrollAndKeyboardMarkerStable() {
    var menu = PopupMenu((0..<12).map { PopupMenuItem("item\($0)") }, selectedIndex: 8)
    let area = Rect(width: 40, height: 6)
    let range = menu.visibleRange(in: area)
    menu.hoveredIndex = 6
    #expect(menu.visibleRange(in: area) == range)
    var buffer = Buffer(width: 40, height: 6)
    menu.render(in: area, buffer: &buffer)
    #expect(buffer[1, 3].symbol == "❯")
    #expect(buffer[1, 1].symbol == " ")
    #expect(buffer[3, 1].style == menu.hoverStyle)
    menu.hoveredIndex = nil
    menu.render(in: area, buffer: &buffer)
    #expect(buffer[3, 1].style == menu.style)
}

@Test func fullBorderMenuHidesDecorationsAndPreservesClippedRowHits() {
    var menu = PopupMenu((0..<8).map { PopupMenuItem("/item\($0)", detail: "Description") }, selectedIndex: 6)
    menu.fullBorder = true
    menu.showsSelectionMarker = false
    menu.showsItemCount = false
    let area = Rect(x: 2, y: 1, width: 30, height: 5)
    var buffer = Buffer(width: 34, height: 8)
    menu.render(in: area, buffer: &buffer)
    #expect(buffer[area.x, area.y].symbol == "┌")
    #expect(buffer[area.maxX - 1, area.maxY - 1].symbol == "┘")
    #expect(buffer[area.maxX - 1, area.y + 1].symbol == "│")
    #expect(!buffer.plainText.contains("❯"))
    #expect(buffer[area.x + 1, area.y].symbol == "─")
    let range = menu.visibleRange(in: area)
    let selectedRow = area.y + 1 + menu.selectedIndex - range.lowerBound
    #expect(buffer[area.x + 1, selectedRow].symbol == "/")
    #expect(buffer[area.x + 1, selectedRow].style.bold)
    #expect(buffer[area.x + 1, selectedRow].style.reversed)
    #expect(menu.item(at: Point(x: area.x + 1, y: selectedRow), in: area) == 6)
    #expect(menu.item(at: Point(x: area.maxX - 2, y: selectedRow), in: area) == nil)
    #expect(menu.item(at: Point(x: area.maxX - 1, y: selectedRow), in: area) == nil)
}

@Test func titledPopupSharesItsScrollableRowsAndCloseControlWithHitTesting() throws {
    var menu = PopupMenu((0..<8).map { PopupMenuItem("Topic \($0)", detail: "Summary \($0)") }, selectedIndex: 6)
    menu.title = "Welcome"
    menu.introduction = "Pick a topic."
    menu.footer = "↑/↓ navigate  Enter open  Esc done"
    menu.showsCloseButton = true
    menu.showsSelectionMarker = false
    let area = Rect(x: 2, y: 1, width: 42, height: 11)
    var buffer = Buffer(width: 48, height: 14)
    menu.render(in: area, buffer: &buffer)

    #expect(menu.visibleRange(in: area) == 4..<8)
    #expect(menu.height(maximumRows: 8) == 15)
    #expect(buffer[area.x, area.y].symbol == "┌")
    #expect(buffer[area.maxX - 1, area.maxY - 1].symbol == "┘")
    #expect(buffer[area.x + 2, area.y].symbol == "W")
    #expect(buffer[area.x + 2, area.y].style.bold)
    #expect(buffer[area.x + 2, area.y + 2].symbol == "P")
    #expect(buffer[area.x + 2, area.y + 4].symbol == "T")
    #expect(menu.item(at: Point(x: area.x + 2, y: area.y + 4), in: area) == 4)
    #expect(menu.item(at: Point(x: area.x + 2, y: area.y + 6), in: area) == 6)
    #expect(menu.item(at: Point(x: area.x + 1, y: area.y + 4), in: area) == nil)
    #expect(menu.item(at: Point(x: area.maxX - 2, y: area.y + 4), in: area) == nil)
    for row in [area.y, area.y + 1, area.y + 2, area.y + 3, area.maxY - 3, area.maxY - 2, area.maxY - 1] {
        #expect(menu.item(at: Point(x: area.x + 2, y: row), in: area) == nil)
    }
    let close = try #require(menu.closeButtonArea(in: area))
    #expect(close == Rect(x: area.maxX - 5, y: area.y, width: 3, height: 1))
    #expect(buffer[close.x, close.y].symbol == "[")
    #expect(buffer[close.x + 1, close.y].symbol == "x")
    #expect(menu.item(at: Point(x: close.x, y: close.y), in: area) == nil)
    #expect(buffer.plainText.contains(menu.footer!))
}

@Test func titledPopupKeepsUnusedRowsUnselectableAndFitsSmallerTerminals() {
    var menu = PopupMenu([PopupMenuItem("Only choice")])
    menu.title = "Commands"
    menu.introduction = "Select a command."
    menu.footer = "Esc done"
    menu.showsCloseButton = true
    menu.showsSelectionMarker = false

    let tall = Rect(width: 40, height: 14)
    #expect(menu.item(at: Point(x: 2, y: 4), in: tall) == 0)
    #expect(menu.item(at: Point(x: 2, y: 5), in: tall) == nil)
    let compact = Rect(width: 40, height: 5)
    var buffer = Buffer(width: 40, height: 5)
    menu.render(in: compact, buffer: &buffer)
    #expect(!buffer.plainText.contains("Select a command."))
    #expect(buffer.plainText.contains("Esc done"))
    #expect(menu.item(at: Point(x: 2, y: 1), in: compact) == 0)
    #expect(menu.item(at: Point(x: 2, y: 2), in: compact) == nil)

    let tiny = Rect(width: 7, height: 3)
    buffer = Buffer(width: 7, height: 3)
    menu.render(in: tiny, buffer: &buffer)
    #expect(!buffer.plainText.contains("Esc done"))
    #expect(menu.closeButtonArea(in: tiny) == nil)
    #expect(menu.visibleRange(in: tiny) == 0..<1)
}

@Test func rightAlignedPopupDetailsUseTerminalColumnsAndKeepTheirMutedSelectionColor() {
    var menu = PopupMenu([PopupMenuItem("Go", detail: "東京"), PopupMenuItem("Longer", detail: "é")])
    menu.title = "Topics"
    menu.showsSelectionMarker = false
    menu.rightAlignsDetails = true
    menu.detailStyle = Style(foreground: .indexed(8), background: .indexed(0))
    menu.selectionStyle = Style(foreground: .indexed(15), background: .indexed(3))
    let area = Rect(x: 1, y: 1, width: 36, height: 6)
    var buffer = Buffer(width: 40, height: 9)
    menu.render(in: area, buffer: &buffer)

    #expect(buffer[31, 2].symbol == "東")
    #expect(buffer[32, 2].width == 0)
    #expect(buffer[33, 2].symbol == "京")
    #expect(buffer[34, 2].width == 0)
    #expect(buffer[31, 2].style.foreground == menu.detailStyle.foreground)
    #expect(buffer[31, 2].style.background == menu.selectionStyle.background)
    #expect(buffer[34, 3].symbol == "é")
    #expect(buffer[34, 3].style == menu.detailStyle)
    #expect(buffer[3, 2].style.bold)
    #expect(buffer[3, 2].style.foreground == menu.selectionStyle.foreground)
}

@Test func titledPopupChromeStaysInsideTinyAndClippedAreas() {
    var menu = PopupMenu((0..<12).map { PopupMenuItem("Topic \($0)", detail: "Description") }, selectedIndex: 8)
    menu.title = "Topics"
    menu.introduction = "Choose a topic."
    menu.footer = "Enter open  Esc done"
    menu.showsCloseButton = true
    menu.rightAlignsDetails = true
    for origin in [-4, 0, 10] {
        for width in 0...12 {
            for height in 0...9 {
                let area = Rect(x: origin, y: origin, width: width, height: height)
                var buffer = Buffer(width: 16, height: 12)
                Paragraph(TextLayout(String(repeating: "x", count: 192), width: 16))
                    .render(in: buffer.area, buffer: &buffer)
                menu.render(in: area, buffer: &buffer)
                for y in 0..<buffer.height {
                    for x in 0..<buffer.width where !area.contains(Point(x: x, y: y)) {
                        #expect(buffer[x, y].symbol == "x")
                    }
                }
            }
        }
    }
}
