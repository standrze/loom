import Testing

@testable import loom

@Test func textInputKeepsPlaceholderPromptAndCursorInsideRoundedPanel() {
    let input = TextInput(LineEditor(), placeholder: "Type here")
    let area = Rect(x: 3, y: 2, width: 20, height: input.height(width: 20))
    var buffer = Buffer(width: 30, height: 8)
    input.render(in: area, buffer: &buffer)

    #expect(area.height == 3)
    #expect(input.contentArea(in: area) == Rect(x: 7, y: 3, width: 14, height: 1))
    #expect(input.cursor(in: area) == Point(x: 7, y: 3))
    #expect(buffer[3, 2].symbol == "╭")
    #expect(buffer[22, 4].symbol == "╯")
    #expect(buffer[5, 3].symbol == "❯")
    #expect(buffer[7, 3].symbol == "T")
    #expect(buffer[7, 3].style.foreground == .indexed(8))
    #expect(buffer[22, 3].symbol == "│")
}

@Test func textInputPaintsFillOnTheCornerSideAndText() {
    var editor = LineEditor()
    editor.insert("Hi")
    var input = TextInput(editor)
    input.fill = .rgb(255, 255, 255)
    input.borderStyle = Style(foreground: .rgb(80, 80, 88))
    input.textColor = .rgb(24, 24, 24)
    input.promptColor = .rgb(35, 101, 209)
    input.placeholderColor = .rgb(105, 105, 105)
    let area = Rect(x: 2, y: 1, width: 16, height: input.height(width: 16))
    var buffer = Buffer(width: 20, height: 6)
    input.render(in: area, buffer: &buffer)

    let fill = Color.rgb(255, 255, 255)
    #expect(buffer[2, 1].symbol == "╭")
    #expect(buffer[2, 1].style.background == fill)
    #expect(buffer[2, 1].style.foreground == .rgb(80, 80, 88))
    #expect(buffer[2, 2].symbol == "│")
    #expect(buffer[2, 2].style.background == fill)
    #expect(buffer[3, 2].symbol == " ")
    #expect(buffer[3, 2].style.background == fill)
    #expect(buffer[4, 2].symbol == "❯")
    #expect(buffer[4, 2].style.background == fill)
    #expect(buffer[4, 2].style.foreground == .rgb(35, 101, 209))
    #expect(buffer[6, 2].symbol == "H")
    #expect(buffer[6, 2].style.background == fill)
    #expect(buffer[6, 2].style.foreground == .rgb(24, 24, 24))

    let empty = TextInput(LineEditor(), placeholder: "Type here")
    var placeholder = empty
    placeholder.fill = fill
    placeholder.placeholderColor = .rgb(105, 105, 105)
    buffer.reset()
    placeholder.render(in: area, buffer: &buffer)
    #expect(buffer[6, 2].symbol == "T")
    #expect(buffer[6, 2].style.foreground == .rgb(105, 105, 105))
    #expect(buffer[6, 2].style.background == fill)
}

@Test func textInputOpenSidesKeepTextAndCursorGeometry() {
    var editor = LineEditor()
    editor.insert("Hello")
    var input = TextInput(editor)
    let area = Rect(x: 3, y: 2, width: 20, height: input.height(width: 20))
    let originalContent = input.contentArea(in: area)
    let originalCursor = input.cursor(in: area)

    input.borders = [.top, .bottom]
    input.horizontalPadding = 2
    var buffer = Buffer(width: 30, height: 8)
    input.render(in: area, buffer: &buffer)

    #expect(input.height(width: 20) == 3)
    #expect(input.contentArea(in: area) == originalContent)
    #expect(input.cursor(in: area) == originalCursor)
    #expect(buffer[3, 2].symbol == "─")
    #expect(buffer[3, 3].symbol == " ")
    #expect(buffer[3, 4].symbol == "─")
    #expect(buffer[22, 2].symbol == "─")
    #expect(buffer[22, 3].symbol == " ")
    #expect(buffer[22, 4].symbol == "─")
}

@Test func textInputScrollsWithCursorAndCapsItsPreferredHeight() {
    var editor = LineEditor()
    editor.insert("abcdefghijkl")
    var input = TextInput(editor)
    let area = Rect(width: 12, height: input.height(width: 12))
    var buffer = Buffer(width: 12, height: 4)
    input.render(in: area, buffer: &buffer)

    #expect(area.height == 4)
    #expect(input.cursor(in: area) == Point(x: 4, y: 2))
    #expect(buffer[4, 1].symbol == "g")
    #expect(buffer[9, 1].symbol == "l")
    #expect(buffer[11, 1].symbol == "│")
    #expect(buffer[4, 2].symbol == " ")

    editor.handle(.home)
    input = TextInput(editor)
    buffer.reset()
    input.render(in: area, buffer: &buffer)
    #expect(input.cursor(in: area) == Point(x: 4, y: 1))
    #expect(buffer[4, 1].symbol == "a")
    #expect(buffer[4, 2].symbol == "g")
}

@Test func textInputReflowsWideTextUsingTheSameCursorGeometry() {
    var editor = LineEditor()
    editor.insert("A中B")
    let input = TextInput(editor, placeholder: "unused")
    let narrow = Rect(width: 10, height: input.height(width: 10))
    var buffer = Buffer(width: 10, height: 4)
    input.render(in: narrow, buffer: &buffer)

    #expect(narrow.height == 4)
    #expect(buffer[4, 1].symbol == "A")
    #expect(buffer[5, 1].symbol == "中")
    #expect(buffer[6, 1].width == 0)
    #expect(buffer[7, 1].symbol == "B")
    #expect(input.cursor(in: narrow) == Point(x: 4, y: 2))
    let wide = Rect(width: 20, height: input.height(width: 20))
    #expect(wide.height == 3)
    #expect(input.cursor(in: wide) == Point(x: 8, y: 1))
}

@Test func textInputHandlesTinyAreasAndAnEmptyPrompt() {
    var editor = LineEditor()
    editor.insert("x\ny\nz")
    let input = TextInput(editor, prompt: "", maximumRows: 1)
    let area = Rect(width: 10, height: input.height(width: 10))
    #expect(area.height == 3)
    #expect(input.contentArea(in: area) == Rect(x: 2, y: 1, width: 6, height: 1))
    #expect(input.cursor(in: area) == Point(x: 3, y: 1))
    #expect(TextInput(editor, maximumRows: 0).height(width: 20) == 3)

    for width in 0...6 {
        for height in 0...4 {
            let tiny = Rect(width: width, height: height)
            var buffer = Buffer(width: width, height: height)
            input.render(in: tiny, buffer: &buffer)
            if let cursor = input.cursor(in: tiny) {
                #expect(tiny.contains(cursor))
                #expect(input.contentArea(in: tiny).contains(cursor))
            }
        }
    }
}
