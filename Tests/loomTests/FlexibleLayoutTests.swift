import Testing
import loom

@Test func flexibleLayoutPlacesUnusedSpaceAndKeepsLegacyAllocation() {
    let area = Rect(x: 4, y: 2, width: 15, height: 3)
    let constraints: [Constraint] = [.length(3), .length(3)]
    let expected: [(Flex, [Int])] = [
        (.start, [4, 7]), (.end, [13, 16]), (.center, [9, 12]),
        (.spaceBetween, [4, 16]), (.spaceAround, [7, 14]), (.spaceEvenly, [7, 13]),
    ]
    for (flex, origins) in expected {
        let regions = Layout(.horizontal, constraints, flex: flex).split(area)
        #expect(regions.map(\.x) == origins)
        #expect(regions.map(\.width) == [3, 3])
        #expect(regions.allSatisfy { $0.y == 2 && $0.height == 3 && $0.maxX <= area.maxX })
    }
    let filled = Layout(.horizontal, [.length(3), .fill(1)], flex: .end).split(area)
    #expect(filled.map(\.x) == [4, 7])
    #expect(filled.map(\.width) == [3, 12])
}

@Test func layoutInsetsAndGapsDefineFractionBasisAndClampSmallAreas() {
    let regions = Layout(
        .horizontal, [.percentage(50), .fill(1)],
        insets: LayoutInsets(left: 2, right: 3, top: 1, bottom: 1), spacing: 3
    ).split(Rect(x: 4, y: 2, width: 20, height: 5))
    #expect(regions == [Rect(x: 6, y: 3, width: 6, height: 3), Rect(x: 15, y: 3, width: 6, height: 3)])
    let tiny = Layout(
        .vertical, [.length(3), .length(3), .fill(1)],
        insets: LayoutInsets(top: Int.max, bottom: Int.max), spacing: Int.max
    ).split(Rect(width: 2, height: 1))
    #expect(tiny == Array(repeating: Rect(y: 1, width: 2, height: 0), count: 3))
    for flex in Flex.allCases {
        for width in 0...20 {
            let regions = Layout(.horizontal, [.length(2), .length(2), .length(2)], spacing: 2, flex: flex)
                .split(Rect(x: 3, width: width, height: 1))
            #expect(regions.allSatisfy { $0.x >= 3 && $0.maxX <= 3 + width })
            #expect(zip(regions, regions.dropFirst()).allSatisfy { $0.maxX <= $1.x })
        }
    }
}

@Test func flexSupportsSingleEmptyVerticalAndExtremeAreas() {
    #expect(Layout(.horizontal, [], flex: .spaceEvenly).split(Rect(width: 4, height: 2)).isEmpty)
    let single = Layout(.vertical, [.length(2)], flex: .spaceAround).split(Rect(x: 2, y: 4, width: 3, height: 7))
    #expect(single == [Rect(x: 2, y: 7, width: 3, height: 2)])
    let extreme = Layout(
        .horizontal, [.length(1), .length(1)], insets: LayoutInsets(left: Int.max), spacing: Int.max, flex: .center
    ).split(Rect(x: Int.max - 3, width: Int.max, height: 1))
    #expect(extreme == [Rect(x: Int.max, width: 0, height: 1), Rect(x: Int.max, width: 0, height: 1)])
}
