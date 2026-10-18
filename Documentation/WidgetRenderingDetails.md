# Widget and rendering details

This increment extends the earlier feature-gap implementation. Existing widget
and ANSI terminal defaults remain unchanged. It does not establish complete
Ratatui parity. Native Windows support is provided by weft 0.2.1; see
[platform support](PlatformSupport.md).

## Borders and shadows

`BorderType.custom(BorderSymbols)` accepts validated, printable single-cell
symbols. Its throwing initializer rejects wide glyphs, control characters, and
multi-character strings. Supply the four corners, horizontal/vertical edges,
and optionally the junction symbols used by `BorderLayer`.

For shared borders, insert panels into an explicit `BorderLayer`, then render
that layer before ordinary content. Connections merge at shared cells; later
panels determine appearance. Single/double mixed-axis corners, tees, and crosses
use matching Unicode glyphs. Opposing strokes of unequal weight have no exact
Unicode representation and fall back to the later border family. Custom sets
use their supplied junction glyphs. Titles render after merged borders.

```swift
let regions = Layout(.horizontal, [.fill(1), .fill(1)], spacing: .overlap(1)).split(area)
var borders = BorderLayer()
borders.insert(Panel(title: "Left"), in: regions[0])
borders.insert(Panel(borderType: .double, title: "Right"), in: regions[1])
borders.render(buffer: &frame.buffer)
```

`Panel.shadow` optionally translates a glyph-filled shadow by cell offsets.
The shadow paints before the panel, outside its original rectangle, respecting
the enclosing clip. It does not change `Panel.inner` or reserve layout space.

## Collections and wrapping

`List.reversed` places the first item at the bottom. Initial overflowing reverse
lists reveal that end; later manual scrolling is retained. Navigation follows
screen direction, and pointer hits use the same measured row geometry.

`List.automaticHeights` and `Table.automaticHeights` opt into measurement. Lists
measure after selection-prefix reservation; tables use the tallest participating
cell at the allocated column width. Custom list drawing can supply `measureRow`;
without it, custom rows retain their explicit item heights.

`TableRow.topMargin` and `bottomMargin` add nonnegative scrolling rows around the
content. Margins receive the row background but return no selectable cell.
Selection reveal includes the full row extent.

`TextWrapOptions` controls `trimLeadingWhitespace` on soft wraps,
`breakLongWords`, and `tabWidth`. Defaults are false, true, and four cells.
Explicit newlines remain significant; source text and source indices remain
available for copying. Tabs expand by a fixed number of cells, retaining the
legacy behavior rather than using terminal tab stops. `.word` with long-word
breaking disabled retains oversized logical words and clips their display.

Pass `options:` to `TextLayout` and document entry insertion, or configure
collection `wrapping` and `wrapOptions`. Measurement and painting share these
settings. `Paragraph` consumes its already constructed text layout.

## Layout and buffers

`LayoutCache(capacity: 128)` is a caller-owned bounded LRU cache. Use
`layout.split(area, cache: &cache)`; every layout field and the complete area
participate in lookup. Zero capacity disables retention. Ordinary `split` remains
uncached, with no shared global state. No performance improvement is claimed
without workload-specific measurement.

`LayoutSpacing.gap` and `.overlap` explicitly select spacing behavior. The existing
integer initializer still clamps negative spacing to zero. Overlap is bounded by
adjacent allocated lengths; it retains those lengths and distributes released
space through the selected flex mode. Later widget writes determine overlap
appearance; use `BorderLayer` where edge connections should merge.

Buffer adds `fill`, `clear`, `apply` for style patches, `copy`, `compose`,
`resized`/`resize`, and structured `differences`. Operations respect active clips
and preserve complete glyphs, styles, and hyperlinks. Copies use value semantics,
so overlapping self-copy reads original contents. A glyph crossing a clip or new
size boundary is omitted; an existing glyph crossing a restricted write boundary
is left intact. Differences include continuation cells and removed coordinates.

