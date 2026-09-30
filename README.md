![loom: Build interfaces at the speed of thought.](Documentation/Assets/banner.svg)

[![Swift](https://img.shields.io/badge/Swift-6.4%2B-F2B45F?style=flat-square&labelColor=171813)](https://www.swift.org/)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-ready-F2B45F?style=flat-square&labelColor=171813)](Package.swift)
[![License](https://img.shields.io/badge/license-Apache--2.0-F2B45F?style=flat-square&labelColor=171813)](LICENSE)

**A Swift toolkit for expressive terminal interfaces.** Construct a complete frame
from text, layouts, and widgets. loom compares it with the previous frame and
writes the changes through [weft](https://github.com/standrze/weft).

## A canvas made of cells

| Layer | What you get |
| --- | --- |
| Rendering | Double-buffered frames, cell diffs, cursor updates, synchronized output |
| Text | Unicode cell geometry, wrapping, selection, editable documents, undo/redo |
| Content | Markdown rendered with Swift Markdown, styled spans, code blocks |
| Widgets | Panels, menus, popup menus, paragraphs, text inputs, document views |
| Detail | Character art, color blending, symbol animation, terminal color fallbacks |

Your application owns state and event handling. loom owns the frame.

## Add it with SwiftPM

Requires **Swift 6.4+**. The package declares **macOS 13+** and includes Linux
terminal code; this initial release was validated locally on macOS. Linux support
has not been verified for this release.

Add the package dependency:

```swift
.package(url: "https://github.com/standrze/loom.git", from: "0.1.0")
```

Then add its product to your target's dependencies:

```swift
.product(name: "loom", package: "loom")
```

The module name is lowercase: `import loom`.

## Draw a frame

```swift
import loom

var terminal = Terminal(backend: ANSIBackend(), width: 80, height: 24)
let greeting = Paragraph(TextLayout("Hello, 世界", width: 80))

try terminal.draw { frame in
    frame.render(greeting, in: frame.area)
    frame.cursor = Point(x: 0, y: 2)
}
```

`draw` rebuilds the logical frame. Unchanged cells do not need to be written again.
For interactive programs, open a `TerminalSession`, process events, resize the
renderer on terminal resize, and close the session on exit. The runnable example
shows that lifecycle:

```sh
swift run loom-demo
```

Type to change the displayed text. Press **Escape** or **Ctrl-C** to exit.
See [the example](Examples/Demo/Demo.swift) and [architecture](Documentation/Architecture.md).

## Development

```sh
scripts/check-format.sh
swift test
swift build --product loom-demo
python3 scripts/smoke.py .build/debug/loom-demo
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Version `0.1.0` is an early extraction
from ono-sendai; APIs may change before 1.0. Terminal behavior and character widths
vary between emulators and fonts.

## License

[Apache License 2.0](LICENSE). Dependencies retain their own licenses.
The banner is an original SVG included in this repository under the same license.
