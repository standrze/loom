import weft

/// Explicit terminal-cell spacing.
///
/// Legacy integer spacing continues to mean a nonnegative gap.
public enum LayoutSpacing: Hashable, Sendable {
    case gap(Int)
    case overlap(Int)
}

/// A caller-owned bounded least-recently-used layout cache.
///
/// No global state is retained.
public struct LayoutCache: Sendable {
    public let capacity: Int
    public var count: Int { entries.count }
    private var entries: [Entry] = []

    private struct Entry: Sendable {
        var layout: Layout
        var area: Rect
        var regions: [Rect]
    }

    public init(capacity: Int = 128) {
        self.capacity = max(0, capacity)
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }

    /// Includes every layout field and the complete input rectangle in the key.
    public mutating func split(_ layout: Layout, area: Rect) -> [Rect] {
        if let index = entries.firstIndex(where: { $0.layout == layout && $0.area == area }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.regions
        }
        let regions = layout.split(area)
        if capacity > 0 {
            if entries.count == capacity { entries.removeFirst() }
            entries.append(Entry(layout: layout, area: area, regions: regions))
        }
        return regions
    }
}
