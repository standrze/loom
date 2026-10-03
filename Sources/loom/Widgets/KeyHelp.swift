/// Shortcut help generated from the same bindings used to dispatch actions.
public struct KeyHelp<Action>: Widget {
    public var keyMap: KeyMap<Action>
    public var style: Style

    public init(_ keyMap: KeyMap<Action>, style: Style = Style()) {
        self.keyMap = keyMap
        self.style = style
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        Paragraph(TextLayout(keyMap.helpText, width: max(1, area.width), wrapping: .word), style: style)
            .render(in: area, buffer: &buffer)
    }
}
