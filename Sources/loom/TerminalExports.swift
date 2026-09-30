// Preserve the convenient import loom API while Weft remains independently usable.
import weft

public typealias Point = weft.Point
public typealias Rect = weft.Rect
public typealias Backend = weft.Backend
public typealias ANSIBackend = weft.ANSIBackend
public typealias TerminalSession = weft.TerminalSession
public typealias TerminalOptions = weft.TerminalOptions
public typealias TerminalKeyboardProtocol = weft.TerminalKeyboardProtocol
public typealias TerminalEvents = weft.TerminalEvents
public typealias TerminalError = weft.TerminalError
public typealias Key = weft.Key
public typealias KeyEvent = weft.KeyEvent
public typealias KeyEventKind = weft.KeyEventKind
public typealias KeyModifiers = weft.KeyModifiers
public typealias MouseKind = weft.MouseKind
public typealias MouseEvent = weft.MouseEvent
public typealias InputEvent = weft.InputEvent
public typealias InputDecoder = weft.InputDecoder
public func terminalCellWidth(_ character: Character) -> Int {
    weft.terminalCellWidth(character)
}
