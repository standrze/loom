import Testing

@testable import loom

@Test func stableSelectionSurvivesSortAndReconcilesFiltering() {
    var state = SelectionState(selectedID: "b")
    state.update(ids: ["a", "b", "c", "d"], heights: [1, 1, 1, 1], viewportLength: 2)
    state.toggleMarked("a")
    state.toggleMarked("c")
    state.update(ids: ["d", "c", "b", "a"], heights: [1, 1, 1, 1], viewportLength: 2)
    #expect(state.selectedID == "b")
    #expect(state.selectedIndex == 2)
    #expect(state.scroll.offset == 1)
    #expect(state.markedIDs == ["a", "c"])
    state.update(ids: ["d", "c"], heights: [1, 1], viewportLength: 2)
    #expect(state.selectedID == "c")
    #expect(state.markedIDs == ["c"])
    state.update(ids: [], heights: [], viewportLength: 0)
    #expect(state.selectedID == nil)
    #expect(state.markedIDs.isEmpty)
    #expect(state.visibleIndices.isEmpty)
}

@Test func manualScrollingIsIndependentFromSelectionUntilNavigation() {
    var state = SelectionState(selectedID: 8)
    state.update(ids: Array(0..<10), heights: Array(repeating: 1, count: 10), viewportLength: 3)
    #expect(state.scroll.offset == 6)
    state.scroll.scroll(to: 0)
    state.update(ids: Array(0..<10), heights: Array(repeating: 1, count: 10), viewportLength: 3)
    #expect(state.scroll.offset == 0)
    #expect(state.selectedID == 8)
    state.moveSelection(by: 1)
    #expect(state.selectedID == 9)
    #expect(state.scroll.offset == 7)
    state.update(ids: Array(0..<10), heights: Array(repeating: 1, count: 10), viewportLength: 5)
    #expect(state.scroll.offset == 5)
}

@Test func variableHeightPagingAndHitTestingUseTerminalRows() {
    var state = SelectionState(selectedID: 1)
    state.update(ids: [0, 1, 2, 3], heights: [2, 3, 1, 4], viewportLength: 4)
    #expect(state.rowRange(at: 1) == 2..<5)
    #expect(state.index(atRow: 4) == 1)
    #expect(state.index(atRow: 5) == 2)
    #expect(state.index(atRow: 10) == nil)
    state.pageSelection(by: 1)
    #expect(state.selectedID == 3)
    #expect(state.scroll.offset == 6)
    #expect(state.visibleIndices == 3..<4)
    state.pageSelection(by: -1)
    #expect(state.selectedID == 1)
    state.moveSelection(by: Int.max)
    #expect(state.selectedID == 3)
    state.moveSelection(by: Int.min)
    #expect(state.selectedID == 0)
}

@Test func marksAndNavigationAreExplicitAndIgnoreTextPastes() {
    var state = SelectionState<Int>()
    state.update(ids: [1, 2, 3], heights: [1, 1, 1], viewportLength: 2)
    #expect(state.selectedID == nil)
    #expect(state.handle(.key(.down)) == true)
    #expect(state.selectedID == 1)
    #expect(state.handle(.text(" ")) == false)
    #expect(state.handle(.text(" "), allowsMultipleSelection: true) == true)
    #expect(state.markedIDs == [1])
    #expect(state.handle(.paste(" "), allowsMultipleSelection: true) == false)
    #expect(state.handle(.keyEvent(KeyEvent(key: .down, modifiers: .alt))) == false)
    state.markAll()
    #expect(state.markedIDs == [1, 2, 3])
    state.clearMarks()
    #expect(state.markedIDs.isEmpty)
}
