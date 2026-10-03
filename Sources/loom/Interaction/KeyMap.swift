/// A logical key and its exact modifiers, ignoring Caps Lock and Num Lock.
///
/// Legacy Ctrl-C/Ctrl-D events match their extended-keyboard equivalents. Release events
/// and pasted text never activate a chord. `label` can override the generated help label.
public struct KeyChord: Equatable, Sendable {
    public var key: Key
    public var modifiers: KeyModifiers
    public var label: String?

    public init(_ key: Key, modifiers: KeyModifiers = [], label: String? = nil) {
        self.key = key
        self.modifiers = modifiers
        self.label = label
    }

    public func matches(_ event: InputEvent) -> Bool {
        guard let event = event.keyboardEvent, event.kind != .release else { return false }
        let expected = Self.normalized(key: key, modifiers: modifiers)
        let actual = Self.normalized(key: event.key, modifiers: event.modifiers)
        return expected.0 == actual.0 && expected.1 == actual.1
    }

    public var displayLabel: String {
        if let label { return label }
        let (key, modifiers) = Self.normalized(key: key, modifiers: modifiers)
        let names: [(KeyModifiers, String)] = [
            (.control, "Ctrl"), (.alt, "Alt"), (.shift, "Shift"),
            (.superKey, "Super"), (.hyper, "Hyper"), (.meta, "Meta"),
        ]
        return (names.filter { modifiers.contains($0.0) }.map { $0.1 } + [Self.name(key)]).joined(separator: "+")
    }

    private static func normalized(key: Key, modifiers: KeyModifiers) -> (Key, KeyModifiers) {
        var modifiers = modifiers.subtracting([.capsLock, .numLock])
        switch key {
        case .interrupt:
            modifiers.insert(.control)
            return (.character("c"), modifiers)
        case .endOfInput:
            modifiers.insert(.control)
            return (.character("d"), modifiers)
        case .f2:
            return (.function(2), modifiers)
        default:
            return (key, modifiers)
        }
    }

    private static func name(_ key: Key) -> String {
        switch key {
        case let .character(text): return text == " " ? "Space" : text
        case let .function(number): return "F\(number)"
        case .unknown: return "Unknown"
        case .enter: return "Enter"
        case .tab: return "Tab"
        case .backspace: return "Backspace"
        case .delete: return "Delete"
        case .insert: return "Insert"
        case .escape: return "Esc"
        case .interrupt: return "Ctrl+c"
        case .endOfInput: return "Ctrl+d"
        case .newline: return "Newline"
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        case .first: return "First"
        case .last: return "Last"
        case .f2: return "F2"
        }
    }
}

/// One application action, its remappable chords, and its user-facing description.
public struct KeyBinding<Action> {
    public var action: Action
    public var keys: [KeyChord]
    public var help: String
    public var isEnabled = true
    public var isHidden = false
    public var acceptsRepeat = true

    public init(_ action: Action, keys: [KeyChord], help: String) {
        self.action = action
        self.keys = keys
        self.help = help
    }
}

/// Resolves keys in declaration order; the first enabled matching binding wins.
public struct KeyMap<Action> {
    public var bindings: [KeyBinding<Action>]

    public init(_ bindings: [KeyBinding<Action>]) {
        self.bindings = bindings
    }

    public func action(for event: InputEvent) -> Action? {
        guard let keyboard = event.keyboardEvent, keyboard.kind != .release else { return nil }
        return bindings.first {
            $0.isEnabled && ($0.acceptsRepeat || keyboard.kind != .repeated)
                && $0.keys.contains { $0.matches(event) }
        }?.action
    }

    /// Help is derived from the same active bindings used for dispatch.
    public var helpText: String {
        bindings.filter { $0.isEnabled && !$0.isHidden && !$0.keys.isEmpty }
            .map { $0.keys.map(\.displayLabel).joined(separator: "/") + " " + $0.help }
            .joined(separator: "  ")
    }
}

extension KeyBinding: Sendable where Action: Sendable {}
extension KeyMap: Sendable where Action: Sendable {}
