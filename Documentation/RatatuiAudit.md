**loom versus ratatui — feature audit, 2026-10-13**

## Status update: 2026-10-18

The original audit below is a **historical pre-implementation baseline**, not a
current missing-feature list. Ratatui 0.30.2 remains the comparison boundary.

| Original gap | Current status |
| --- | --- |
| Sparkline, BarChart, Chart, Canvas, monthly calendar | Available in 0.2.1; [plotting guide](Plotting.md) |
| Style patches, gauges/tabs/fills, rich titles, collection selection | Available in 0.2.1; [implementation record](FeatureGapImplementation.md) |
| Fixed/inline viewports and public headless backend | Available in 0.2.1; [viewport guide](Viewports.md) |
| Custom/merged borders, shadows, reverse/measured lists, row margins, wrapping | Available in 0.2.1; [widget details](WidgetRenderingDetails.md) |
| Layout flex/cache/overlap, buffer operations, underline color, hidden/blink | Available in 0.2.1; [widget details](WidgetRenderingDetails.md) |
| Linux combining width and native Windows sessions/ConPTY | Addressed in matched loom/weft 0.2.1; [platform evidence and limits](PlatformSupport.md) |
| Repeated prefixes, column flex, independent titles, per-line alignment | Implemented in unreleased PR #2; [customization guide](APICustomization.md) |
| Additional markers, legend placement/limits, filled lines, explicit diff policies | Implemented in unreleased PR #2; [customization guide](APICustomization.md) |
| Bundled world map data | Still absent; needs a separately reviewed dataset and provenance |
| Other terminal backends and complete upstream API/pixel compatibility | Not claimed; loom provides ANSI and semantic headless backends |

See the [documentation index](README.md) for stable and unreleased references.
Specialized ecosystem widgets, every upstream option, emulator/font compatibility,
and comparative performance remain outside this remediation's completion claim.

## Original audit: 2026-10-13

loom has the basic immediate-mode TUI foundation and substantial interaction and text functionality. Its largest gaps against ratatui are visualization widgets, managed terminal viewports, layout flexibility, composable styling, and some customization options on existing widgets.

This audit compares the current local working tree, including existing uncommitted changes, with ratatui **0.30.2**, the latest stable release returned by the official release page during the audit. loom's base commit is `f28aae2781eb7776c24c8c0995a2b310a1a043ec`. Its resolved weft dependency is `0.1.0`, commit `0a540ce2dee1e4622ebbcbb367a35d374318d001`; the dependency checkout matches that pin. These findings describe the working tree, not necessarily the published loom release. [ratatui release](https://github.com/ratatui/ratatui/releases/tag/ratatui-v0.30.2)

“Missing” means no equivalent reusable public API was found in the source inventory. It does not mean an application cannot implement the feature using Buffer or custom widgets. “Partial” means an existing feature covers the basic use case but lacks specific upstream behavior. This is a feature audit, not a security audit or comparative performance benchmark.

The following foundation is already present and should not appear on a missing-feature list:

| Area | Current loom capabilities | Local evidence |
| --- | --- | --- |
| Rendering | Complete logical frames, double buffering, cell diffs, synchronized output, cursor placement/visibility, repaint after write failure | [Terminal](../Sources/loom/Rendering/Terminal.swift), [CellDiff](../Sources/loom/Rendering/CellDiff.swift) |
| Layout | Horizontal/vertical layouts with min, max, length, percentage, ratio and fill constraints | [Layout](../Sources/loom/Rendering/Layout.swift) |
| Unicode and text | Grapheme/cell geometry, wide-character clipping, styled spans, word/grapheme wrapping, selection/copy mappings | [Buffer](../Sources/loom/Rendering/Buffer.swift), [TextLayout](../Sources/loom/Text/TextLayout.swift) |
| Collections | Lists and tables, stable identities, multiselect marks, explicit variable row heights, hit testing, headers/footers, table cell selection and horizontal scrolling | [List](../Sources/loom/Widgets/List.swift), [Table](../Sources/loom/Widgets/Table.swift) |
| Scrolling | Shared paging/reveal/follow-end state, two-axis buffered ScrollView, vertical/horizontal scrollbars with mouse dragging | [ScrollState](../Sources/loom/Interaction/ScrollState.swift), [ScrollView](../Sources/loom/Widgets/ScrollView.swift), [Scrollbar](../Sources/loom/Widgets/Scrollbar.swift) |
| Interaction | Focus traversal, modal focus scopes/restoration, key bindings/remapping, generated key help | [FocusState](../Sources/loom/Interaction/FocusState.swift), [KeyMap](../Sources/loom/Interaction/KeyMap.swift) |
| Editing/content | Text input, grapheme/word movement, selection, undo/redo, cached documents, folding, basic search, Markdown and streaming snapshots | [LineEditor](../Sources/loom/Text/LineEditor.swift), [TextInput](../Sources/loom/Widgets/TextInput.swift), [TextDocument](../Sources/loom/Text/TextDocument.swift), [MarkdownText](../Sources/loom/Text/MarkdownText.swift) |
| Terminal integration | Async input, keyboard protocols, mouse, paste, resize, session cleanup and clipboard copy through weft; loom additionally encodes safe HTTP(S) hyperlinks and color fallbacks | [Exports](../Sources/loom/TerminalExports.swift), [CellDiff](../Sources/loom/Rendering/CellDiff.swift), [Architecture](Architecture.md) |

