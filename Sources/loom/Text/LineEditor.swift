import Foundation
import weft

/// A plain-text draft whose cursor and selection use extended grapheme clusters.
public struct LineEditor: Sendable {
    public private(set) var text = ""

    /// Cursor offset in grapheme clusters, not UTF-8 bytes or terminal cells.
    public private(set) var cursor = 0
    public private(set) var selectionAnchor: Int?

    private struct Snapshot: Sendable {
        let text: String
        let cursor: Int
        let selectionAnchor: Int?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var coalescesInsertion = false
    private var verticalColumn: Int?

    public init() {}

    /// A half-open grapheme range, or nil when nothing is selected.
    public var selection: Range<Int>? {
        guard let selectionAnchor, selectionAnchor != cursor else { return nil }
        return min(selectionAnchor, cursor)..<max(selectionAnchor, cursor)
    }

    public mutating func reset() {
        text = ""
        cursor = 0
        selectionAnchor = nil
        undoStack = []
        redoStack = []
        coalescesInsertion = false
        verticalColumn = nil
    }

    /// Inserts sanitized text, replacing the current selection if present.
    public mutating func insert(_ value: String) {
        let sanitized = String(
            value.unicodeScalars.filter {
                $0 == "\n" || $0 == "\t" || ($0.value >= 32 && !(0x7f...0x9f).contains($0.value))
            })
        guard !sanitized.isEmpty else { return }
        let selectedBytes = selection.map { bytes(in: $0) } ?? 0
        guard text.utf8.count - selectedBytes + sanitized.utf8.count <= 65_536 else { return }
        saveUndo(coalesce: coalescesInsertion && selection == nil)
        let range = selection ?? cursor..<cursor
        let replacementRange = indices(for: range)
        let prefix = String(text[..<replacementRange.lowerBound]) + sanitized
        text.replaceSubrange(replacementRange, with: sanitized)
        cursor = min(text.count, prefix.count)
        selectionAnchor = nil
        coalescesInsertion = true
        verticalColumn = nil
    }

    /// Moves by one grapheme, optionally extending the selection.
    public mutating func moveLeft(selecting: Bool = false) {
        if !selecting, let selection {
            move(to: selection.lowerBound, selecting: false)
        } else {
            move(to: cursor - 1, selecting: selecting)
        }
    }

    /// Moves by one grapheme, optionally extending the selection.
    public mutating func moveRight(selecting: Bool = false) {
        if !selecting, let selection {
            move(to: selection.upperBound, selecting: false)
        } else {
            move(to: cursor + 1, selecting: selecting)
        }
    }

    /// Moves across whitespace and one word or punctuation run.
    public mutating func moveWordLeft(selecting: Bool = false) {
        move(to: wordBoundaryLeft(from: cursor), selecting: selecting)
    }

    /// Moves across one word or punctuation run and trailing whitespace.
    public mutating func moveWordRight(selecting: Bool = false) {
        move(to: wordBoundaryRight(from: cursor), selecting: selecting)
    }

    public mutating func moveHome(selecting: Bool = false) {
        move(to: 0, selecting: selecting)
    }

    public mutating func moveEnd(selecting: Bool = false) {
        move(to: text.count, selecting: selecting)
    }

    /// Moves to a grapheme offset, optionally extending the current selection.
    public mutating func moveCursor(to offset: Int, selecting: Bool = false) {
        move(to: offset, selecting: selecting)
    }

    /// Moves between displayed rows, retaining the desired terminal column across short rows.
    public mutating func moveVertical(by rows: Int, width: Int, selecting: Bool = false) {
        guard rows != 0 else { return }
        let (layout, position) = layout(width: width)
        let targetRow = min(max(0, position.y + rows), layout.lines.count - 1)
        guard targetRow != position.y else { return }
        let desiredColumn = verticalColumn ?? position.x
        var offsets: [String.Index: Int] = [:]
        var characters: [Character] = []
        for index in layout.source.indices {
            offsets[index] = characters.count
            characters.append(layout.source[index])
        }
        offsets[layout.source.endIndex] = characters.count
        var nextOffset = 0
        var rowStarts: [Int] = []
        for line in layout.lines {
            rowStarts.append(nextOffset)
            if let last = line.glyphs.last {
                nextOffset = offsets[last.sourceRange.upperBound] ?? nextOffset
            }
            if characters.indices.contains(nextOffset), characters[nextOffset] == "\n" {
                nextOffset += 1
            }
        }
        let target = layout.lines[targetRow]
        var offset = rowStarts[targetRow]
        for glyph in target.glyphs where glyph.column < desiredColumn {
            offset = offsets[glyph.sourceRange.upperBound] ?? offset
        }
        move(to: min(text.count, offset), selecting: selecting)
        verticalColumn = desiredColumn
    }

    public mutating func selectAll() {
        selectionAnchor = 0
        cursor = text.count
        coalescesInsertion = false
        verticalColumn = nil
    }

    /// Deletes the selected text or the preceding grapheme.
    public mutating func deleteBackward() {
        let range = selection ?? max(0, cursor - 1)..<cursor
        delete(range)
    }

