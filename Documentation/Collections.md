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

## Optional collection presentation

Selection prefixes are opt-in. Set `selectionSymbol` and `prefixReservation` on
List or Table. `.never` (the default) consumes no cells and hides the prefix;
`.whenSelected` reserves space while a row is selected; `.always` reserves space
regardless of selection. The symbol defaults to an empty string. Width uses
terminal cells, including wide graphemes. The gutter is fixed while table columns
scroll; header/footer/body columns share the remaining width. Table cell hits
exclude the gutter; list hits in the gutter select the corresponding item.
Custom list renderers receive the content rectangle after the gutter.

```swift
var list = List([ListItem(id: "job", "Compile", alignment: .right)])
list.selectionSymbol = "> "
list.prefixReservation = .always
selection.revealPadding = 2
```

`ListItem.alignment` overrides the list alignment when non-nil. Explicit row heights
still control wrapping and clipping. `SelectionState.revealPadding` defaults to
zero and requests terminal rows around the selected item, clamped so that the
item fits. It applies during navigation and data/viewport reconciliation, without
undoing a manual wheel scroll on an unchanged draw.

`TableState.highlightColumn(_:)` controls `highlightedColumn` independently of
`selectedColumn`, which retains its existing selected-cell meaning. Whole-column
highlights include headers and footers. Customize `columnSelectionStyle` or
`columnSelectionPatch`; presentation applies row, whole-column, then selected-cell
overlays in that order. Column selections are positional and clamp after a column
count change.

Legacy Style overlays retain their color-inheritance and enabled-modifier merge.
Optional `ListItem.patch` and `TableRow.patch` apply after their explicit appearance;
span patches apply after the legacy base/span merge. Selection patches apply last,
so they can reset colors or disable inherited modifiers. List exposes
`markedPatch`/`selectionPatch`; Table exposes `selectionPatch`,
`columnSelectionPatch`, and `cellSelectionPatch`.

Scrollbar accepts `thumbSymbol`, optional `trackSymbol`, `startSymbol`, and
`endSymbol`. Every supplied symbol must be one grapheme occupying one safe terminal
cell; invalid values use the direction's default symbol. Endpoints each consume a
cell before thumb sizing, paging, and drag geometry. Endpoint clicks scroll one
cell. For a one-cell bar the start endpoint takes precedence. `trackArea(in:)`
returns only the draggable track; `thumbRange(length:)` expects that track length.

Lists can opt into `reversed = true` to place their first item at the bottom. Up,
down, Home, End, and page navigation follow screen order; identities remain in the
original input order. Short reversed lists align to the bottom of the viewport.

Set `automaticHeights = true` on a list or table to measure wrapped text using the
final content width, including selection prefix reservation and table column sizing.
Explicit heights remain the default. A custom list renderer supplies `measureRow`
with a content width in terminal cells; without it the custom row keeps its explicit
height. `TableRow.topMargin` and `bottomMargin` add background rows to scrolling but
never produce cell hits.

`TextWrapOptions` controls leading whitespace on soft wraps, long-word splitting,
and cells per tab. Defaults preserve the existing four-cell tab expansion and
wrapping behavior. Pass options to `TextLayout` or document append/insert operations.
Trimming changes display geometry only: source text and copying retain whitespace.
With word wrapping and `breakLongWords = false`, overwide words remain on one logical
row and are clipped by the viewport.

Collection `wrapping` and `wrapOptions` configure both automatic measurement and
painting, so word wrapping, whitespace trimming, and custom tab widths use identical
geometry. A reversed list initially reveals its first item at the viewport bottom;
subsequent unchanged updates preserve manual scrolling.

## Additional collection controls

Released in 0.2.1: `List.reversed`, list/table `automaticHeights`,
`List.measureRow`, and `TableRow.topMargin` / `bottomMargin` share measured
paint and hit geometry. See [widget details](WidgetRenderingDetails.md).

Unreleased in [PR #2](https://github.com/standrze/loom/pull/2):
`List.repeatHighlightSymbol = true` repeats the selected prefix on every visible
physical item row, including blank/custom rows. Its default is false.
`Table.columnFlex` distributes leftover space with the existing `Flex` modes
(default `.start`); headers, body, horizontal scrolling and hit testing all use
`columnAreas(width:)`. Neither option changes copied source text. See
[API customization](APICustomization.md) for the full contracts.
