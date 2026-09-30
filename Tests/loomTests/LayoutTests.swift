import Foundation
import Testing

@testable import loom

@Test func layoutReservesComposerAndClampsSmallWindows() {
    let layout = Layout(.vertical, [.length(2), .fill(1), .length(5), .length(1)])
    let regions = layout.split(Rect(width: 80, height: 24))
    #expect(regions.map(\.height) == [2, 16, 5, 1])
    #expect(regions[2] == Rect(y: 18, width: 80, height: 5))
    let small = layout.split(Rect(width: 20, height: 4))
    #expect(
        small.allSatisfy {
            $0.height >= 0 && $0.maxY <= 4
        })
    let weighted = Layout(.horizontal, [.fill(1), .fill(2)]).split(Rect(width: 10, height: 5))
    #expect(weighted.map(\.width) == [3, 7])
    #expect(weighted.last?.maxX == 10)
}

@Test func mixedConstraintsUseFullAreaForRatiosAndLeaveFillTheRemainder() {
    let regions = Layout(
        .horizontal,
        [.length(10), .percentage(25), .ratio(1, 4), .fill(1)]
    ).split(Rect(x: 4, y: 2, width: 80, height: 6))
    #expect(regions.map(\.width) == [10, 20, 20, 30])
    #expect(regions.map(\.x) == [4, 14, 34, 54])
    #expect(regions.last?.maxX == 84)
}

@Test func boundsAndOvercommitNeverEscapeAvailableCells() {
    let layout = Layout(.vertical, [.min(8), .max(12), .fill(1)])
    #expect(layout.split(Rect(width: 20, height: 30)).map(\.height) == [8, 12, 10])
    #expect(layout.split(Rect(width: 20, height: 6)).map(\.height) == [6, 0, 0])
    let invalid = Layout(.horizontal, [.ratio(3, 0), .percentage(-10), .fill(1)])
    #expect(invalid.split(Rect(width: 17, height: 2)).map(\.width) == [0, 0, 17])
}

@Test func minimumsGrowBeyondTheirBoundsWhenNoFillIsPresent() {
    let regions = Layout(.horizontal, [.min(8), .length(5)]).split(Rect(width: 30, height: 2))
    #expect(regions.map(\.width) == [25, 5])
    let shared = Layout(.horizontal, [.min(3), .min(7)]).split(Rect(width: 20, height: 2))
    #expect(shared.map(\.width) == [8, 12])
    let filled = Layout(.horizontal, [.min(8), .fill(1)]).split(Rect(width: 30, height: 2))
    #expect(filled.map(\.width) == [8, 22])
}

@Test func maximumsYieldToRequestedSizesWithoutExceedingTheirCaps() {
    let regions = Layout(.horizontal, [.max(20), .length(45)]).split(Rect(width: 50, height: 2))
    #expect(regions.map(\.width) == [5, 45])
    let relative = Layout(.horizontal, [.max(40), .percentage(75)]).split(Rect(width: 40, height: 2))
    #expect(relative.map(\.width) == [10, 30])
    let capped = Layout(.horizontal, [.max(2), .max(100), .max(100)]).split(Rect(width: 11, height: 2))
    #expect(capped.map(\.width) == [2, 4, 5])
    let spare = Layout(.horizontal, [.max(4), .max(6)]).split(Rect(width: 30, height: 2))
    #expect(spare.map(\.width) == [4, 6])
    #expect(spare.last?.maxX == 10)
}

@Test func impossibleRequestsFollowPriorityAndThenSourceOrder() {
    let requests: [Constraint] = [.length(8), .min(7), .length(4), .percentage(100), .fill(1)]
    let regions = Layout(.horizontal, requests).split(Rect(width: 10, height: 2))
    #expect(regions.map(\.width) == [3, 7, 0, 0, 0])
    let bounds = Layout(.horizontal, [.min(8), .min(8), .max(20)]).split(Rect(width: 10, height: 2))
    #expect(bounds.map(\.width) == [8, 2, 0])
}

@Test func extremeFractionsAndWeightSumsRemainExactWithoutOverflow() {
    let ratio = Layout(.horizontal, [.ratio(Int.max - 1, Int.max), .fill(1)])
        .split(Rect(width: Int.max, height: 1))
    #expect(ratio.map(\.width) == [Int.max - 1, 1])
    let weights = Layout(.horizontal, [.fill(Int.max), .fill(Int.max), .fill(Int.max)])
        .split(Rect(width: Int.max, height: 1))
    #expect(weights.map(\.width) == [Int.max / 3, Int.max / 3, Int.max / 3 + 1])
    #expect(weights.last?.maxX == Int.max)
    let asymmetric = Layout(.horizontal, [.fill(Int.max), .fill(1), .fill(Int.max), .fill(Int.max)])
        .split(Rect(width: 31, height: 1))
    #expect(asymmetric.map(\.width) == [10, 0, 10, 11])
    let percent = Layout(.horizontal, [.percentage(50), .fill(1)])
        .split(Rect(width: Int.max, height: 1))
    #expect(percent.map(\.width) == [Int.max / 2, Int.max / 2 + 1])
}

@Test func invalidAndUnrepresentableAreasClampToSafeRegions() {
    let negative = Layout(.horizontal, [.min(-2), .max(-4), .length(-8), .fill(0)])
        .split(Rect(width: 20, height: 1))
    #expect(negative.map(\.width) == [20, 0, 0, 0])
    let invalid = Layout(.horizontal, [.ratio(Int.max, Int.min), .percentage(Int.min), .fill(Int.min)])
        .split(Rect(width: 20, height: 1))
    #expect(invalid.map(\.width) == [0, 0, 0])
    let outside = Layout(.horizontal, [.fill(1), .fill(1)])
        .split(Rect(x: Int.max - 5, y: Int.max, width: Int.max, height: 10))
    #expect(outside.map(\.width) == [2, 3])
    #expect(outside.map(\.height) == [0, 0])
    #expect(outside.last?.maxX == Int.max)
    var mutated = Rect(width: 10, height: 4)
    mutated.width = -1
    #expect(Layout(.horizontal, [.fill(1)]).split(mutated) == [Rect(width: 0, height: 4)])
    #expect(Layout(.vertical, []).split(Rect(width: 1, height: 1)).isEmpty)
}

@Test func boundedLayoutsStayOrderedWithinEverySmallWindow() {
    let constraints: [Constraint] = [.max(8), .min(3), .length(2), .percentage(20), .ratio(1, 4), .fill(2)]
    for width in 0...60 {
        let regions = Layout(.horizontal, constraints).split(Rect(x: 4, y: 2, width: width, height: 3))
        #expect(regions.count == constraints.count)
        #expect(regions[0].width <= 8)
        #expect(regions[1].width >= min(width, 3))
        #expect(regions.allSatisfy { $0.width >= 0 && $0.x >= 4 && $0.maxX <= 4 + width })
        #expect(zip(regions, regions.dropFirst()).allSatisfy { $0.maxX == $1.x })
        #expect(regions.last?.maxX == 4 + width)
    }
}
