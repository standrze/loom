/// Explicitly merges panel edge connections.
///
/// Later insertions supply junction glyphs and style.
/// Render this layer before ordinary content; subsequent buffer writes overwrite it normally.
public struct BorderLayer: Sendable {
    private struct Entry: Sendable {
        var panel: Panel
        var area: Rect
    }
    private struct Coordinate: Hashable {
        var x: Int
        var y: Int
    }
    private struct EdgeCell {
        var connections: Int
        var doubleConnections: Int
        var panel: Panel
    }
    private var entries: [Entry] = []

    public init() {}

    /// Adds absolute panel geometry to the layer without drawing yet.
    public mutating func insert(_ panel: Panel, in area: Rect) {
        entries.append(Entry(panel: panel, area: representableBorderArea(area)))
    }

    /// Draws shadows, merged borders, then titles, respecting the buffer's current clip.
    public func render(buffer: inout Buffer) {
        var cells: [Coordinate: EdgeCell] = [:]
        for entry in entries where entry.area.width >= 2 && entry.area.height >= 2 {
            entry.panel.renderShadow(in: entry.area, buffer: &buffer)
            let area = entry.area
            func add(_ x: Int, _ y: Int, _ connections: Int) {
                let point = Coordinate(x: x, y: y)
                let previous = cells[point]
                let doubles: Int
                if case .double = entry.panel.borderType {
                    doubles = connections
                } else {
                    doubles = 0
                }
                cells[point] = EdgeCell(
                    connections: (previous?.connections ?? 0) | connections,
                    doubleConnections: ((previous?.doubleConnections ?? 0) & ~connections) | doubles,
                    panel: entry.panel)
            }
            for edge in [BorderEdges.top, .bottom] where entry.panel.borders.contains(edge) {
                let y = edge == .top ? area.y : area.maxY - 1
                for x in max(area.x, buffer.area.x)..<max(max(area.x, buffer.area.x), min(area.maxX, buffer.area.maxX))
                {
                    add(x, y, (x > area.x ? 8 : 0) | (x < area.maxX - 1 ? 2 : 0))
                }
            }
            for edge in [BorderEdges.left, .right] where entry.panel.borders.contains(edge) {
                let x = edge == .left ? area.x : area.maxX - 1
                for y in max(area.y, buffer.area.y)..<max(max(area.y, buffer.area.y), min(area.maxY, buffer.area.maxY))
                {
                    add(x, y, (y > area.y ? 1 : 0) | (y < area.maxY - 1 ? 4 : 0))
                }
            }
        }
        for (point, cell) in cells {
            buffer.put(
                cell.panel.borderType.symbol(for: cell.connections, doubleConnections: cell.doubleConnections),
                width: 1,
                at: Point(x: point.x, y: point.y), style: cell.panel.borderStyle ?? cell.panel.style)
        }
        for entry in entries where entry.area.width > 0 && entry.area.height > 0 {
            buffer.withClip(entry.area) { target in
                guard entry.panel.titlesWithoutBorders || (entry.area.width >= 2 && entry.area.height >= 2) else {
                    return
                }
                entry.panel.renderTitle(in: entry.area, buffer: &target)
                entry.panel.renderRichTitles(in: entry.area, buffer: &target)
            }
        }
    }
}

extension BorderType {
    func symbol(for connections: Int, doubleConnections: Int = 0) -> String {
        // Unicode provides mixed single/double glyphs when each axis has one weight.
        // Opposing strokes with different weights fall back to the later border family.
        if case .custom = self {
            return unmixedSymbol(for: connections)
        }
        let horizontal = connections & 10
        let vertical = connections & 5
        let doubleHorizontal = doubleConnections & 10
        let doubleVertical = doubleConnections & 5
        if horizontal != 0, vertical != 0 {
            if doubleHorizontal == horizontal, doubleVertical == 0 {
                if let symbol = [
                    3: "╘", 6: "╒", 9: "╛", 12: "╕", 7: "╞", 11: "╧",
                    13: "╡", 14: "╤", 15: "╪",
                ][connections] {
                    return symbol
                }
            } else if doubleHorizontal == 0, doubleVertical == vertical {
                if let symbol = [
                    3: "╙", 6: "╓", 9: "╜", 12: "╖", 7: "╟", 11: "╨",
                    13: "╢", 14: "╥", 15: "╫",
                ][connections] {
                    return symbol
                }
            }
        }
        return unmixedSymbol(for: connections)
    }

    private func unmixedSymbol(for connections: Int) -> String {
        let glyphs = glyphs
        switch connections {
        case 6: return glyphs.topLeft
        case 12: return glyphs.topRight
        case 3: return glyphs.bottomLeft
        case 9: return glyphs.bottomRight
        case 7, 11, 13, 14, 15:
            switch self {
            case .custom(let symbols):
                switch connections {
                case 7: return symbols.leftJunction
                case 11: return symbols.bottomJunction
                case 13: return symbols.rightJunction
                case 14: return symbols.topJunction
                default: return symbols.cross
                }
            case .double:
                return [7: "╠", 11: "╩", 13: "╣", 14: "╦", 15: "╬"][connections]!
            case .single, .rounded:
                return [7: "├", 11: "┴", 13: "┤", 14: "┬", 15: "┼"][connections]!
            }
        default:
            return connections & 5 != 0 ? glyphs.vertical : glyphs.horizontal
        }
    }
}

/// Keeps terminal geometry representable without moving the original edges into the visible buffer.
func representableBorderArea(_ area: Rect) -> Rect {
    let width = max(0, area.width)
    let height = max(0, area.height)
    return Rect(
        x: area.x, y: area.y,
        width: area.x > 0 ? min(width, Int.max - area.x) : width,
        height: area.y > 0 ? min(height, Int.max - area.y) : height)
}
