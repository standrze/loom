# loom documentation

The published release is **0.2.1**, paired with **weft 0.2.1 or newer**.
Use the [getting-started guide](https://swiftloom.dev/docs/loom/) and
[stable API reference](https://swiftloom.dev/docs/loom/api/) for that release.
These repository guides describe this branch; unreleased additions are marked.

| Guide | Scope |
| --- | --- |
| [Architecture](Architecture.md) | Frames, widgets, text geometry, application ownership |
| [Collections and interaction](Collections.md) | Stable IDs, lists/tables, scrolling, focus and keys |
| [Common widgets](CommonWidgets.md) | Gauges, tabs, fills and rich panel titles |
| [Widget and rendering details](WidgetRenderingDetails.md) | Borders/shadows, row measurement, wrapping, layout cache, buffers and backends |
| [Plotting and calendars](Plotting.md) | Sparkline, grouped bars, Chart, Canvas and MonthlyCalendar |
| [Viewports](Viewports.md) | Fixed/inline placement, scrollback insertion and recovery |
| [Platform support](PlatformSupport.md) | Unicode policy, macOS/Linux/Windows evidence and native Windows boundaries |
| [API customization — unreleased](APICustomization.md) | Repeated prefixes, column flex, independent titles, line alignment, markers, legends, fills and diff controls |

The [unreleased reference](https://swiftloom.dev/docs/loom/api-next/) describes
[PR #2](https://github.com/standrze/loom/pull/2), based on source revision
`0ac2ae4`. These APIs preserve current defaults and shared paint/hit/copy
geometry, but are not available from the 0.2.1 tag.

## Validation and historical records

[PR #2 CI](https://github.com/standrze/loom/actions/runs/39126908787) passed
315 tests and all executable builds on macOS, Windows, and Linux under C and
C.UTF-8. macOS and Linux additionally passed the four PTY checks. weft validates
native console restoration/input and ConPTY separately. These checks do not
establish every terminal emulator/font combination or performance parity.

The [original Ratatui audit](RatatuiAudit.md), [feature gap plan](FeatureGapPlan.md)
and [implementation record](FeatureGapImplementation.md) preserve dated findings
and validation counts. Their original missing-feature tables are historical;
see the audit's current status table before treating an entry as an open gap.
