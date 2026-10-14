/// A labeled tab with a caller-owned stable identity.
public struct Tab<ID: Hashable & Sendable>: Sendable {
    public var id: ID
    public var label: String

    public init(id: ID, label: String) {
        self.id = id
        self.label = label
    }
}

/// A single row of tabs.
///
/// Selection and event routing remain caller-owned.
/// Overflow starts at the selected tab when it would otherwise be clipped.
public struct Tabs<ID: Hashable & Sendable>: Widget {
    public var tabs: [Tab<ID>]
    public var selected: ID?
    public var separator: String
    public var padding: Int
    public var style: Style
    public var selectedStyle: Style

    public init(
        _ tabs: [Tab<ID>], selected: ID? = nil, separator: String = "│", padding: Int = 1,
        style: Style = Style(), selectedStyle: Style = Style(reversed: true)
    ) {
        self.tabs = tabs
        self.selected = selected
        self.separator = separator
        self.padding = padding
        self.style = style
        self.selectedStyle = selectedStyle
    }

    /// Returns the tab occupying a painted label or padding cell; separators have no target.
    public func hitTest(_ point: Point, in area: Rect) -> ID? {
        guard point.y == area.y else { return nil }
        return geometry(in: area).first { $0.area.contains(point) }.map { tabs[$0.index].id }
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        guard area.width > 0, area.height > 0 else { return }
        let positions = geometry(in: area)
        buffer.withClip(area) { target in
            for (positionIndex, position) in positions.enumerated() {
                let tabStyle = tabs[position.index].id == selected ? selectedStyle : style
                Fill(style: tabStyle).render(in: position.area, buffer: &target)
                let inset = min(max(0, padding), max(0, position.area.width - 1) / 2)
                TextLayout(tabs[position.index].label, width: max(1, position.area.width - 2 * inset), wrapping: .none)
                    .paint(
                        in: Rect(
                            x: position.area.x + inset, y: area.y,
                            width: position.area.width - 2 * inset, height: 1), style: tabStyle, buffer: &target)
                if positionIndex + 1 < positions.count {
                    let next = positions[positionIndex + 1].area.x
                    TextLayout(separator, width: max(1, next - position.area.maxX), wrapping: .none).paint(
                        in: Rect(
                            x: position.area.maxX, y: area.y,
                            width: next - position.area.maxX, height: 1), style: style, buffer: &target)
                }
            }
        }
    }

    private func geometry(in area: Rect) -> [(index: Int, area: Rect)] {
        guard area.width > 0, area.height > 0, !tabs.isEmpty else { return [] }
        let pad = min(max(0, padding), area.width)
        func width(_ text: String) -> Int {
            let layout = TextLayout(text, width: area.width, wrapping: .none)
            return layout.lines.first?.glyphs.last.map { $0.column + $0.width } ?? 0
        }
        let separatorWidth = width(separator)
        let widths = tabs.map { tab in
            let labelWidth = min(area.width, width(tab.label))
            let paddingWidth = min(area.width - labelWidth, pad)
            return labelWidth + paddingWidth + min(area.width - labelWidth - paddingWidth, pad)
        }
        let selectedIndex = tabs.firstIndex { $0.id == selected } ?? 0
        var start = 0
        var used = 0
        for index in 0...selectedIndex {
            let gap = index > 0 ? separatorWidth : 0
            if gap > area.width - used || widths[index] > area.width - used - gap {
                start = selectedIndex
                break
            }
            used += gap + widths[index]
        }
        var result: [(index: Int, area: Rect)] = []
        var offset = 0
        for index in start..<tabs.count {
            if !result.isEmpty {
                guard separatorWidth < area.width - offset else { break }
                offset += separatorWidth
            }
            guard offset < area.width else { break }
            let visibleWidth = min(widths[index], area.width - offset)
            if visibleWidth > 0 {
                result.append((index, Rect(x: area.x + offset, y: area.y, width: visibleWidth, height: 1)))
            }
            offset += visibleWidth
        }
        return result
    }
}
