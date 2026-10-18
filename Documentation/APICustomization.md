# Collection, text, plotting, and presentation customization

These APIs are opt-in. Existing initialization, Unicode measurement, wrapping,
left-aligned text, list prefix behavior, table placement, and bordered titles
retain their defaults. Applications continue to own state and input routing.

## Collections and text

- `List.repeatHighlightSymbol = true` repeats the selected item's prefix on every
  visible physical row, including padding/custom rows. Prefix reservation and
  hit testing use the existing item geometry. Work stays bounded by visible rows.
- `Table.columnFlex` accepts the existing `Flex` modes. Width constraints and
  `columnSpacing` are reserved before leftover space is distributed. Headers,
  rows, horizontal scrolling, and hit testing share `columnAreas(width:)`.
- `Panel.titlesWithoutBorders = true` enables legacy and rich titles on missing
  border edges. `inner(_:)` reserves those title rows exactly once. Existing title
  ordering, clipping, and the merged `BorderLayer` use the same edge geometry.
- `TextLine` carries rich spans and an optional `alignment`. Construct
  `TextLayout(lines: [...], width: ...)` to retain each line's alignment on soft
  wraps. String/span initializers also accept logical `lineAlignments`. Nil
  inherits `Paragraph.alignment`; overrides use the existing shared horizontal
  origin for painting, viewport mapping, hit testing, and selection. Alignment
  adds no characters to copied source text.

```swift
let layout = TextLayout(lines: [
    TextLine("Heading", alignment: .center),
    TextLine("Body inherits the paragraph alignment"),
    TextLine("界e\u{301}", alignment: .right),
], width: 40)
let paragraph = Paragraph(layout)
```

## Plotting

`CanvasMarker` supports dot, circle, bar, block, halfBlock, braille, quadrant,
sextant, octant, and custom markers. Custom markers must be exactly one visible
terminal cell; wide, control, and zero-width values paint nothing. Dense markers
combine independent subpixels within each terminal cell. Terminal/font support
for newer sextant and octant glyphs varies; choose an older marker if needed.

`Chart.legendPosition` supports the eight perimeter positions and `.hidden`.
`legendWidthLimit` and `legendHeightLimit` accept `.cells`, `.ratio`, or
`.unlimited`. Limits apply to the actual Unicode-cell footprint inside the plot;
legends that exceed a limit or cover the entire plot dimension are omitted.
Defaults retain the original top-right, strict-fit legend behavior.

`ChartGraphType.filledLine` fills between consecutive finite points and the
`ChartDataset.baseline`, then strokes the line. `fillStyle` may differ from the
stroke style. Nonfinite points break segments; a nonfinite baseline suppresses
fill. `CanvasContext.filledLine` exposes the same primitive. Fill work is bounded
by the visible raster, including clipped or extremely distant endpoints.

The widget example's **p** page demonstrates filled lines, legend controls, and
quadrant shapes. Its detail page demonstrates repeated prefixes, column flex,
and titles without a top border.

### Data provenance and maps

No geographic dataset is bundled by this change. Map data remains a separate
addition: any future bundle must identify its upstream URL, version/date,
license and required attribution, geographic scope/detail, and the transformation
or simplification used. Caller-owned coordinates may already be drawn with the
existing canvas line/point primitives.

Dense glyph mappings in `CanvasMarkerSymbols.swift` are derived from the character
names in the official [Unicode 16.0 UnicodeData](https://www.unicode.org/Public/16.0.0/ucd/UnicodeData.txt).
The row-major quadrant/sextant/octant bit positions are documented beside the
lookup tables; standard block glyphs cover masks without dedicated scalars.
[Unicode License V3](Licenses/Unicode-3.0.txt) accompanies that derived data.
This is glyph metadata, not geographic data.

## Specialized diff policies

`CellDiffPolicy` offers `.automatic`, `.skip`, `.alwaysUpdate`, and
`.forcedWidth(Int)`. Ordinary text continues to use the existing Unicode cell
geometry and control filtering. `.skip` preserves the physical footprint during
frame painting; `.alwaysUpdate` repaints unchanged glyphs after an external
renderer may have covered them. `Buffer.setDiffPolicy(_:in:)` affects complete
existing glyphs; copies/composition retain policies and ordinary writes reset them.

An explicit width requires `Buffer.put(..., width: n, diffPolicy: .forcedWidth(n))`
with a positive fitting span. It allows safe multi-grapheme payloads while keeping
continuation cells, clipping, replacement, and highlighting coherent. The caller
owns the declared terminal width. Terminal control characters are still rejected;
this API does not introduce raw escape payloads into widget content. Setting a
forced policy on an existing glyph requires its stored width to match.

ANSI presentation retains emitted occupancy across skipped frames, protects old
wide glyphs crossing a skipped cell, and avoids full-screen ED2 while cells are
skipped. The headless backend preserves the corresponding physical contents.
Reserve entire external-image/glyph footprints: without a prior frame, ANSI
cannot infer unknown physical glyphs beyond those reservations. Explicit clears,
viewport relocation, and scrollback insertion still affect the owned terminal
area; skip is a frame-paint policy, not a terminal lock. Encoder byte/repaint
statistics and headless physical-change counts retain their different meanings.

## Reference boundary

Behavior was compared with the published Ratatui 0.30.2
[marker](https://docs.rs/ratatui/0.30.2/ratatui/symbols/enum.Marker.html),
[line alignment](https://docs.rs/ratatui/0.30.2/ratatui/text/struct.Line.html), and
[cell diff option](https://docs.rs/ratatui/0.30.2/ratatui/buffer/enum.CellDiffOption.html)
contracts. These additions preserve loom's shared geometry and safe buffer model;
they do not claim compatibility with arbitrary raw terminal protocols.

## Validation

The integrated suite has 315 tests. On macOS, formatter lint, all tests, all four
example builds, and the demo/browser/widget/viewport PTY checks pass. In an
isolated Linux Swift 6.4.1 container, all 315 tests pass separately under `C` and
`C.UTF-8`, and the updated widget PTY check passes. The checked-in CI matrix also
builds/tests Windows; local macOS/Linux results do not substitute for that job.
