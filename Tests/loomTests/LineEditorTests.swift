import Foundation
import Testing

@testable import loom

@Test func editorMovesAndDeletesWholeGraphemes() {
    var editor = LineEditor()
    editor.insert("A👩🏽‍💻中")
    editor.handle(.left)
    editor.handle(.backspace)
    #expect(editor.text == "A中" && editor.cursor == 1)
    editor.insert("\n")
    #expect(editor.text == "A\n中")
    #expect(editor.layout(width: 20).1 == Point(x: 0, y: 1))
    editor.handle(.left)
    #expect(editor.layout(width: 20).1 == Point(x: 1, y: 0))
    editor.insert("\u{1b}[2J")
    #expect(!editor.text.contains("\u{1b}"))
}

@Test func editorSupportsWordMotionsSelectionAndUndoRedo() {
    var editor = LineEditor()
    editor.insert("hello, 👩🏽‍💻 world")
    editor.moveWordLeft()
    #expect(editor.cursor == "hello, 👩🏽‍💻 ".count)
    editor.deleteWordBackward()
    #expect(editor.text == "hello, world")
    editor.undo()
    #expect(editor.text == "hello, 👩🏽‍💻 world")
    editor.redo()
    #expect(editor.text == "hello, world")
    editor.moveHome()
    editor.moveWordRight(selecting: true)
    #expect(editor.selection == 0..<5)
    editor.insert("goodbye")
    #expect(editor.text == "goodbye, world")
    editor.undo()
    #expect(editor.text == "hello, world")
    editor.selectAll()
    editor.deleteForward()
    #expect(editor.text.isEmpty)
}

@Test func replacingPreviousGraphemeIsOneUndoableEdit() {
    var editor = LineEditor()
    editor.insert("first\\tail")
    editor.moveCursor(to: 6)
    editor.replacePreviousGrapheme(with: "\n")
    #expect(editor.text == "first\ntail")
    #expect(editor.cursor == 6)
    editor.undo()
    #expect(editor.text == "first\\tail")
    #expect(editor.cursor == 6)
    editor.redo()
    #expect(editor.text == "first\ntail")
}

@Test func verticalMovementFollowsWrappedRowsAndRetainsTheDesiredColumn() {
    var editor = LineEditor()
    editor.insert("abcdefghij")
    editor.moveCursor(to: 9)
    editor.moveVertical(by: -1, width: 4)
    #expect(editor.cursor == 5)
    editor.moveVertical(by: -1, width: 4)
    #expect(editor.cursor == 1)
    editor.moveVertical(by: 1, width: 4)
    #expect(editor.cursor == 5)

    editor.reset()
    editor.insert("abcd\nx\nwxyz")
    editor.moveVertical(by: -1, width: 20)
    #expect(editor.cursor == 6)
    editor.moveVertical(by: -1, width: 20)
    #expect(editor.cursor == 4)
    editor.moveVertical(by: 1, width: 20)
    #expect(editor.cursor == 6)
}

@Test func selectedEditorTextIsHighlightedInInput() {
    var editor = LineEditor()
    editor.insert("abc")
    editor.moveLeft(selecting: true)
    var input = TextInput(editor, prompt: "$")
    input.borders = []
    input.horizontalPadding = 0
    var buffer = Buffer(width: 12, height: 2)
    input.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[4, 0].symbol == "c")
    #expect(buffer[4, 0].style.reversed)
    #expect(!buffer[2, 0].style.reversed)
}

@Test func separatelyInsertedCombiningMarksKeepCursorInsideText() {
    var editor = LineEditor()
    editor.insert("e")
    editor.insert("\u{301}")
    #expect(editor.text == "e\u{301}")
    #expect(editor.cursor == 1)
    editor.insert("!")
    #expect(editor.text == "e\u{301}!")
    editor.deleteBackward()
    #expect(editor.text == "e\u{301}")
}
