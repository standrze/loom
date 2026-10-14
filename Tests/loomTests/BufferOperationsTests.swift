import Testing

@testable import loom

@Test func bufferOperationsPreserveWholeGlyphsAndMetadata() {
    var source = Buffer(width: 6, height: 1)
    source.put("界", width: 2, at: Point(x: 1, y: 0), style: Style(bold: true), link: "https://example.com")
    source.apply(StylePatch(italic: true), to: Rect(x: 2, width: 1, height: 1))
    #expect(!source[1, 0].style.italic)
    source.apply(StylePatch(italic: true), to: source.area)
    #expect(source[2, 0].style.italic)
    var destination = Buffer(width: 6, height: 1)
    destination.copy(from: source, region: Rect(x: 1, width: 2, height: 1), to: Point(x: 3, y: 0))
    #expect(destination[3, 0] == source[1, 0])
    #expect(destination[4, 0] == source[2, 0])
    destination.withClip(Rect(x: 4, width: 1, height: 1)) { $0.clear($0.area) }
    #expect(destination[3, 0].symbol == "界")
    #expect(destination.resized(width: 4, height: 1)[3, 0].symbol == " ")
    destination.copy(from: destination, region: Rect(x: 3, width: 2, height: 1), to: Point(x: 0, y: 0))
    #expect(destination[0, 0].symbol == "界")
    #expect(destination.differences(from: Buffer(width: 6, height: 1)).count == 4)
    destination.fill(destination.area, symbol: "\u{1b}")
    #expect(destination[0, 0].symbol == "界")
}

@Test func layoutCacheKeysAndCapacityAndExplicitOverlap() {
    var cache = LayoutCache(capacity: 2)
    let area = Rect(width: 10, height: 1)
    let legacy = Layout(.horizontal, [.length(4), .length(4)], spacing: -2)
    #expect(legacy.split(area).map(\.x) == [0, 4])
    var layout = Layout(.horizontal, [.length(4), .length(4)], spacing: .overlap(3))
    #expect(layout.split(area, cache: &cache).map(\.x) == [0, 1])
    layout.flex = .end
    #expect(layout.split(area, cache: &cache).map(\.x) == [5, 6])
    _ = layout.split(Rect(x: 1, width: 10, height: 1), cache: &cache)
    #expect(cache.count == 2)
    cache.removeAll()
    #expect(cache.count == 0)
    let zero = Layout(.horizontal, [.length(0), .length(4), .length(4)], spacing: .overlap(Int.max))
    #expect(zero.split(area).map(\.x) == [0, 0, 0])
}

@Test func bufferRegionsClampExtremeAndMutatedCoordinates() {
    var buffer = Buffer(width: 3, height: 2)
    buffer.fill(Rect(x: Int.max, y: Int.max, width: Int.max, height: Int.max), symbol: "X")
    #expect(buffer.plainText == "   \n   ")
    buffer.fill(Rect(x: Int.min, y: Int.min, width: 1, height: 1), symbol: "X")
    #expect(buffer.plainText == "   \n   ")
    buffer.fill(Rect(x: 1, y: 1, width: Int.max, height: Int.max), symbol: "X")
    #expect(buffer.plainText == "   \n XX")
    var negative = buffer.area
    negative.width = Int.min
    negative.height = Int.min
    buffer.clear(negative)
    #expect(buffer.plainText == "   \n XX")
    var copied = Buffer(width: 3, height: 2)
    copied.copy(from: buffer, region: Rect(x: 1, y: 1, width: Int.max, height: Int.max), to: Point(x: 0, y: 0))
    #expect(copied.plainText == "XX \n   ")
    copied.copy(from: buffer, region: buffer.area, to: Point(x: Int.max, y: Int.max))
    #expect(copied.plainText == "XX \n   ")
}

@Test func explicitOverlapAndFlexStayRepresentableAtExtremeWidth() {
    for flex in Flex.allCases {
        let layout = Layout(
            .horizontal, [.fill(Int.max), .fill(Int.max), .fill(Int.max)],
            spacing: .overlap(Int.max), flex: flex)
        let regions = layout.split(Rect(width: Int.max, height: 1))
        #expect(regions.count == 3)
        #expect(regions.allSatisfy { $0.x >= 0 && $0.maxX <= Int.max })
        #expect(zip(regions, regions.dropFirst()).allSatisfy { $0.x <= $1.x })
    }
}
