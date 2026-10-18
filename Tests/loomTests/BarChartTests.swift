import Testing

@testable import loom

@Test func barChartVerticalFractionalAndGroupedLayout() {
    var chart = BarChart(groups: [BarGroup([Bar(1), Bar(0.5)]), BarGroup([Bar(0.0625)])], maximum: 1)
    chart.showsValues = false
    chart.barGap = 1
    chart.groupGap = 2
    var buffer = Buffer(width: 6, height: 2)
    chart.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "█     \n█ █  ▁")
}

@Test func barChartVerticalLabelsAndValuesInheritPatches() {
    let bar = Bar(
        1, label: [TextSpan("界", link: "https://example.com")], textValue: "OK",
        style: StylePatch(bold: true), valueStyle: StylePatch(italic: true))
    var chart = BarChart(groups: [BarGroup([bar], label: "G", style: StylePatch(foreground: .indexed(4)))])
    chart.barWidth = 2
    chart.valueStyle = Style(background: .indexed(2))
    var buffer = Buffer(width: 3, height: 4)
    chart.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "██ \nOK \n界 \nG  ")
    #expect(buffer[0, 0].style.bold)
    #expect(buffer[0, 0].style.foreground == .indexed(4))
    #expect(buffer[0, 1].style.italic)
    #expect(buffer[0, 1].style.background == .indexed(2))
    #expect(buffer[0, 2].link == "https://example.com")
    #expect(buffer[1, 2].width == 0)
}

@Test func barChartHorizontalLabelsFractionsAndThickness() {
    var chart = BarChart(bars: [Bar(1, label: "A"), Bar(0.5625, label: "B")], maximum: 1)
    chart.direction = .horizontal
    chart.barWidth = 2
    chart.barGap = 1
    chart.showsValues = false
    var buffer = Buffer(width: 6, height: 5)
    chart.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "A ████\n  ████\n      \nB ██▎ \n  ██▎ ")
}

@Test func barChartNonfiniteDataEmptyGroupsAndTinyAreasAreDeterministic() {
    var chart = BarChart(groups: [BarGroup([], label: "unused"), BarGroup([Bar(.infinity), Bar(-1), Bar(.nan)])])
    chart.showsValues = false
    chart.barGap = 0
    chart.groupGap = Int.max
    chart.barWidth = Int.max
    var buffer = Buffer(width: 3, height: 1)
    chart.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText == "   ")
    chart = BarChart(bars: [Bar(1, label: "界")])
    chart.direction = .horizontal
    chart.render(in: Rect(width: 1, height: 1), buffer: &buffer)
    #expect(buffer[0, 0].symbol == " ")
    chart.render(in: Rect(x: Int.max, y: Int.max, width: 4, height: 4), buffer: &buffer)
    chart.render(in: Rect(width: 0, height: 0), buffer: &buffer)
}

@Test func barChartNonzeroOriginAndNestedClipPreserveOutsideCells() {
    var chart = BarChart(bars: [Bar(1), Bar(0.5)], maximum: 1)
    chart.barWidth = 2
    chart.barGap = 0
    chart.showsValues = false
    var buffer = Buffer(width: 7, height: 4)
    buffer.fill(buffer.area, symbol: ".")
    buffer.withClip(Rect(x: 2, y: 1, width: 2, height: 2)) { target in
        chart.render(in: Rect(x: 1, y: 1, width: 4, height: 2), buffer: &target)
    }
    #expect(buffer.plainText == ".......\n..█ ...\n..██...\n.......")
}

@Test func barChartInheritsBaseGroupAndValueAppearance() {
    for direction in [Direction.vertical, .horizontal] {
        var chart = BarChart(groups: [
            BarGroup(
                [
                    Bar(
                        1, label: "A", textValue: "V", style: StylePatch(underlined: true),
                        labelStyle: StylePatch(italic: true), valueStyle: StylePatch(dim: true))
                ], label: "G", style: StylePatch(bold: true), labelStyle: StylePatch(strikethrough: true),
                valueStyle: StylePatch(background: .indexed(3)))
        ])
        chart.direction = direction
        chart.barWidth = 3
        chart.style = Style(foreground: .indexed(2))
        var buffer = Buffer(width: 8, height: 5)
        chart.render(in: buffer.area, buffer: &buffer)
        let value = direction == .vertical ? buffer[0, 2] : buffer[2, 1]
        #expect(value.symbol == "V")
        #expect(value.style.foreground == .indexed(2))
        #expect(value.style.background == .indexed(3))
        #expect(value.style.bold)
        #expect(value.style.underlined)
        #expect(value.style.dim)
        let label = direction == .vertical ? buffer[0, 3] : buffer[0, 1]
        #expect(label.symbol == "A")
        #expect(label.style.foreground == .indexed(2))
        #expect(label.style.strikethrough)
        #expect(label.style.italic)
    }
}
