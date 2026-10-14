import weft

/// The axis along which a layout allocates regions.
public enum Direction: Hashable, Sendable {
    case horizontal
    case vertical
}

/// How unused cells surround allocated layout regions.
public enum Flex: Hashable, Sendable, CaseIterable {
    case start
    case end
    case center
    case spaceBetween
    case spaceAround
    case spaceEvenly
}

/// Nonnegative terminal-cell insets, clamped against the supplied area during layout.
public struct LayoutInsets: Hashable, Sendable {
    public var left: Int
    public var right: Int
    public var top: Int
    public var bottom: Int

    public init(left: Int = 0, right: Int = 0, top: Int = 0, bottom: Int = 0) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public init(all cells: Int) {
        self.init(left: cells, right: cells, top: cells, bottom: cells)
    }
}

/// A fixed, relative, bounded, or weighted share of terminal cells.
public enum Constraint: Hashable, Sendable {
    /// A lower bound, with equal shares of excess space when there are no positive fills.
    case min(Int)
    /// An upper bound; grows toward the limit after minimum and requested sizes are satisfied.
    case max(Int)
    /// A requested cell count, clipped when higher-priority requests exhaust the area.
    case length(Int)
    /// A requested percentage of the original axis length, clamped to 0...100.
    case percentage(Int)
    /// A requested fraction of the original axis length; a nonpositive denominator requests zero.
    case ratio(Int, Int)
    /// A proportional share of excess cells; nonpositive weights receive no cells.
    case fill(Int)
}

/// Splits an area into regions in its original constraint order; explicit overlap is opt-in.
///
/// Minimum bounds are reserved first, followed by length, percentage, and ratio requests.
/// Equal-priority requests are clipped in source order when the area is too small.
/// Maximum-bounded regions then share excess cells equally until their caps are reached.
/// Weighted fills consume what remains, or minimum-bounded regions grow equally if no
/// positive fill exists. Otherwise unused cells trail the last region.
public struct Layout: Hashable, Sendable {
    public var direction: Direction
    public var constraints: [Constraint]
    public var insets: LayoutInsets
    public var spacing: Int
    public var flex: Flex
    public var overlap: Int = 0

    public init(
        _ direction: Direction, _ constraints: [Constraint], insets: LayoutInsets = LayoutInsets(),
        spacing: Int = 0, flex: Flex = .start
    ) {
        self.direction = direction
        self.constraints = constraints
        self.insets = insets
        self.spacing = spacing
        self.flex = flex
    }

    /// Explicitly chooses a gap or overlap in terminal cells.
    ///
    /// Negative amounts clamp to zero.
    public init(
        _ direction: Direction, _ constraints: [Constraint], insets: LayoutInsets = LayoutInsets(),
        spacing: LayoutSpacing, flex: Flex = .start
    ) {
        self.init(direction, constraints, insets: insets, spacing: 0, flex: flex)
        switch spacing {
        case .gap(let cells): self.spacing = max(0, cells)
        case .overlap(let cells): self.overlap = max(0, cells)
        }
    }

    /// Uses only the caller-owned cache; ordinary split calls remain uncached.
    public func split(_ area: Rect, cache: inout LayoutCache) -> [Rect] {
        cache.split(self, area: area)
    }

    /// Returns a region for every constraint, including zero-sized regions.
    public func split(_ area: Rect) -> [Rect] {
        // Rect fields are mutable. Clamp both dimensions before doing coordinate arithmetic.
        let originalWidth = representableLength(area.width, origin: area.x)
        let originalHeight = representableLength(area.height, origin: area.y)
        let left = min(originalWidth, max(0, insets.left))
        let right = min(originalWidth - left, max(0, insets.right))
        let top = min(originalHeight, max(0, insets.top))
        let bottom = min(originalHeight - top, max(0, insets.bottom))
        let width = originalWidth - left - right
        let height = originalHeight - top - bottom
        let origin = Point(x: area.x + left, y: area.y + top)
        let axisLength = direction == .vertical ? height : width
        let gaps = max(0, constraints.count - 1)
        let gap = gaps == 0 ? 0 : min(max(0, spacing), axisLength / gaps)
        // Fractions use the cells available for regions after insets and reserved gaps.
        let total = axisLength - gap * gaps
        var remaining = total
        var lengths = Array(repeating: 0, count: constraints.count)

        for priority in 0...3 {
            for (index, constraint) in constraints.enumerated() {
                guard let requested = requestedLength(for: constraint, priority: priority, total: total) else {
                    continue
                }
                lengths[index] = min(requested, remaining)
                remaining -= lengths[index]
            }
        }

        growMaximums(lengths: &lengths, remaining: &remaining)
        let fillWeights = constraints.map { constraint in
            if case let .fill(weight) = constraint { return max(0, weight) }
            return 0
        }
        let growthWeights =
            fillWeights.contains(where: { $0 > 0 })
            ? fillWeights
            : constraints.map { constraint in
                if case .min = constraint { return 1 }
                return 0
            }
        var remainingWeight = LayoutWeight(growthWeights)
        for (index, weight) in growthWeights.enumerated() where weight > 0 {
            let growth = remainingWeight.share(of: remaining, weight: weight)
            lengths[index] += growth
            remaining -= growth
            remainingWeight.subtract(UInt(weight))
        }

        let overlaps = lengths.indices.dropLast().map { index in
            min(max(0, overlap), min(lengths[index], lengths[index + 1]))
        }
        let freed = overlaps.reduce(0, +)
        let spaces = distributedSpaces(remaining + freed, count: lengths.count)
        var offset = spaces.first ?? 0
        return lengths.enumerated().map { index, length in
            let region =
                direction == .vertical
                ? Rect(x: origin.x, y: origin.y + offset, width: width, height: length)
                : Rect(x: origin.x + offset, y: origin.y, width: length, height: height)
            offset += length
            if index + 1 < lengths.count { offset += gap + spaces[index + 1] - overlaps[index] }
            return region
        }
    }

