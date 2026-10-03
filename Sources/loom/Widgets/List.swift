/// A list row with a stable application identity, styled text, and an explicit terminal-row height.
public struct ListItem<ID: Hashable>: Identifiable {
    public var id: ID
    public var spans: [TextSpan]
    public var height: Int
    public var style: Style

    public init(id: ID, _ text: String, height: Int = 1, style: Style = Style()) {
        self.init(id: id, spans: [TextSpan(text)], height: height, style: style)
    }

    public init(id: ID, spans: [TextSpan], height: Int = 1, style: Style = Style()) {
        self.id = id
        self.spans = spans
        self.height = height
        self.style = style
    }
}

/// Presentation passed to a custom list row renderer.
public struct ListRowAppearance: Sendable {
    public let isSelected: Bool
    public let isMarked: Bool
    public let style: Style
}

/// A selectable, scrollable collection with custom row rendering and shared hit-test geometry.
///
/// Sorting/filtering belong to the caller. Pass stable, unique IDs for selection to survive
/// reordering. Only visible rows are rendered. Row heights are explicit, not measured implicitly.
public struct List<ID: Hashable>: StatefulWidget {
    public var items: [ListItem<ID>]
    public var style = Style()
    public var selectionStyle = Style(reversed: true)
    public var markedStyle = Style(bold: true)
    public var emptyMessage = "No items"
    public var alignment: CellAlignment = .left

    /// Optional custom drawing, clipped to the row and viewport.
    ///
    /// Coordinates remain absolute.
    public var renderRow: ((ListItem<ID>, ListRowAppearance, Rect, inout Buffer) -> Void)?

    public init(_ items: [ListItem<ID>]) {
        self.items = items
    }

    /// Synchronizes data/geometry before event dispatch.
    ///
    /// Rendering also calls this method.
    public func update(in area: Rect, state: inout SelectionState<ID>) {
        state.update(ids: items.map(\.id), heights: items.map(\.height), viewportLength: max(0, area.height))
    }

    public func render(in area: Rect, buffer: inout Buffer, state: inout SelectionState<ID>) {
        update(in: area, state: &state)
        guard area.width > 0, area.height > 0 else { return }
        buffer.withClip(area) { buffer in
            fillCollectionArea(area, style: style, buffer: &buffer)
            if items.isEmpty {
                paintCollectionText([TextSpan(emptyMessage)], in: area, style: style, buffer: &buffer)
            }
            for index in state.visibleIndices {
                let item = items[index]
                let rows = state.rowRange(at: index)
                let rowArea = Rect(
                    x: area.x, y: area.y + rows.lowerBound - state.scroll.offset,
                    width: area.width, height: rows.count)
                let selected = state.selectedID == item.id
                let marked = state.markedIDs.contains(item.id)
                var overlay = marked ? markedStyle : Style()
                if selected { overlay = collectionStyle(overlay, overlay: selectionStyle) }
                let base = collectionStyle(style, overlay: item.style)
                let rowStyle = collectionStyle(base, overlay: overlay)
                buffer.withClip(rowArea) { buffer in
                    fillCollectionArea(rowArea, style: rowStyle, buffer: &buffer)
                    if let renderRow {
                        renderRow(
                            item, ListRowAppearance(isSelected: selected, isMarked: marked, style: rowStyle),
                            rowArea, &buffer)
                    } else {
                        paintCollectionText(
                            item.spans, in: rowArea, alignment: alignment,
                            style: base, overlay: overlay, buffer: &buffer)
                    }
                }
            }
        }
    }

    /// Call after update/draw with the same items and area.
    ///
    /// Padding below the last item returns nil.
    public func item(at point: Point, in area: Rect, state: SelectionState<ID>) -> ID? {
        guard area.contains(point), let index = state.index(atRow: state.scroll.offset + point.y - area.y),
            items.indices.contains(index), state.ids[index] == items[index].id
        else { return nil }
        return items[index].id
    }
}

extension ListItem: Sendable where ID: Sendable {}
