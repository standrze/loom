import Foundation
import loom

/// Deterministic logical cells for external review tools; no terminal session or ANSI output.
enum WidgetSnapshot {
    static func exportIfRequested(arguments: [String]) throws -> Bool {
        guard ["--snapshot", "--snapshot-details", "--snapshot-plots"].contains(arguments.first ?? "") else {
            return false
        }
        guard arguments.count == 3, let width = Int(arguments[1]), let height = Int(arguments[2]),
            (1...1000).contains(width), (1...1000).contains(height), width * height <= 250_000
        else {
            throw NSError(
                domain: "loom-widgets", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Usage: loom-widgets --snapshot WIDTH HEIGHT (1...1000 each; at most 250000 cells)"
                ])
        }
        var application = WidgetsApplication()
        var frame = Frame(width: width, height: height)
        if arguments.first == "--snapshot-details" {
            var details = WidgetsDetails()
            details.render(&frame)
        } else if arguments.first == "--snapshot-plots" {
            WidgetsPlots().render(&frame)
        } else {
            application.render(&frame)
        }
        let rows: [[[String: Any]]] = (0..<height).map { y in
            (0..<width).map { x in
                let cell = frame.buffer[x, y]
                return [
                    "symbol": cell.symbol, "width": cell.width,
                    "link": cell.link.map { $0 as Any } ?? NSNull(),
                    "style": style(cell.style),
                ]
            }
        }
        let snapshot: [String: Any] = [
            "width": width, "height": height, "rows": rows,
            "cursor": frame.cursor.map { ["x": $0.x, "y": $0.y] as Any } ?? NSNull(),
        ]
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        try FileHandle.standardOutput.write(contentsOf: data)
        try FileHandle.standardOutput.write(contentsOf: Data([0x0a]))
        return true
    }

    private static func style(_ style: Style) -> [String: Any] {
        [
            "foreground": color(style.foreground), "background": color(style.background),
            "bold": style.bold, "italic": style.italic, "underlined": style.underlined,
            "reversed": style.reversed, "dim": style.dim, "strikethrough": style.strikethrough,
            "underlineColor": color(style.underlineColor), "hidden": style.hidden,
            "blink": style.blink == .none ? "none" : style.blink == .slow ? "slow" : "rapid",
        ]
    }

    private static func color(_ color: Color) -> [String: Any] {
        switch color {
        case .terminalDefault: return ["kind": "default"]
        case let .indexed(index): return ["kind": "indexed", "index": Int(index)]
        case let .rgb(red, green, blue):
            return ["kind": "rgb", "red": Int(red), "green": Int(green), "blue": Int(blue)]
        }
    }
}
