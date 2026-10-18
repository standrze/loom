# Feature gap implementation

The [feature gap plan](FeatureGapPlan.md) describes two milestones. The first
adds style composition, flexible layout and text placement, common widgets, and
collection options. The standalone `loom-widgets` executable demonstrates those
features together without changing the browser's application flow.

```sh
swift run loom-widgets
```

Use arrows/Home/End/Page Up/Page Down to navigate jobs, Space to mark, s to reverse
sort, and f to filter Ready jobs. Stable row IDs preserve selection through sort;
filtering reconciles a removed selection to the nearest surviving row. Click tabs
to filter or cells to select. Wheel and scrollbar dragging move the job viewport.
Tab switches keyboard navigation between the table and log. The l/h/a keys scroll
the log vertically, advance its horizontal offset, and cycle alignment. Escape
exits. The layout recomputes on terminal resize, including very small areas.

The example combines styled top/bottom Panel titles, Tabs, selection prefixes,
a separate whole-column highlight, Gauge/LineGauge, an unwrapped aligned Paragraph,
and help generated from its key bindings. Progress values and log events are
synthetic deterministic fixtures; this is a widget composition, not a job runner.
The application owns selection, filtering, sorting, pointer capture, event routing,
and terminal session lifetime.

## Logical frame export

Export the deterministic initial composition without entering terminal modes:

```sh
.build/debug/loom-widgets --snapshot 100 24 > widgets-wide.json
.build/debug/loom-widgets --snapshot 54 18 > widgets-narrow.json
```

The JSON contains `width`, `height`, optional `cursor`, and `rows` of cells.
Each cell records `symbol`, terminal-cell `width` (zero for a wide glyph's
continuation), optional `link`, and resolved `style`. Colors record their
`kind` (`default`, `indexed`, or `rgb`) and numeric components; styles include
bold, italic, underlined, reversed, dim, and strikethrough. Missing cursor/link
values are JSON null. Object keys are sorted and output ends with a newline.
Dimensions must each be 1...1000, with at most 250000 total cells.

Only JSON is written to stdout on the snapshot path. It performs one logical
render using the same application composition as the interactive executable.
A preview reconstructed from these cells is logical rendering evidence; it does
not establish terminal emulator behavior or interactive input correctness.

## Additive APIs

Style patches inherit unspecified fields and can explicitly reset colors or
disable modifiers. Existing resolved Style rendering and collection merges keep
their legacy behavior. Patches are optional at spans, collection items/rows, and
selection overlays. `dim` and `strikethrough` are resolved Style attributes.

```swift
let inherited = Style(foreground: .indexed(6), bold: true)
let appearance = inherited.applying(StylePatch(bold: false, underlined: true))
let spans = [TextSpan("status", patch: StylePatch(foreground: .terminalDefault))]
```

Layout accepts `insets: LayoutInsets`, `spacing`, and `flex: Flex`. Defaults retain
the previous allocator. Insets and spacing consume space before constraints;
flex distributes remaining space. Paragraph accepts `alignment` and
`horizontalScroll`; `TextLayout(..., wrapping: .none)` retains long logical lines.
Use Paragraph's `contentPoint(at:in:)`/`viewportPoint(for:in:)` mapping for selection
so hit geometry agrees with alignment and scrolling. Whole graphemes crossing a
viewport edge are omitted rather than painted as half a wide glyph.

```swift
let layout = TextLayout("long Unicode 界 line", width: 20, wrapping: .none)
let paragraph = Paragraph(layout, horizontalScroll: 4, alignment: .right)
var table = Table(columns: columns, rows: rows)
table.selectionSymbol = "> "
table.prefixReservation = .always
state.rows.revealPadding = 1
state.highlightColumn(1) // Whole column; selectColumn still means selected cell.
```

