import Testing

@testable import loom

@Test func focusTraversesEnabledTargetsAndRestoresNestedScopes() {
    var state = FocusState([FocusTarget("search"), FocusTarget("disabled", isEnabled: false), FocusTarget("table")])
    #expect(state.focusedID == "search")
    #expect(state.handle(.key(.tab)) == true)
    #expect(state.focusedID == "table")
    state.moveForward()
    #expect(state.focusedID == "search")
    #expect(state.handle(.keyEvent(KeyEvent(key: .tab, modifiers: .shift))) == true)
    #expect(state.focusedID == "table")
    state.pushScope([FocusTarget("cancel"), FocusTarget("confirm")])
    #expect(state.scopeDepth == 2)
    #expect(state.focus("table") == false)
    state.moveBackward()
    #expect(state.focusedID == "confirm")
    state.pushScope([FocusTarget("nested")])
    #expect(state.popScope() == true)
    #expect(state.focusedID == "confirm")
    #expect(state.popScope() == true)
    #expect(state.focusedID == "table")
    #expect(state.popScope() == false)
    state.update([FocusTarget("search"), FocusTarget("table", isEnabled: false)])
    #expect(state.focusedID == "search")
    state.update([])
    #expect(state.focusedID == nil)
}

@Test func focusClickUsesTopmostEnabledRegionAndStaysInsideModal() {
    let area = Rect(x: 2, y: 2, width: 4, height: 2)
    var state = FocusState([
        FocusTarget("back", area: area), FocusTarget("front", area: area),
        FocusTarget("disabled", area: area, isEnabled: false),
    ])
    let click = InputEvent.mouse(MouseEvent(kind: .down, position: Point(x: 3, y: 2)))
    #expect(state.handle(click) == true)
    #expect(state.focusedID == "front")
    state.pushScope([FocusTarget("modal", area: Rect(width: 1, height: 1))])
    #expect(state.handle(click) == false)
    #expect(state.focusedID == "modal")
    #expect(state.handle(.keyEvent(KeyEvent(key: .tab, kind: .release))) == false)
    #expect(state.handle(.keyEvent(KeyEvent(key: .tab, modifiers: .control))) == false)
    state.popScope()
    state.wraps = false
    state.moveForward()
    #expect(state.focusedID == "front")
}

@Test func remappedBindingsAndHelpStayTogether() {
    var map = KeyMap([
        KeyBinding("quit", keys: [KeyChord(.character("q"))], help: "quit"),
        KeyBinding("next", keys: [KeyChord(.down), KeyChord(.character("j"))], help: "next"),
    ])
    #expect(map.action(for: .text("q")) == "quit")
    map.bindings[0].keys = [KeyChord(.character("c"), modifiers: .control)]
    #expect(map.action(for: .text("q")) == nil)
    #expect(map.action(for: .key(.interrupt)) == "quit")
    #expect(map.action(for: .keyEvent(KeyEvent(key: .character("c"), modifiers: [.control, .capsLock]))) == "quit")
    #expect(map.helpText == "Ctrl+c quit  ↓/j next")
    map.bindings[1].isEnabled = false
    #expect(map.action(for: .key(.down)) == nil)
    #expect(map.helpText == "Ctrl+c quit")
    map.bindings[0].isHidden = true
    #expect(map.helpText.isEmpty)
    #expect(map.action(for: .key(.interrupt)) == "quit")
}

@Test func bindingsRejectPastesReleasesAndUnexpectedModifiers() {
    var first = KeyBinding("first", keys: [KeyChord(.enter)], help: "activate")
    first.acceptsRepeat = false
    let map = KeyMap([first, KeyBinding("fallback", keys: [KeyChord(.enter)], help: "fallback")])
    #expect(map.action(for: .key(.enter)) == "first")
    #expect(map.action(for: .keyEvent(KeyEvent(key: .enter, kind: .repeated))) == "fallback")
    #expect(map.action(for: .keyEvent(KeyEvent(key: .enter, kind: .release))) == nil)
    #expect(map.action(for: .keyEvent(KeyEvent(key: .enter, modifiers: .alt))) == nil)
    #expect(map.action(for: .paste("\r")) == nil)
    #expect(map.action(for: .text("many characters")) == nil)
    #expect(KeyChord(.function(2)).matches(.key(.f2)))
    #expect(KeyChord(.character("d"), modifiers: .control).matches(.key(.endOfInput)))
}

@Test func keyHelpWrapsAndRendersOnlyActiveBindings() {
    var disabled = KeyBinding(2, keys: [KeyChord(.escape)], help: "hidden")
    disabled.isEnabled = false
    let help = KeyHelp(
        KeyMap([KeyBinding(1, keys: [KeyChord(.tab)], help: "focus"), disabled]), style: Style(bold: true))
    var buffer = Buffer(width: 12, height: 2)
    help.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText.contains("Tab focus"))
    #expect(!buffer.plainText.contains("hidden"))
    #expect(buffer[0, 0].style.bold)
}
