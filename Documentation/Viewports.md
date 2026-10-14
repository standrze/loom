# Frames, snapshots and terminal viewports

`Terminal` uses fullscreen rendering by default. A frame's area, widget positions,
and requested cursor always use viewport-local terminal cells. `viewportArea` is
its physical terminal footprint. Convert physical mouse positions with
`localPoint(from:)`; positions outside the footprint return nil.

```swift
var terminal = Terminal(
    backend: RecordingBackend(), width: 80, height: 24,
    viewport: .fixed(Rect(x: 4, y: 6, width: 40, height: 8)))
try terminal.draw { frame in
    frame.render(Paragraph(TextLayout("Status", width: frame.area.width)), in: frame.area)
    frame.cursor = Point(x: 6, y: 0)
}
let snapshot = terminal.snapshot
let bytes = terminal.backend.data
```

Snapshots are captured on demand and retain independent buffer values, including
wide-cell continuation cells, styles, links and the local cursor. `differences(from:)`
reports geometry, cursor and cell changes. A snapshot is nil before successful
presentation, after resize/invalidation, or after failed output. Logical snapshots
do not establish terminal-emulator behavior or scrollback correctness.

Fixed viewports are clipped to the terminal. Their initial repaint writes every
owned cell, including blanks, using absolute cursor positions. They never clear the
whole screen. Moving or shrinking with `setViewport` schedules a bounded erase of
the previous footprint. The application must keep viewport boundaries on whole
existing graphemes: a renderer cannot discover an external wide character crossing
its boundary. A partial failed ordinary repaint invalidates the snapshot and the
next draw retries the complete current footprint.

Inline viewports require the primary screen and a physical cursor position already
confirmed by the application. `loom` does not start a second stdin reader or guess
an initial cursor position. The caller owns terminal session modes and any cursor
query. A nonzero initial column moves to the next line; reservation emits line feeds
and scrolls when it reaches the bottom. Height is clamped to terminal rows and the
inline footprint uses the full terminal width.

```swift
var terminal = Terminal(
    backend: backend, width: columns, height: rows,
    viewport: .inline(height: 3, anchor: confirmedCursor))
try terminal.draw { frame in
    frame.render(prompt, in: frame.area)
}
try terminal.insertBefore(height: 1) { frame in
    frame.render(logMessage, in: frame.area)
}
```

`insertBefore` commits styled buffer rows above the current UI with line feeds,
then reserves and repaints the UI, including its local cursor. Short rows are padded;
long rows clip whole graphemes. Terminal scrollback retention remains the emulator's
policy. The byte implementation assumes ordinary full-screen primary-screen scroll
margins; applications must restore custom margins before using inline rendering.

Resize and external inline writes invalidate the physical anchor. Call
`reanchor(at:)` only after the application has established a new safe position.
Reservation or insertion failure may have happened after partial output. Such a
failure sets `requiresReanchor`; both draw and insertion throw
`ViewportError.reanchorRequired` until explicit reanchoring. Failed insertion
content is never queued or replayed automatically. The application decides whether
it was committed and whether to offer it again. Reanchoring discards old footprint
knowledge, so the caller must establish a safe location and handle any remnants.

These APIs use the existing byte `Backend` protocol. `RecordingBackend` supports
ordinary importing test clients without `@testable`. Unit tests exercise byte
mapping, bounded erasure, snapshot ownership and failure transitions. PTY and real
terminal checks are separate evidence; this document does not claim emulator or
platform coverage that has not been run.

## Interactive example and PTY fixture

The example is registered as `loom-viewports` and uses the published
[weft 0.1.2 cursor-query API](https://github.com/standrze/weft/releases/tag/0.1.2).
Its prerequisite implementation is also preserved in
[the source patch](Prerequisites/weft-cursor-position-queries.patch).

`loom-viewports` demonstrates application-owned session/input routing. It opens the
primary screen without clearing it, requests the initial physical cursor through
`TerminalSession.requestQuery(.cursorPosition)`, and receives the matching result on its
single `TerminalEvents` stream. Type a line and press Enter to commit it above the
three-row UI. Type `q` followed by Enter, or press Escape, to leave. Resize issues a
new cursor query before explicit reanchoring. Submissions entered while that query
is pending are queued and inserted once, in order, after confirmation. A query
timeout reports and discards pending submissions and exits without guessing an
anchor or replaying output.

Run `swift run loom-viewports --fixed` to see a bounded rectangle between labeled
sentinels. `m` moves it, `s` shrinks it, `r` repaints it, and `q` exits. The example
places the cursor below the final known UI footprint when leaving and restores its
owned session modes.

After building the product, run:

```sh
python3 scripts/smoke-viewports.py .build/debug/loom-viewports
```

The fixture supplies cursor reports over a PTY, commits multiple transcript lines,
resizes, queues two submissions before answering the fresh query, verifies each is
inserted once, moves/shrinks/repaints the fixed viewport between
sentinels, withholds a query response to exercise timeout exit, and compares termios
before/after. Its small ASCII screen model inspects bounded rendering and scroll
placement. This is PTY/model evidence, distinct from visually checking the example
in an actual terminal emulator. The main package resolves the released weft cursor-query API; local and published-dependency validation are recorded separately in the implementation guide.