    /// Remainders go to earlier spacer slots.
    ///
    /// Fill/min growth precedes flex placement.
    private func distributedSpaces(_ remaining: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var weights = Array(repeating: 0, count: count + 1)
        switch flex {
        case .start:
            weights[count] = 1
        case .end:
            weights[0] = 1
        case .center:
            weights[0] = 1
            weights[count] = 1
        case .spaceBetween:
            if count == 1 { weights[count] = 1 } else { for index in 1..<count { weights[index] = 1 } }
        case .spaceAround:
            weights = Array(repeating: 2, count: count + 1)
            weights[0] = 1
            weights[count] = 1
        case .spaceEvenly:
            weights = Array(repeating: 1, count: count + 1)
        }
        let totalWeight = weights.reduce(0, +)
        let share = remaining / totalWeight
        var extra = remaining % totalWeight
        return weights.map { weight in
            let remainder = min(extra, weight)
            extra -= remainder
            return share * weight + remainder
        }
    }

    private func requestedLength(for constraint: Constraint, priority: Int, total: Int) -> Int? {
        switch (priority, constraint) {
        case let (0, .min(length)), let (1, .length(length)):
            return max(0, length)
        case let (2, .percentage(percent)):
            return fraction(of: total, numerator: min(100, max(0, percent)), denominator: 100)
        case let (3, .ratio(numerator, denominator)) where denominator > 0:
            return fraction(of: total, numerator: min(denominator, max(0, numerator)), denominator: denominator)
        default:
            return nil
        }
    }

    private func growMaximums(lengths: inout [Int], remaining: inout Int) {
        var capped: [(index: Int, limit: Int)] = constraints.enumerated().compactMap { index, constraint in
            guard case let .max(limit) = constraint, limit > 0 else { return nil }
            return (index, limit)
        }
        // Satisfy small caps first, then share the remainder without iterating cell by cell.
        capped.sort { $0.limit == $1.limit ? $0.index < $1.index : $0.limit < $1.limit }
        var firstUncapped = 0
        while firstUncapped < capped.count {
            let region = capped[firstUncapped]
            let equalShare = remaining / (capped.count - firstUncapped)
            guard region.limit <= equalShare else { break }
            lengths[region.index] = region.limit
            remaining -= region.limit
            firstUncapped += 1
        }
        let uncapped = capped.dropFirst(firstUncapped).sorted { $0.index < $1.index }
        var count = uncapped.count
        for region in uncapped {
            let growth = min(region.limit, remaining / count)
            lengths[region.index] = growth
            remaining -= growth
            count -= 1
        }
    }

    private func fraction(of total: Int, numerator: Int, denominator: Int) -> Int {
        let product = UInt(total).multipliedFullWidth(by: UInt(numerator))
        return Int(UInt(denominator).dividingFullWidth(product).quotient)
    }

    private func representableLength(_ length: Int, origin: Int) -> Int {
        min(max(0, length), origin > 0 ? Int.max - origin : Int.max)
    }
}

/// Two words keep sums and proportional products exact even when fill weights total more than UInt.max.
private struct LayoutWeight {
    private var high: UInt = 0
    private var low: UInt = 0

    init(_ weights: [Int]) {
        for weight in weights {
            let sum = low.addingReportingOverflow(UInt(weight))
            low = sum.partialValue
            if sum.overflow { high += 1 }
        }
    }

    mutating func subtract(_ weight: UInt) {
        let difference = low.subtractingReportingOverflow(weight)
        low = difference.partialValue
        if difference.overflow { high -= 1 }
    }

    func share(of cells: Int, weight: Int) -> Int {
        let product = UInt(cells).multipliedFullWidth(by: UInt(weight))
        if high == 0 {
            return Int(low.dividingFullWidth(product).quotient)
        }
        guard product.high > high || (product.high == high && product.low >= low) else { return 0 }

        // Long division is needed only for weight sums larger than one machine word.
        let shift = high.leadingZeroBitCount - product.high.leadingZeroBitCount
        var divisorHigh = high << shift
        var divisorLow = low << shift
        if shift > 0 { divisorHigh |= low >> (UInt.bitWidth - shift) }
        var remainder = product
        var quotient: UInt = 0
        for bit in stride(from: shift, through: 0, by: -1) {
            if remainder.high > divisorHigh || (remainder.high == divisorHigh && remainder.low >= divisorLow) {
                let difference = remainder.low.subtractingReportingOverflow(divisorLow)
                remainder.low = difference.partialValue
                remainder.high -= divisorHigh
                if difference.overflow { remainder.high -= 1 }
                quotient |= UInt(1) << bit
            }
            divisorLow = (divisorLow >> 1) | (divisorHigh << (UInt.bitWidth - 1))
            divisorHigh >>= 1
        }
        return Int(quotient)
    }
}
