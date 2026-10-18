import Testing

@testable import loom

@Test func sparklineScalesAcrossRowsAndEighths() {
    var buffer = Buffer(width: 5, height: 2)
    Sparkline([0, 0.0625, 0.5, 0.5625, 1], maximum: 1).render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "   ▁█\n ▁███")
    var automatic = Buffer(width: 3, height: 1)
    Sparkline([1, 2, 4]).render(in: automatic.area, buffer: &automatic)
    #expect(automatic.plainText == "▂▄█")
}

@Test func sparklineMissingAndCustomSymbolsKeepPerBarAppearance() {
    let symbols = SparklineSymbols(["0", "1", "2", "3", "4", "5", "6", "7", "8"])!
    #expect(SparklineSymbols([" "]) == nil)
    #expect(SparklineSymbols(Array(repeating: "界", count: 9)) == nil)
    #expect(SparklineSymbols(Array(repeating: "\u{1b}", count: 9)) == nil)
    var sparkline = Sparkline(
        bars: [
            SparklineBar(1, patch: StylePatch(bold: true)), SparklineBar(nil), SparklineBar(.infinity),
            SparklineBar(-1), SparklineBar(.nan),
        ], maximum: 1, style: Style(foreground: .indexed(2)))
    sparkline.symbols = symbols
    sparkline.missingSymbol = "?"
    sparkline.missingStyle = StylePatch(italic: true)
    var buffer = Buffer(width: 5, height: 1)
    sparkline.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "8??0?")
    #expect(buffer[0, 0].style.bold)
    #expect(buffer[0, 0].style.foreground == .indexed(2))
    #expect(buffer[1, 0].style.italic)
    sparkline.direction = .rightToLeft
    sparkline.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "?0??8")
}

@Test func sparklineHandlesInvalidMaximaAndNestedClipping() {
    for maximum in [0.0, -1, .nan, .infinity] {
        var buffer = Buffer(width: 2, height: 1)
        Sparkline([1, 2], maximum: maximum).render(in: buffer.area, buffer: &buffer)
        #expect(buffer.plainText == "  ")
    }
    var buffer = Buffer(width: 6, height: 3)
    buffer.fill(buffer.area, symbol: ".")
    buffer.withClip(Rect(x: 2, y: 1, width: 2, height: 1)) { target in
        Sparkline([1, 0.5, 0.25], maximum: 1)
            .render(in: Rect(x: 1, y: 1, width: 3, height: 1), buffer: &target)
    }
    #expect(buffer.plainText == "......\n..▄▂..\n......")
    Sparkline([]).render(in: Rect(width: 0, height: 0), buffer: &buffer)
    Sparkline(samples: [nil]).render(in: Rect(x: Int.max, y: Int.max, width: 2, height: 2), buffer: &buffer)
}

@Test func sparklineExtremeFiniteScaleAndOffscreenSamplesStayFinite() {
    let maximum = Double.greatestFiniteMagnitude
    var buffer = Buffer(width: 2, height: 1)
    Sparkline([maximum / 2, maximum, maximum / 4]).render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "▄█")
    var reversed = Sparkline([maximum / 2, maximum], maximum: maximum)
    reversed.direction = .rightToLeft
    reversed.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "█▄")
}