    /// Deletes a grapheme-offset range as one edit, preserving the original cursor and selection for undo.
    ///
    /// Empty and out-of-bounds ranges do not modify the draft or its undo history.
    public mutating func delete(in range: Range<Int>) {
        guard range.lowerBound >= 0, range.upperBound <= text.count else { return }
        delete(range)
    }

    /// Replaces the preceding grapheme as one undoable edit.
    public mutating func replacePreviousGrapheme(with value: String) {
        guard selection == nil, cursor > 0 else { return }
        let sanitized = String(
            value.unicodeScalars.filter {
                $0 == "\n" || $0 == "\t" || ($0.value >= 32 && !(0x7f...0x9f).contains($0.value))
            })
        guard !sanitized.isEmpty else { return }
        let range = (cursor - 1)..<cursor
        guard text.utf8.count - bytes(in: range) + sanitized.utf8.count <= 65_536 else { return }
        saveUndo()
        let replacementRange = indices(for: range)
        let prefix = String(text[..<replacementRange.lowerBound]) + sanitized
        text.replaceSubrange(replacementRange, with: sanitized)
        cursor = min(text.count, prefix.count)
        verticalColumn = nil
    }

    /// Deletes the selected text or the following grapheme.
    public mutating func deleteForward() {
        let range = selection ?? cursor..<min(text.count, cursor + 1)
        delete(range)
    }

    public mutating func deleteWordBackward() {
        delete(selection ?? wordBoundaryLeft(from: cursor)..<cursor)
    }

    public mutating func deleteWordForward() {
        delete(selection ?? cursor..<wordBoundaryRight(from: cursor))
    }

    /// Restores the draft before the most recent edit.
    public mutating func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        restore(snapshot)
    }

    /// Reapplies the most recently undone edit.
    public mutating func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        restore(snapshot)
    }

    public mutating func handle(_ key: Key) {
        switch key {
        case .left: moveLeft()
        case .right: moveRight()
        case .home: moveHome()
        case .end: moveEnd()
        case .backspace: deleteBackward()
        case .delete: deleteForward()
        case .newline: insert("\n")
        default: break
        }
    }

    public func layout(width: Int) -> (TextLayout, Point) {
        let layout = TextLayout(text + " ", width: width)
        let prefix = TextLayout(String(text.prefix(cursor)), width: width)
        let lastGlyph = prefix.lines.last!.glyphs.last
        let column = lastGlyph.map { $0.column + $0.width } ?? 0
        let row = prefix.lines.count - 1
        return (layout, column >= max(1, width) ? Point(x: 0, y: row + 1) : Point(x: column, y: row))
    }

    private var currentSnapshot: Snapshot {
        Snapshot(text: text, cursor: cursor, selectionAnchor: selectionAnchor)
    }

    private mutating func saveUndo(coalesce: Bool = false) {
        if !coalesce {
            undoStack.append(currentSnapshot)
            if undoStack.count > 100 { undoStack.removeFirst() }
        }
        redoStack = []
        coalescesInsertion = false
        verticalColumn = nil
    }

    private mutating func restore(_ snapshot: Snapshot) {
        text = snapshot.text
        cursor = snapshot.cursor
        selectionAnchor = snapshot.selectionAnchor
        coalescesInsertion = false
        verticalColumn = nil
    }

    private mutating func move(to position: Int, selecting: Bool) {
        if selecting {
            if selectionAnchor == nil { selectionAnchor = cursor }
        } else {
            selectionAnchor = nil
        }
        cursor = min(text.count, max(0, position))
        coalescesInsertion = false
        verticalColumn = nil
    }

    private mutating func delete(_ range: Range<Int>) {
        guard !range.isEmpty else { return }
        saveUndo()
        text.removeSubrange(indices(for: range))
        cursor = range.lowerBound
        selectionAnchor = nil
        verticalColumn = nil
    }

    private func indices(for range: Range<Int>) -> Range<String.Index> {
        text.index(
            text.startIndex, offsetBy: range.lowerBound)..<text.index(text.startIndex, offsetBy: range.upperBound)
    }

    private func bytes(in range: Range<Int>) -> Int {
        text[indices(for: range)].utf8.count
    }

    private func wordBoundaryLeft(from position: Int) -> Int {
        let characters = Array(text)
        var target = position
        while target > 0 && characters[target - 1].isWhitespace { target -= 1 }
        guard target > 0 else { return 0 }
        let word = isWord(characters[target - 1])
        while target > 0 && !characters[target - 1].isWhitespace && isWord(characters[target - 1]) == word {
            target -= 1
        }
        return target
    }

    private func wordBoundaryRight(from position: Int) -> Int {
        let characters = Array(text)
        var target = position
        guard target < characters.count else { return target }
        if !characters[target].isWhitespace {
            let word = isWord(characters[target])
            while target < characters.count && !characters[target].isWhitespace && isWord(characters[target]) == word {
                target += 1
            }
        }
        while target < characters.count && characters[target].isWhitespace { target += 1 }
        return target
    }

    private func isWord(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0.value == 95 }
    }
}
