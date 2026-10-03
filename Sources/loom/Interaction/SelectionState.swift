/// Stable single selection, optional marked items, and vertical scrolling for lists and tables.
///
/// IDs must be unique. Synchronizing a filtered data set preserves surviving IDs and removes
/// hidden marks. If the selected ID disappears, selection moves to the nearest surviving index.
/// No item is selected automatically when selection was nil.
public struct SelectionState<ID: Hashable> {
    public private(set) var selectedID: ID?
    public private(set) var markedIDs: Set<ID> = []
    public var scroll = ScrollState()
    public private(set) var ids: [ID] = []
    private var indices: [ID: Int] = [:]
    private var starts: [Int] = [0]

    public var selectedIndex: Int? { selectedID.flatMap { indices[$0] } }

    public init(selectedID: ID? = nil) {
        self.selectedID = selectedID
    }

    /// Updates row geometry in terminal rows.
    ///
    /// Row heights are at least one. Call after data or geometry changes, before dispatching events. Stateful widgets also
    /// call this when drawing. An unchanged draw does not pull a manually scrolled view back.
    public mutating func update(ids: [ID], heights: [Int], viewportLength: Int) {
        precondition(ids.count == heights.count, "Every item needs a height")
        let oldIndex = selectedIndex
        let oldIDs = self.ids
        let oldStarts = starts
        let oldViewport = scroll.viewportLength
        self.ids = ids
        indices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        starts = [0]
        for height in heights {
            let sum = starts.last!.addingReportingOverflow(max(1, height))
            precondition(!sum.overflow, "Total row height exceeds Int.max")
            starts.append(sum.partialValue)
        }
        if let selectedID, indices[selectedID] == nil {
            self.selectedID = ids.isEmpty ? nil : ids[min(oldIndex ?? 0, ids.count - 1)]
        }
        markedIDs.formIntersection(Set(ids))
        scroll.update(contentLength: starts.last!, viewportLength: viewportLength)
        if ids != oldIDs || starts != oldStarts || oldViewport != scroll.viewportLength {
            revealSelection()
        }
    }

    public mutating func select(_ id: ID?) {
        guard id == nil || indices[id!] != nil else { return }
        selectedID = id
        revealSelection()
    }

    public mutating func moveSelection(by distance: Int) {
        guard !ids.isEmpty else { return }
        guard let index = selectedIndex else {
            select(distance < 0 ? ids.last : ids.first)
            return
        }
        let delta = distance >= 0 ? min(distance, ids.count - 1 - index) : max(distance, -index)
        select(ids[index + delta])
    }

    public mutating func selectFirst() { select(ids.first) }
    public mutating func selectLast() { select(ids.last) }

    /// Moves selection by a viewport of rows, including variable-height items.
    public mutating func pageSelection(by pages: Int) {
        guard !ids.isEmpty, pages != 0 else { return }
        guard let index = selectedIndex else {
            select(pages < 0 ? ids.last : ids.first)
            return
        }
        var position = ScrollState(contentLength: scroll.contentLength, viewportLength: 1, offset: starts[index])
        let distance = max(1, scroll.viewportLength).multipliedReportingOverflow(by: pages)
        position.scroll(by: distance.overflow ? (pages < 0 ? Int.min : Int.max) : distance.partialValue)
        let target = self.index(atRow: position.offset) ?? index
        if target == index { moveSelection(by: pages < 0 ? -1 : 1) } else { select(ids[target]) }
    }

    public mutating func toggleMarked(_ id: ID) {
        guard indices[id] != nil else { return }
        if !markedIDs.insert(id).inserted { markedIDs.remove(id) }
    }

    public mutating func markAll() { markedIDs = Set(ids) }
    public mutating func clearMarks() { markedIDs.removeAll() }

    public mutating func revealSelection() {
        if let index = selectedIndex { scroll.reveal(rowRange(at: index)) }
    }

    /// Content rows occupied by an item; the index must belong to `ids`.
    public func rowRange(at index: Int) -> Range<Int> { starts[index]..<starts[index + 1] }

    /// Finds the item under a content row using the same geometry as rendering.
    public func index(atRow row: Int) -> Int? {
        guard row >= 0, row < scroll.contentLength else { return nil }
        var lower = 0
        var upper = ids.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if starts[middle + 1] <= row { lower = middle + 1 } else { upper = middle }
        }
        return lower < ids.count ? lower : nil
    }

    public var visibleIndices: Range<Int> {
        let rows = scroll.visibleRange
        guard !rows.isEmpty, let first = index(atRow: rows.lowerBound), let last = index(atRow: rows.upperBound - 1)
        else { return 0..<0 }
        return first..<(last + 1)
    }

    /// Optional default keys; Space toggles marks only when explicitly enabled.
    @discardableResult
    public mutating func handle(_ event: InputEvent, allowsMultipleSelection: Bool = false) -> Bool {
        if KeyChord(.up).matches(event) {
            moveSelection(by: -1)
        } else if KeyChord(.down).matches(event) {
            moveSelection(by: 1)
        } else if KeyChord(.home).matches(event) {
            selectFirst()
        } else if KeyChord(.end).matches(event) {
            selectLast()
        } else if KeyChord(.pageUp).matches(event) {
            pageSelection(by: -1)
        } else if KeyChord(.pageDown).matches(event) {
            pageSelection(by: 1)
        } else if allowsMultipleSelection, KeyChord(.character(" ")).matches(event) {
            if let selectedID { toggleMarked(selectedID) }
        } else if case .mouse = event {
            return scroll.handle(event)
        } else {
            return false
        }
        return true
    }
}

extension SelectionState: Sendable where ID: Sendable {}