## Styles and backends

`Style` and `StylePatch` support `underlineColor`, `hidden`, and `blink`.
`Blink` is `.none`, `.slow`, or `.rapid`; use `Blink.none` explicitly in an optional
patch to disable it, because optional `.none` means inheritance. ANSI uses SGR
58/59 for underline color, 8 for hidden, and 5/6 for blinking. Color depth controls
underline color conversion too. Hidden retains content for copying and logical
snapshots. Actual display of these attributes depends on the terminal emulator.

`RenderBackend` accepts semantic `RenderUpdate.frame` and `.insertion` operations.
`RenderPresentation` includes logical snapshots, physical placement, pending
clears, terminal size, and optional inline reservation. `RenderInsertion` carries
transcript rows and the retained frame to repaint. Implementations own output,
not terminal sessions or input. Return `RenderStats` and throw on output failure;
`reset` discards encoder assumptions without clearing the physical surface.

`RenderTerminal` owns the shared frame/viewport state machine. Existing
`Terminal<B: weft.Backend>` forwards to it through `ANSIRenderBackend<B>` and keeps
its original API. Successful presentation alone advances snapshots. Output
failure invalidates them; uncertain inline scrolling requires explicit reanchor
and never automatically replays a transcript insertion.

```swift
var terminal = RenderTerminal(
    backend: TestBackend(width: 80, height: 24), width: 80, height: 24)
try terminal.draw { frame in
    frame.render(Panel(title: "Headless"), in: frame.area)
}
let screen = terminal.backend.screen
```

`TestBackend` retains physical cells, cursor, scrollback, operation history, and
step counts. It can throw before or after a chosen primitive step to exercise
partial output. It interprets semantic updates, not arbitrary ANSI input.
`RecordingBackend` continues to support byte assertions. No SVG renderer is
included.

## Explicit presentation policies — unreleased

[PR #2](https://github.com/standrze/loom/pull/2) adds `CellDiffPolicy` with
`.automatic`, `.skip`, `.alwaysUpdate`, and `.forcedWidth(Int)`. Policies retain
complete glyph footprints and ordinary Unicode geometry. Forced-width writes
still reject terminal controls. ANSI and headless backends track physical
occupancy consistently across skips. See [API customization](APICustomization.md)
for reservation, clearing, and recovery boundaries.

## Demonstration and validation

Run `loom-widgets` and press `d` to view the details screen. Press `d` again to
return to the existing collection demo. `--snapshot-details WIDTH HEIGHT`
exports deterministic logical cells without entering terminal modes.

Run formatting, the complete Swift suite, all executable builds, and the demo,
browser, widget, and viewport PTY scripts serially. Logical cell tests, ANSI byte
tests, and PTY checks cover separate contracts; they do not establish live
terminal-emulator compatibility or successful Linux execution.

Current validation and platform evidence are linked from the
[documentation index](README.md). The record below describes the earlier increment.

### Historical validation record: 2026-10-13

Validated locally on macOS arm64 with Apple Swift 6.4:

| Check | Result |
| --- | --- |
| Repository format check and `git diff --check` | Passed |
| Complete Swift Testing suite | 241 tests passed |
| loom-demo, loom-browser, loom-widgets, loom-viewports | All built serially |
| Demo, browser, widgets, and viewports PTY checks | All passed |
| Details logical snapshots | Generated and inspected at 100×24, 54×18, and 8×3 |

The new headless tests cover physical placement, retained cells and metadata,
scrollback, full-width insertion padding, cursor validity, resize, diagnostic
history, and failures before/after primitive mutations. Driver tests verify
snapshot invalidation and explicit recovery after uncertain output. Byte tests
cover underline-color downgrade/reset, hidden text, and blinking.

At the time of this historical record, these results were local and uncommitted. No Linux runtime, remote CI, native
Windows backend, or live terminal-emulator attribute rendering is claimed.
