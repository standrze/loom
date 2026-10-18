# Common widgets and panel titles

These widgets modify logical buffer cells. They own no event loop, terminal modes,
selection state, or application routing.

```swift
Gauge(ratio: 0.375, label: "3 / 8", filledStyle: Style(foreground: .indexed(2)))
LineGauge(ratio: 0.625, label: "Download")
let tabs = Tabs([
    Tab(id: "jobs", label: "Jobs"),
    Tab(id: "logs", label: "Logs"),
], selected: "logs")
let selectedID = tabs.hitTest(Point(x: 3, y: 0), in: tabArea)
Panel(
    titles: [
        PanelTitle([TextSpan("Jobs", style: Style(bold: true))]),
        PanelTitle([TextSpan("Ready")], alignment: .right, position: .bottom),
    ],
    borderStyle: Style(foreground: .indexed(4)),
    titleStyle: Style(italic: true)
)
Clear().render(in: overlayArea, buffer: &buffer)
Fill("·", style: Style(dim: true)).render(in: backgroundArea, buffer: &buffer)
```

Gauge clamps finite ratios to 0...1; NaN and either infinity become zero. The bar
uses full block glyphs plus eighth-cell left blocks, rounding partial progress
down to the nearest eighth. Gauge fills every assigned row and centers its
optional label on the middle row. LineGauge uses the first assigned row, placing
its optional label and a space before the remaining bar. Labels use the first
laid-out row and whole-grapheme clipping. Label style is explicit and independent
of the bar styles. An empty rectangle changes no cells.

Tabs uses stable, caller-provided IDs. Update `selected` in application code after
hit testing or keyboard routing. Hit testing and rendering calculate identical
label/padding rectangles; separator cells have no target. Padding is measured in
terminal cells and negative padding becomes zero. Tabs starts from the first tab
when the selected tab fits fully; otherwise it starts at the selected tab. The
last visible tab may be clipped. A selected tab wider than the rectangle uses its
available width, reduces padding to keep label space, and clips whole graphemes.
A wide grapheme may therefore be omitted in a one-cell rectangle. Empty labels
can still occupy padding. Only the first assigned row is interactive.

Panel retains `title: String?`, its alignment, and the old padded single-title
behavior. Its additional `titles` accept styled spans at either edge. Titles only
appear when their corresponding border is enabled by default. The unreleased
`titlesWithoutBorders: true` option in [PR #2](https://github.com/standrze/loom/pull/2)
also paints titles on absent edges; `inner(_:)` reserves those title rows once,
and `BorderLayer` uses the same geometry. `borderStyle` and `titleStyle`
fall back to `style`; explicit span styles override title style, and span patches
compose over the inherited or explicit style. Titles receive one blank cell at
each end and use their first laid-out row. The legacy title has first priority,
then rich titles are processed in array order. Earlier titles reserve their whole
grapheme footprints, including blank padding; later glyphs intersecting those
cells are omitted. Custom borders, explicit border intersection merging, and panel shadows are
described in [widget and rendering details](WidgetRenderingDetails.md).

Fill accepts exactly one printable grapheme of terminal width one. Wide symbols,
zero-width graphemes, controls, empty strings, and multiple graphemes are ignored.
Clear is a blank default-style Fill. Both operations clip to the supplied
rectangle and buffer. If an existing wide glyph straddles the rectangle boundary,
they preserve both cells of that glyph, including its cell inside the rectangle.
They replace whole glyphs contained within the rectangle. This preserves content
outside the assigned area and never leaves a continuation without its leader.

`CommonWidgetTests.swift` checks ratio normalization, fractional cells, labels,
Unicode boundaries, tab hit geometry, and title precedence. Logical cell tests do
not establish terminal font appearance; the integration demo and PTY checks cover
separate rendering and interaction behavior.

The [plotting and calendar guide](Plotting.md) covers Sparkline, BarChart, Chart,
Canvas, and MonthlyCalendar.