Gauge and LineGauge clamp finite ratios to 0...1 and treat non-finite input as
empty. Gauge renders eighth-cell fractions. Tabs retain caller-owned selection;
narrow overflow starts with the selected tab and clips the final visible label.
Panel titles use ordered placement with deterministic clipping at narrow widths.
Clear and Fill use the Buffer's safe cell-writing behavior. See
[Collections](Collections.md) for prefix reservation, patch precedence, reveal
padding, and scrollbar symbol/endpoint contracts.

## Repeatable validation

Run builds serially in one build directory:

```sh
scripts/check-format.sh
swift test
swift build --product loom-demo
swift build --product loom-browser
swift build --product loom-widgets
swift build --product loom-viewports
python3 scripts/smoke.py .build/debug/loom-demo
python3 scripts/smoke-browser.py .build/debug/loom-browser
python3 scripts/smoke-widgets.py .build/debug/loom-widgets
python3 scripts/smoke-viewports.py .build/debug/loom-viewports
```

The widgets PTY fixture reconstructs the cell-diff screen, verifies rendered job
and log tokens after input, checks stable IDs through sorting/filtering, resizes
wide/narrow/tiny, and checks alternate-screen, mouse-mode, and termios restoration.
This is PTY evidence rather than a full terminal emulator compatibility claim.
Logical frame tests and byte-output assertions establish separate contracts.

The CI workflow configures macOS and Linux jobs, each with serial SwiftPM commands
and separate PTY checks. Linux uses the official `swift:6.4-noble` image; macOS
selects the latest stable installed Xcode and explicitly gates Swift >= 6.4.
The [official image tags](https://hub.docker.com/_/swift) and
[setup-xcode options](https://github.com/maxim-lobanov/setup-xcode) were checked
2026-10-13. A configured workflow is not evidence of a successful remote run.

## Validation record and remaining scope

Validated on macOS with Swift 6.4:

| Check | Result |
| --- | --- |
| Main checkout format and whitespace checks | Passed |
| Main checkout unit tests against published weft 0.1.2 | 204 passed |
| All registered products: loom-demo, loom-browser, loom-widgets, loom-viewports | Built against published weft 0.1.2 |
| Main demo/browser/widget/viewport PTY checks | All passed against published weft 0.1.2 |
| Isolated complete build with the proposed weft prerequisite | Built; 204 tests passed |
| Inline/fixed viewport PTY check in that isolated build | Passed, including queued submissions during query and timeout cleanup |
| Clean weft prerequisite | 30 tests, formatting, standard PTY and cursor-query PTY passed |
| Logical frame previews | Exported at 100×24, 54×18 and 8×3; inspected in the browser |

The main package now requires published
[weft 0.1.2](https://github.com/standrze/weft/releases/tag/0.1.2), commit
`cc4a74f482600b252be7858251da6a71efc8574d`. The release was prepared in a separate
clean checkout based on weft 0.1.1, preserving the existing sibling working tree.
The prerequisite is also retained in
[this source patch](Prerequisites/weft-cursor-position-queries.patch).
The published tag and the resolved checkout were verified to match that exact
commit. `loom-viewports` is registered alongside the other executable products. Its
cursor queries use the same reader as keyboard and resize events.

No Linux runtime/remote CI result is claimed: the Docker daemon was unavailable.
Live Terminal-app inspection was denied by the computer-use tool. Browser frame
previews are logical rendering artifacts, not terminal-emulator screenshots.
The isolated viewport build used an explicit local dependency for prepublication
validation only. The main package uses the published remote dependency.

The follow-up [widget and rendering increment](WidgetRenderingDetails.md) adds
layout caching/overlap, custom and merged borders, shadows, measured reverse
collections, row margins, wrapping controls, extended styles, buffer operations,
and semantic ANSI/headless backends. Its validation is recorded separately.

The [plotting and calendar increment](Plotting.md) adds Sparkline, grouped
BarChart, Cartesian Chart, coordinate Canvas, and MonthlyCalendar. These widget
families are no longer missing. Native Windows support, arbitrary graphics/diff
escape hooks, incremental Markdown parsing, and full Markdown table presentation
remain outside these implementations. Forms/tree/file pickers are optional
ecosystem additions rather than core widget parity requirements.