The wholly missing widget families are straightforward to identify against the [ratatui 0.30.2 widget inventory](https://raw.githubusercontent.com/ratatui/ratatui/ratatui-v0.30.2/ratatui/src/widgets.rs):

| Widget family | What loom lacks | Practical effect |
| --- | --- | --- |
| Gauge / LineGauge | Labeled progress bars with percentage/ratio and fractional-cell rendering | Downloads, jobs and task progress require custom drawing |
| BarChart / Chart / Sparkline | Numerical series rendering, grouped bars, axes, legends and compact trends | Monitoring and dashboard applications must implement their own plots |
| Canvas | Coordinate-space drawing and shape rasterization using terminal markers | No ready-made chart/shape/map drawing layer; CharacterArt only paints supplied literal artwork |
| Tabs | A horizontal tab bar with selected labels, separators and padding | Menu is vertical; application navigation needs a custom tab implementation |
| Monthly calendar | Month grid and date/event styling | No calendar component; upstream exposes this through the widget-calendar feature, enabled by its default all-widgets configuration |
| Clear / Fill | Public reusable widgets for clearing a region or repeating a symbol/style | Small convenience gap: applications can already do this with Buffer.put; an internal collection fill helper exists |

Existing widgets need narrower improvements rather than replacement:

| Component | Confirmed missing behavior | Evidence and qualification |
| --- | --- | --- |
| Panel versus Block | Multiple or bottom titles, styled title spans, independent title/border/base styles, titles without a top border, custom/thick/dashed border sets, merged border intersections and a Panel-level shadow option | [Panel](../Sources/loom/Widgets/Panel.swift) has one String title, one style and three border types; its title renderer requires a top border. [ratatui Block release source](https://raw.githubusercontent.com/ratatui/ratatui/ratatui-v0.30.2/ratatui-widgets/src/block.rs) |
| Paragraph | Direct center/right or per-line alignment, horizontal scroll offset, explicit whitespace-trimming policy when wrapping | [Paragraph](../Sources/loom/Widgets/Paragraph.swift) only stores a vertical scroll offset. Horizontal display can be composed with ScrollView; this is a missing direct API, not a general inability to scroll text. [ratatui Paragraph source](https://raw.githubusercontent.com/ratatui/ratatui/ratatui-v0.30.2/ratatui-widgets/src/paragraph.rs) |
| List | Bottom-to-top direction, content-derived multiline item heights, per-item alignment, selection prefix/repeated highlight symbol and its spacing policy, scroll padding around selection | [List](../Sources/loom/Widgets/List.swift) has explicit heights, global alignment and a custom renderRow callback. Several presentation gaps can be implemented by that callback today. [ratatui List source](https://raw.githubusercontent.com/ratatui/ratatui/ratatui-v0.30.2/ratatui-widgets/src/list.rs) |
| Table | Independently styled whole-column selection, selection prefix/spacing policy, row top/bottom margins and column flex distribution | [Table](../Sources/loom/Widgets/Table.swift) passes selectedColumn only to the selected row: current column state enables a selected cell, not a whole-column highlight. Column spacing already exists. [ratatui Table source](https://raw.githubusercontent.com/ratatui/ratatui/ratatui-v0.30.2/ratatui-widgets/src/table.rs) |
| Scrollbar | Configurable thumb/track/endpoint symbols and independent endpoint styles | [Scrollbar](../Sources/loom/Widgets/Scrollbar.swift) uses hard-coded symbols. Placement on any edge is already achievable by choosing its rectangle. [ratatui Scrollbar API](https://docs.rs/ratatui/latest/ratatui/widgets/struct.Scrollbar.html) |

The deeper rendering and developer-facing differences matter across many widgets:

| Area | Gap | Why it matters / evidence |
| --- | --- | --- |
| Flexible layout | No Flex start/end/center/space-between/around/evenly API, layout-level margins/gaps/overlap, spacer output or layout cache | [Layout.swift](../Sources/loom/Rendering/Layout.swift) exposes direction and constraints and places adjacent rectangles from the origin. Manual spacers/insets are possible. Caching is an available upstream feature, not evidence that loom is slow. [ratatui Layout](https://docs.rs/ratatui/latest/ratatui/layout/struct.Layout.html) |
| Constraint semantics | Names match, allocation policies differ | loom explicitly clips equal-priority requests in source order and grows maximum-bounded areas after requested sizes. Ratatui uses a solver and different priority rules. This is a compatibility difference, not an absent constraint; existing loom behavior should not change silently. [loom Layout](../Sources/loom/Rendering/Layout.swift), [ratatui Constraint](https://docs.rs/ratatui/latest/ratatui/layout/enum.Constraint.html) |
| Style composition | No public style patch with independent inheritance/reset and modifier addition/removal | [TextLayout.paint](../Sources/loom/Text/TextLayout.swift) uses glyph.style ?? style, so a bold-only glyph style replaces its parent foreground/background. Collections have a separate private merge that ORs booleans, preventing removal of inherited modifiers. [CollectionRendering](../Sources/loom/Widgets/CollectionRendering.swift), [ratatui Style](https://docs.rs/ratatui/latest/ratatui/style/struct.Style.html) |
| Style attributes | No dim, crossed-out, hidden, slow/rapid blink or underline color | [Style](../Sources/loom/Rendering/Style.swift) and its encoder support bold, italic, underline and reverse plus foreground/background. Dim and strikethrough have greater general usefulness than blink. [ratatui Modifier](https://docs.rs/ratatui/latest/ratatui/style/struct.Modifier.html) |
| Managed terminal viewports | No inline viewport, nonzero-origin fixed terminal viewport, or insert-before output above a persistent UI | [Terminal](../Sources/loom/Rendering/Terminal.swift) owns an origin-zero buffer; [CellDiff](../Sources/loom/Rendering/CellDiff.swift) clears the screen on a full repaint. Drawing a widget in a smaller rectangle does not provide scrollback-preserving terminal ownership. [ratatui Terminal](https://docs.rs/ratatui/latest/ratatui/struct.Terminal.html) |
| Resize/lifecycle conveniences | No draw-time backend size check or combined init/run/restore helper at the loom renderer layer | Resize events, explicit resize and weft session cleanup already exist. These are convenience differences and should respect application/session ownership. [loom Architecture](Architecture.md), [ratatui Terminal](https://docs.rs/ratatui/latest/ratatui/struct.Terminal.html) |
| Public testing backend | No reusable virtual-screen backend with cursor/scrollback inspection and buffer assertions | loom has direct Buffer tests and a test-only MemoryBackend collecting bytes, but no equivalent downstream testing product. [TestSupport](../Tests/loomTests/TestSupport.swift), [ratatui TestBackend](https://docs.rs/ratatui/latest/ratatui/backend/struct.TestBackend.html) |
| Buffer utilities | No public region style patch, merge/compositing operation, checked mutable cell access, resize-in-place or backend-neutral cell-diff iterator | [Buffer](../Sources/loom/Rendering/Buffer.swift) supplies reads, reset, clipping, put and highlight. Applications can reproduce some operations with loops. [ratatui Buffer](https://docs.rs/ratatui/latest/ratatui/buffer/struct.Buffer.html) |
| Specialized cell diff control | No per-cell skip/always-update or arbitrary forced-width diff options | Conditional need for specialized rendering/graphics integrations; preserve loom's control-character filtering. [Cell](../Sources/loom/Rendering/Cell.swift), [ratatui cell diff additions](https://ratatui.rs/highlights/v0301/#buffer-cell-diff-options) |
| Backend portability | A generic byte-output Backend exists, but rendering always encodes ANSI; no bundled semantic alternative backends or Windows session implementation | Ratatui has Crossterm, Termina, Termion, Termwiz and TestBackend. loom/weft's current backend is a Data sink, and session implementation is POSIX. This is not an absence of abstraction, but a narrower abstraction. [CellDiff](../Sources/loom/Rendering/CellDiff.swift), [ratatui backends](https://ratatui.rs/concepts/backends/) |

The comparison should preserve loom's strengths. Ratatui core leaves input handling to the application/backend and recommends separate editor crates for functional text editing. loom already bundles focus scopes, key maps/help, editable documents, undo/redo, Markdown, streaming snapshots, popup menus, window/desktop primitives and animation helpers. Ratatui's broader ecosystem can supply alternatives, but that is a different comparison. [ratatui input example](https://ratatui.rs/examples/apps/user_input/), [core input-handling boundary](https://docs.rs/ratatui/latest/ratatui/#handling-events)

There are additional useful loom opportunities outside strict ratatui-core parity:

- Reusable forms, validation/error presentation, password masking, dedicated button/checkbox/radio/select controls, trees and file pickers. Existing input, menu, focus and selection primitives provide part of the foundation. Ratatui classifies specialized widgets separately in its [third-party showcase](https://ratatui.rs/showcase/third-party-widgets/).
- A richer input controller. LineEditor exposes movement and editing operations, but applications still wire modifiers, selection gestures, up/down, undo/redo, paste/copy/cut and completion acceptance. [LineEditor](../Sources/loom/Text/LineEditor.swift), [browser event routing](../Examples/Browser/BrowserApplication.swift)
- Search beyond the existing case-insensitive next-entry substring search: match ranges, all-occurrence highlighting, regex/fuzzy matching and replacement. [TextDocument.find](../Sources/loom/Text/TextDocument.swift)
- Markdown table rendering. The general Table widget exists, but MarkdownRenderer intentionally preserves Markdown tables as literal source. Strikethrough, images and HTML also have literal-source fallbacks; syntax highlighting is a host hook. [MarkdownRenderer](../Sources/loom/Text/MarkdownRenderer.swift), [Markdown tests](../Tests/loomTests/MarkdownTextTests.swift)
- Incremental Markdown parsing. Streaming snapshots already expose stable/pending content and final-reflow requirements, but updates reparse the full source. Scrollback anchoring remains application-owned. No timing comparison was performed. [MarkdownStreamingSnapshot](../Sources/loom/Text/MarkdownStreamingSnapshot.swift), [README](../README.md)
- Multi-event key sequences and command-palette helpers. Current bindings match a single logical key plus modifiers. [KeyMap](../Sources/loom/Interaction/KeyMap.swift)
- Distribution and validation depth: no checked-in CI workflow, DocC catalog or benchmark suite was found. There are two executable examples and two PTY smoke scripts. The README explicitly limits release validation to macOS; Linux and Windows were not tested by this audit. A render-only package product is also absent; Swift Markdown is mandatory for loom consumers. [Package.swift](../Package.swift), [README](../README.md)

Recommended implementation order is an engineering judgment based on reuse, not a claim about the user's next application:

1. **Style composition and flexible layout**, then Paragraph/Panel improvements. These reduce custom work across almost every interface.
2. **Gauge, LineGauge, Tabs and public Clear/Fill helpers** for frequently needed application UI.
3. **A public testing backend and managed inline/fixed viewports** together. Move this ahead of widgets if shell-native prompts and preserved scrollback are the immediate goal. Keep terminal I/O/session authority in weft.
4. **List/table/scrollbar customization**, followed by **Sparkline, BarChart, Chart and Canvas** according to actual dashboard needs.
5. **Calendar, alternate platforms/backends and specialized diff hooks** when product requirements justify them. Profile before adding layout caches or changing algorithms for performance.

Validation on this local macOS checkout passed: `scripts/check-format.sh`; `swift test` with **158 Swift Testing tests**; sequential builds of `loom-demo` and `loom-browser`; `scripts/smoke.py` and `scripts/smoke-browser.py`. The browser PTY check covers filtering, focus, sorting, marks, modal restoration, wheel/drag interaction, resize and cleanup. These are local unit/PTY checks, not a full terminal-emulator matrix, Linux/Windows certification, a fresh-clone dependency test or a performance comparison. No implementation changes were made for this audit.
