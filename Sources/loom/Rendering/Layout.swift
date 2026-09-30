import weft

/// The axis along which a layout allocates regions.
public enum Direction: Sendable {
    case horizontal
    case vertical
}

/// A fixed, relative, bounded, or weighted share of terminal cells.
public enum Constraint: Sendable {
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

/// Splits an area into nonoverlapping regions in its original constraint order.
///
/// Minimum bounds are reserved first, followed by length, percentage, and ratio requests.
/// Equal-priority requests are clipped in source order when the area is too small.
/// Maximum-bounded regions then share excess cells equally until their caps are reached.
/// Weighted fills consume what remains, or minimum-bounded regions grow equally if no
/// positive fill exists. Otherwise unused cells trail the last region.
public struct Layout: Sendable {
    public var direction: Direction
    public var constraints: [Constraint]

    public init(_ direction: Direction, _ constraints: [Constraint]) {
        self.direction = direction
        self.constraints = constraints
    }

    /// Returns a region for every constraint, including zero-sized regions.
    public func split(_ area: Rect) -> [Rect] {
        // Rect fields are mutable. Clamp both dimensions before doing coordinate arithmetic.
        let width = representableLength(area.width, origin: area.x)
        let height = representableLength(area.height, origin: area.y)
        let total = direction == .vertical ? height : width
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

        var offset = 0
        return lengths.map { length in
            defer { offset += length }
            return direction == .vertical
                ? Rect(x: area.x, y: area.y + offset, width: width, height: length)
                : Rect(x: area.x + offset, y: area.y, width: length, height: height)
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
