/// A list row with a stable application identity, styled text, and an explicit terminal-row height.
public struct ListItem<ID: Hashable>: Identifiable {
    public var id: ID
    public var spans: [TextSpan]
    public var height: Int
    public var style: Style
    public var patch: StylePatch?
    public var alignment: CellAlignment?

    public init(
        id: ID, _ text: String, height: Int = 1, style: Style = Style(), alignment: CellAlignment? = nil,
        patch: StylePatch? = nil
    ) {
        self.init(id: id, spans: [TextSpan(text)], height: height, style: style, alignment: alignment, patch: patch)
    }

    public init(
        id: ID, spans: [TextSpan], height: Int = 1, style: Style = Style(), alignment: CellAlignment? = nil,
        patch: StylePatch? = nil
    ) {
        self.id = id
        self.spans = spans
        self.height = height
        self.style = style
        self.alignment = alignment
        self.patch = patch
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
/// reordering. Only visible rows are rendered. Row heights are explicit by default; automatic measurement is opt-in.
public struct List<ID: Hashable>: StatefulWidget {
    public var items: [ListItem<ID>]
    public var style = Style()
    public var selectionStyle = Style(reversed: true)
    public var markedStyle = Style(bold: true)
    public var selectionSymbol = ""
    /// Repeats the selection symbol on every terminal row of the selected item, including blank rows.
    ///
    /// The prefix width and content geometry are unchanged.
    public var repeatHighlightSymbol = false
    public var prefixReservation: SelectionPrefixReservation = .never
    public var selectionPatch: StylePatch?
    public var markedPatch: StylePatch?
    public var emptyMessage = "No items"
    public var alignment: CellAlignment = .left
    /// Places the first item at the bottom; navigation follows screen direction.
    public var reversed = false
    /// Measures default text at its final content width when enabled.
    public var automaticHeights = false
    public var wrapping: TextWrapping = .grapheme
    public var wrapOptions = TextWrapOptions()
    /// Required to measure custom row rendering; width excludes the selection prefix.
    public var measureRow: ((ListItem<ID>, Int) -> Int)?

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
        let prefix = collectionPrefixWidth(
            selectionSymbol, reservation: prefixReservation, hasSelection: state.selectedID != nil)
        let width = max(0, area.width - min(max(0, area.width), prefix))
        let heights = items.map { item in
            guard automaticHeights else { return item.height }
            if let measureRow { return max(1, measureRow(item, width)) }
            guard renderRow == nil else { return item.height }
            return TextLayout(item.spans, width: width, wrapping: wrapping, options: wrapOptions).lines.count
        }
        state.update(ids: items.map(\.id), heights: heights, viewportLength: max(0, area.height), reversed: reversed)
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
                    x: area.x,
                    y: area.y + (reversed ? max(0, area.height - state.scroll.contentLength) : 0) + rows.lowerBound
                        - state.scroll.offset,
                    width: area.width, height: rows.count)
                let selected = state.selectedID == item.id
                let marked = state.markedIDs.contains(item.id)
                var overlay = marked ? markedStyle : Style()
                if selected { overlay = collectionStyle(overlay, overlay: selectionStyle) }
                let base = collectionStyle(style, overlay: item.style).applying(item.patch ?? StylePatch())
                var rowStyle = collectionStyle(base, overlay: overlay)
                if marked { rowStyle = rowStyle.applying(markedPatch ?? StylePatch()) }
                if selected { rowStyle = rowStyle.applying(selectionPatch ?? StylePatch()) }
                let prefixWidth = min(
                    rowArea.width,
                    collectionPrefixWidth(
                        selectionSymbol, reservation: prefixReservation, hasSelection: state.selectedID != nil))
                let contentArea = Rect(
                    x: rowArea.x + prefixWidth, y: rowArea.y, width: rowArea.width - prefixWidth, height: rowArea.height
                )
                buffer.withClip(rowArea) { buffer in
                    fillCollectionArea(rowArea, style: rowStyle, buffer: &buffer)
                    if selected, prefixWidth > 0 {
                        let first = max(0, area.y, rowArea.y)
                        let last = min(buffer.height, area.maxY, repeatHighlightSymbol ? rowArea.maxY : rowArea.y + 1)
                        if first < last {
                            let prefix = TextLayout(selectionSymbol, width: prefixWidth)
                            for y in first..<last {
                                prefix.paint(
                                    in: Rect(x: rowArea.x, y: y, width: prefixWidth, height: 1),
                                    style: rowStyle, buffer: &buffer)
                            }
                        }
                    }
                    if let renderRow {
                        buffer.withClip(contentArea) { buffer in
                            renderRow(
                                item, ListRowAppearance(isSelected: selected, isMarked: marked, style: rowStyle),
                                contentArea, &buffer)
                        }
                    } else {
                        paintCollectionText(
                            item.spans, in: contentArea, alignment: item.alignment ?? alignment,
                            style: base, overlay: overlay,
                            patches: [marked ? markedPatch : nil, selected ? selectionPatch : nil].compactMap { $0 },
                            wrapping: wrapping, wrapOptions: wrapOptions, buffer: &buffer)
                    }
                }
            }
        }
    }

    /// Call after update/draw with the same items and area.
    ///
    /// Padding below the last item returns nil.
    public func item(at point: Point, in area: Rect, state: SelectionState<ID>) -> ID? {
        guard area.contains(point),
            let index = state.index(
                atRow: state.scroll.offset + point.y - area.y
                    - (reversed ? max(0, area.height - state.scroll.contentLength) : 0)),
            items.indices.contains(index), state.ids[index] == items[index].id
        else { return nil }
        return items[index].id
    }
}

extension ListItem: Sendable where ID: Sendable {}
