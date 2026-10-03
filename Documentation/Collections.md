# Lists, tables, scrolling, and focus

`loom` draws the interface. Your application owns its data, state, event routing,
filtering, sorting, and terminal session. None of these helpers starts an event loop
or reads input itself.

Run the complete browser example:

```sh
swift run loom-browser
```

Type to filter jobs. Tab/Shift-Tab moves between search, categories, and the table.
Use arrows or j/k to navigate, Space to mark table rows, s to reverse the sort,
and Enter to inspect a job. Escape closes the dialog and restores focus; Escape
outside a dialog exits. Mouse clicks, wheel scrolling, and scrollbar dragging work
without changing the application-owned event model. Help reflects the active bindings.

## A list with stable selection

```swift
var selection = SelectionState(selectedID: "b")
let list = List([
    ListItem(id: "a", "First"),
    ListItem(id: "b", "Second"),
    ListItem(id: "c", "Third"),
])

// Synchronize after changing data or layout, before dispatching a batch of events.
list.update(in: area, state: &selection)
selection.handle(event, allowsMultipleSelection: true)
frame.render(list, in: area, state: &selection)
```

`List` and `Table` conform to `StatefulWidget`. Their draw method updates metrics
and reconciles selection in the state passed by the caller. Existing `Widget`
conformances and `Frame.render(_:in:)` are unchanged. Rendering never consumes input.

IDs must be unique. Selection and marks survive reordering. If filtering/removal
hides the selected item, selection moves to the nearest surviving index; hidden
marks are removed. Empty data clears selection. Nil selection remains nil until
the application or navigation selects an item. If you need marks to survive a
filter, retain that larger set in your application and project it onto the visible data.

Use `select`, `moveSelection`, `pageSelection`, `toggleMarked`, `markAll`, and
`clearMarks` directly for custom bindings. `handle` is an optional default for
arrows, Home/End, Page Up/Down, and wheels; Space marking is opt-in. Route only
the focused control's keys and the hovered/captured viewport's mouse events.

`item(at:in:state:)` maps absolute terminal cells to IDs. Update or draw first,
then hit-test with the same data and area. Unused rows are not selectable.

Rows can have styled spans and explicit heights in terminal rows. A row wraps
within its width and clips at its declared height. For arbitrary row content,
set `renderRow`; the callback receives the item, selection/mark appearance, and
its absolute logical rectangle. Writes are clipped to the viewport and row.
Only visible rows invoke the callback. Use the supplied appearance style in
custom content if you want the default selection/mark presentation.

## A table

```swift
var state = TableState(selectedID: 42)
let table = Table(
    columns: [
        TableColumn("Name", width: .fill(1)),
        TableColumn("Size", width: .length(10), alignment: .right),
    ],
    rows: [
        TableRow(id: 42, cells: [TableCell("report.txt"), TableCell("12 KB")]),
        TableRow(id: 43, cells: [TableCell("notes.txt"), TableCell("2 KB")]),
    ])
frame.render(table, in: area, state: &state)
```

Columns use loom's existing `Constraint` values. `columnSpacing` separates them;
alignment can be set per column or overridden per cell. Headers and optional
footers stay fixed while body rows scroll. Row heights are explicit. Missing
cells remain blank and excess cells are ignored.

`state.rows` provides the same selection/marks/vertical scrolling as a list.
`state.selectCell(row:column:)` enables a cell highlight; `selectColumn(nil)` returns
to row-only selection. `cell(at:in:state:)` excludes headers, footers, and column gaps.

Set `table.minimumWidth` when columns should extend past a narrow viewport.
`state.horizontal` then controls horizontal scrolling, moving headers, body, and
footer together. In the default handler, left/right navigate an active cell
selection or scroll horizontally when no cell is selected. Column indexes are
positional; applications reordering columns should remap cell selection themselves.

## Shared scrolling

`ScrollState` describes one axis in terminal cells. It clamps offsets against
content and viewport lengths, provides paging and range reveal, and handles
empty/zero-sized viewports. Use separate instances for horizontal and vertical axes.

```swift
var scroll = ScrollState(followsEnd: true)
scroll.update(contentLength: document.rowCount, viewportLength: area.height)
frame.render(DocumentView(document, scroll: scroll.offset), in: area)
frame.render(Scrollbar(scroll), in: scrollbarArea)
```

`followsEnd` keeps a log at the end as content grows. Scrolling away disables it;
`scrollToEnd(follow: true)` re-enables it. Metric updates otherwise preserve the
numeric offset and clamp it. Content-aware anchors across text reflow belong to
the application: resolve the saved entry ID to its new row and reveal it.

List/table rendering does not re-reveal an unchanged selection every frame, so a
wheel can scroll away from it. Selection navigation and changed row geometry
reveal it again. All mutable state remains with the application.

`Scrollbar` can render vertically or horizontally. Its optional mouse handler
supports page clicks, wheels, and thumb dragging. Keep a `ScrollbarDrag?` beside
your scroll state, and route drag/release events to that bar even outside its
track. Clear capture if the owning control is removed. A bar uses the area's first
column or row; reserve that space separately from content.

`ScrollView` clips a cached `Buffer` at two offsets, copies only visible cells,
and translates viewport hits to content coordinates. It does not lay out or
allocate the content buffer. Whole wide glyphs cut by either edge are omitted.
For huge data sets, render visible list/table rows rather than allocating a
content-sized buffer.

## Focus and shortcuts

```swift
var focus = FocusState([
    FocusTarget("search", area: searchArea),
    FocusTarget("results", area: resultsArea),
])
focus.handle(event)
// Route keyboard events according to focus.focusedID.
// A click can change focus AND activate the newly focused control.
```

Update targets after layout changes. Disabled targets are skipped. Traversal wraps
unless `wraps` is false. Overlapping click regions prefer the last enabled target.
`pushScope` restricts traversal and clicks to modal targets; `popScope` restores the
previous focus. Escape behavior is application policy, not built into `FocusState`.

```swift
enum Action { case quit, next }
var keys = KeyMap([
    KeyBinding(Action.quit, keys: [KeyChord(.character("c"), modifiers: .control)], help: "quit"),
    KeyBinding(Action.next, keys: [KeyChord(.down), KeyChord(.character("j"))], help: "next"),
])
let action = keys.action(for: event)
frame.render(KeyHelp(keys), in: helpArea)
```

Bindings can be remapped, disabled, hidden from help, or configured to reject
repeat events. First enabled match wins. Help is generated from the same current
bindings; construct it again after remapping. Chords match logical keys and exact
modifiers, ignoring Caps Lock/Num Lock. Releases, pastes, and multi-character text
events do not trigger shortcuts. Legacy Ctrl-C/Ctrl-D normalize to their extended
keyboard equivalents. Other ambiguous legacy keys retain the decoder's identity;
the helper cannot recover distinctions the terminal did not transmit.

## Validation

The package tests cover identity preservation, filtering/removal, marks,
variable-height paging, independent scrolling, headers/footers, column alignment,
wide grapheme clipping, nested focus scopes, mouse focus, and binding/help behavior.

```sh
scripts/check-format.sh
swift test
swift build
python3 scripts/smoke.py .build/debug/loom-demo
python3 scripts/smoke-browser.py .build/debug/loom-browser
```

The browser PTY smoke exercises actual input decoding, search, focus traversal,
selection, sorting, multiselect, modal focus restoration, mouse scrolling, resize,
and terminal mode restoration. It is a macOS host check, not Linux or a terminal
emulator compatibility certification.
