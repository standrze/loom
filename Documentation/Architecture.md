# Frame ownership

```text
application → loom → weft → terminal
                 → Swift Markdown
```

The application owns state, event handling, and scheduling. `Terminal.draw`
resets the logical frame, runs a rendering closure, compares cells against the
previous frame, and writes the encoded difference through a `Backend`.
An unchanged frame and cursor emit no output. Output failure invalidates the
previous frame so the next draw can repaint. Call `invalidate()` after external
code writes outside the renderer, and `resize(width:height:)` on terminal resize.

Widgets paint into `Buffer`; `Frame` provides the drawable area and optional
cursor position. Layout and selection use terminal cells. Text models retain
source ranges so wrapping and Unicode graphemes can map back to original text.
`MarkdownRenderer` uses Swift Markdown to parse content. Widgets have no event
loop of their own.

`StatefulWidget` adds explicit caller-owned state to that rendering contract.
Lists and tables synchronize selection and scroll metrics during drawing; they
never consume events. Applications may call their `update` method before event
dispatch when data or geometry changes. `SelectionState`, `ScrollState`,
`FocusState`, and `KeyMap` are optional value types, not an application runtime.
See [collections and interaction](Collections.md) for identity, clipping, focus,
and routing contracts.

Terminal sessions belong to weft. The application opens and closes a session,
and stops `TerminalEvents` before closing it. Many common weft types are aliased
by loom for convenience; clients using additional terminal APIs can depend on
weft explicitly.

The initial extraction preserves the library implementation from ono-sendai,
with lowercase module imports. It includes existing desktop-style widgets as
optional building blocks; it does not impose a desktop interaction model.
