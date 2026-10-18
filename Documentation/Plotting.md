# Plotting and monthly calendars

`Sparkline`, `BarChart`, `Chart`, `Canvas`, and `MonthlyCalendar` are public loom
widgets. They paint logical buffers and own no input loop, terminal mode, clock,
or application data source. The implementations use existing loom cell geometry
and style composition, with no new package dependencies.

This addition addresses the five missing widget families identified in the
Ratatui 0.30.2 audit. The reference capabilities were checked against its official
[Sparkline](https://docs.rs/ratatui/0.30.2/ratatui/widgets/struct.Sparkline.html),
[BarChart](https://docs.rs/ratatui/0.30.2/ratatui/widgets/struct.BarChart.html),
[Chart](https://docs.rs/ratatui/0.30.2/ratatui/widgets/struct.Chart.html),
[Canvas](https://docs.rs/ratatui/0.30.2/ratatui/widgets/canvas/), and
[calendar](https://docs.rs/ratatui/0.30.2/ratatui/widgets/calendar/) documentation.
The Swift APIs and rasterizers are independently written; this is capability
coverage, not a source or pixel-compatible port of every upstream option.

## Sparkline

```swift
var trend = Sparkline(samples: [2, 4, nil, 8, 3, 6], maximum: 8)
trend.style = Style(foreground: .indexed(6))
trend.direction = .rightToLeft
trend.missingSymbol = "·"
trend.render(in: area, buffer: &buffer)
```

Each sample occupies one terminal column and can span multiple rows. Bars use
bottom-up eighth-cell blocks. The first sample starts on the left by default or
on the right in reverse direction. Excess samples are clipped; no aggregation
or resampling is implicit. Autoscaling considers all finite positive samples,
including offscreen samples. An explicit positive maximum clips larger values;
zero, negative, and non-finite maxima produce empty bars. Negative samples are
zero; nil, NaN, and infinities are missing.

Use `Sparkline(bars:)` with `SparklineBar(value, patch:)` for per-sample styling.
`missingStyle` applies after that patch; missing symbols appear only on the
bottom row. `SparklineSymbols` validates exactly nine printable single-cell
glyphs, from empty through full. Invalid missing symbols fall back to blank.

## Grouped bars

```swift
var bars = BarChart(groups: [
    BarGroup([Bar(12, label: "GET"), Bar(7, label: "POST")], label: "API"),
    BarGroup([Bar(9, label: "GET"), Bar(4, label: "POST")], label: "Web"),
])
bars.barWidth = 5
bars.barGap = 1
bars.groupGap = 2
bars.direction = .vertical
frame.render(bars, in: area)
```

Bars support vertical or horizontal direction, grouped labels, individual
styled span labels, value text overrides, and group/bar style patches. Vertical
charts reserve bottom rows for labels. Horizontal charts reserve a shared left
gutter for bar labels and place group labels above their bars. `barWidth` is
terminal columns vertically and terminal rows horizontally. Nonpositive widths
become one and negative gaps become zero. Empty groups consume no space.

Autoscaling considers all finite positive bars. Negative and non-finite values
render as zero; invalid explicit maxima yield empty bars. Fractional height or
width uses eighth-cell blocks. `showsValues` controls values inside the bar;
labels and values use one unwrapped, whole-grapheme-clipped row. Bars default to
chart style, then group/bar patches. Optional replacement styles can separately
control bars, labels, group headings, and values.

## Cartesian charts

```swift
let chart = Chart(
    datasets: [
        ChartDataset(name: "load", points: [
            CanvasPoint(x: 0, y: -1), CanvasPoint(x: 1, y: 2), CanvasPoint(x: 2, y: 1),
        ], style: Style(foreground: .indexed(2))),
    ],
    xAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 2), title: "seconds", labels: [
        ChartAxisLabel(value: 0, text: "0"), ChartAxisLabel(value: 2, text: "2"),
    ]),
    yAxis: ChartAxis(bounds: CanvasBounds(min: -2, max: 3), title: "load"))
frame.render(chart, in: area)
```

Each dataset can be `.line`, `.scatter`, or `.bar`, with its own marker, name,
and style. Line order is retained; non-finite coordinate pairs break segments
and do not affect automatic bounds. Bar graphs use a zero baseline clamped into
the y bounds. For an all-positive/all-negative dataset, include zero in explicit
y bounds if the baseline should be visible outside the finite data range.

Nil bounds autoscale finite pairs; empty data uses 0...1 and a constant series
gets a finite expanded range. Invalid explicit bounds suppress the data raster.
Axes accept custom numeric ticks and styled titles/labels; ticks are caller
supplied, not an implicit formatting or tick-generation policy. Titles occupy
horizontal rows. First-supplied tick labels win collisions. `plotArea(in:)`
exposes the exact region after axis/label reservation. Tiny areas clamp to empty
plot regions without negative geometry.

Legend position supports the four corners or `.hidden`; a legend that would
cover the complete plot width or height is omitted. Later datasets replace
shared raster cells, preserving their own glyph and appearance. This does not
blend separate datasets into a shared multi-color Braille glyph.

## Coordinate drawing

```swift
let canvas = Canvas(
    xBounds: CanvasBounds(min: -10, max: 10),
    yBounds: CanvasBounds(min: -5, max: 5), marker: .braille
) { context in
    context.rectangle(origin: CanvasPoint(x: -8, y: -3), width: 16, height: 6)
    context.circle(center: CanvasPoint(x: 0, y: 0), radius: 3)
    context.newLayer()
    context.line(from: CanvasPoint(x: -20, y: 0), to: CanvasPoint(x: 20, y: 0))
    context.print("origin", at: CanvasPoint(x: 0, y: 0))
}
frame.render(canvas, in: area)
```

Canvas maps caller-defined finite increasing x/y bounds into cells, with
positive y upward. Markers are `.braille` (2×4 dots per cell), `.halfBlock` (1×2),
`.dot`, and `.block`. Points, crossing line segments, outlined/filled rectangles,
and circle outlines are supported; non-finite shapes are ignored. Circle
outlines use bounded polygon sampling based on the visible raster dimensions.

Dots combine within a layer; the latest stroke determines a cell's style.
`newLayer` flushes that layer, permitting later glyph replacement. `print`
flushes before writing unwrapped Unicode text, preserving wide-glyph clipping.
Unpainted cells are retained. `CanvasShape` and `context.draw` permit reusable
custom shapes; no bundled world-map dataset or geographic projection library is
included.

## Monthly calendar

```swift
let month = try CalendarMonth(year: 2026, month: 10)
let release = try CalendarDay(year: 2026, month: 10, day: 17)
var calendar = MonthlyCalendar(month: month)
calendar.firstWeekday = .monday
calendar.showsSurroundingDays = true
calendar.events[release] = StylePatch(foreground: .indexed(2), bold: true)
calendar.selectedDay = release
frame.render(calendar, in: area)
let clicked = calendar.date(at: pointer, in: area)
```

Dates use the Gregorian calendar with validated years 1...9999, including the
100/400-year leap rule. `CalendarDay.adding(days:)` returns nil beyond that range.
Dates contain no timezone or clock state. The application supplies `today`,
selection, and `[CalendarDay: StylePatch]` event presentation.

The grid uses seven three-cell columns (21 cells total), four to six week rows,
and optional month/weekday headers. `fixedWeekCount` reserves six weeks;
`requiredHeight` reports its rows before viewport clipping. `firstWeekday` rotates
the Monday-first `weekdayLabels` array. `monthNames` and `weekdayLabels` can be
localized by the caller; defaults are English. Wide labels clip as whole glyphs.
Narrow areas clip the fixed grid without reassigning dates to other columns.

Style order is base, weekend, surrounding day, event, today, then selection.
Header rows, separators, and hidden surrounding days return no date from hit
testing. Application-owned routing decides whether a click changes selection.

## Demonstration and checks

Run `swift run loom-widgets` and press **p** to switch to plots/calendar, then
**p** to return. The fixtures are deterministic synthetic values. They do not
load a data service, change the system date, or persist application state.

Export logical cells without terminal modes:

```sh
.build/debug/loom-widgets --snapshot-plots 100 28 > /tmp/loom-plots.json
```

Run the repository format check, complete Swift suite, serial executable builds,
and all four existing PTY smoke scripts. Unit coverage includes scaling, missing
values, grouped directions, Unicode boundaries, legend/tick geometry, shape
clipping/layers, extreme finite values, leap centuries, and shared calendar hit
geometry. PTY coverage exercises the showcase and resizes it wide/narrow/tiny.
Native font appearance and cross-platform emulator support remain separate
validation tasks.

### Validation record: 2026-10-17

Validated locally on macOS arm64 with Apple Swift 6.4:

| Check | Result |
| --- | --- |
| Strict format check and whitespace diff check | Passed |
| Complete Swift suite | 283 tests passed (241 before this increment) |
| All four executable products | Built serially |
| Demo/browser/widgets/viewports PTY checks | Passed |
| Plotting showcase | PTY checks all five families and state retention on return |
| Logical snapshots | Inspected at 100×28, 54×18, and 8×3 |

The new tests include optional/missing Sparkline samples, grouped fractional
bars in both directions, appearance inheritance, tick-label collisions,
multi-series overlays, clipped extreme finite segments at unequal slopes,
custom Canvas shapes, and all Gregorian month/day positions across representative
century boundaries. The calendar and plots retain whole wide glyphs at clips.

No Linux runtime, native Windows backend, live emulator font/marker appearance,
or numerical performance benchmark is claimed. Tick generation, logarithmic
axes, bundled geographic map data, and date/timezone conversion are not supplied;
applications can provide ticks, custom shapes, and date-only values explicitly.
