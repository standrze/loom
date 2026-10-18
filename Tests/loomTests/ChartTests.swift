import Testing

@testable import loom

@Test func chartAutoscaleUsesFinitePairsAndExpandsConstants() {
    let chart = Chart(datasets: [
        ChartDataset(points: [
            CanvasPoint(x: -4, y: 2), CanvasPoint(x: -4, y: 2),
            CanvasPoint(x: .nan, y: 100), CanvasPoint(x: 200, y: .infinity),
        ])
    ])
    #expect(chart.resolvedXBounds.min < -4)
    #expect(chart.resolvedXBounds.max > -4)
    #expect(chart.resolvedYBounds.min < 2)
    #expect(chart.resolvedYBounds.max > 2)
    let empty = Chart(datasets: [])
    #expect(empty.resolvedXBounds.min == 0)
    #expect(empty.resolvedXBounds.max == 1)
}

@Test func chartExplicitBoundsAndNegativeCoordinatesMapToPlotCorners() {
    var chart = Chart(
        datasets: [
            ChartDataset(
                points: [CanvasPoint(x: -5, y: -3), CanvasPoint(x: 5, y: 3)],
                graphType: .scatter, marker: .block, style: Style(foreground: .indexed(2)))
        ],
        xAxis: ChartAxis(bounds: CanvasBounds(min: -5, max: 5)),
        yAxis: ChartAxis(bounds: CanvasBounds(min: -3, max: 3)))
    chart.legendPosition = .hidden
    let area = Rect(x: 2, y: 1, width: 12, height: 6)
    let plot = chart.plotArea(in: area)
    var buffer = Buffer(width: 16, height: 9)
    chart.render(in: area, buffer: &buffer)
    #expect(buffer[plot.x, plot.maxY - 1].style.foreground == .indexed(2))
    #expect(buffer[plot.maxX - 1, plot.y].style.foreground == .indexed(2))
    #expect(buffer[1, 1].symbol == " ")
}

@Test func chartCustomLabelsAndTitlesReserveWideTerminalCells() {
    let chart = Chart(
        datasets: [],
        xAxis: ChartAxis(
            bounds: CanvasBounds(min: 0, max: 1), title: "time",
            labels: [
                ChartAxisLabel(value: 0, text: "始"), ChartAxisLabel(value: 1, text: "終"),
            ]),
        yAxis: ChartAxis(
            bounds: CanvasBounds(min: 0, max: 1), title: "value",
            labels: [
                ChartAxisLabel(value: 0, text: "界", style: Style(bold: true)),
                ChartAxisLabel(value: 1, text: "10"),
            ]))
    let area = Rect(width: 18, height: 9)
    let plot = chart.plotArea(in: area)
    #expect(plot == Rect(x: 4, y: 1, width: 14, height: 5))
    var buffer = Buffer(width: 18, height: 9)
    chart.render(in: area, buffer: &buffer)
    #expect(buffer[0, 5].symbol == "界")
    #expect(buffer[1, 5].width == 0)
    #expect(buffer[0, 5].style.bold)
    #expect(buffer[plot.x, plot.maxY + 1].symbol == "始")
    #expect(buffer[plot.maxX - 2, plot.maxY + 1].symbol == "終")
}

@Test func chartLegendsFitAndRespectPositionAndTinyPlots() {
    let dataset = ChartDataset(name: "界", points: [], style: Style(foreground: .indexed(1)))
    var chart = Chart(datasets: [dataset])
    let area = Rect(width: 12, height: 6)
    let plot = chart.plotArea(in: area)
    var buffer = Buffer(width: 12, height: 6)
    chart.render(in: area, buffer: &buffer)
    #expect(buffer[plot.maxX - 2, plot.y].symbol == "界")
    #expect(buffer[plot.maxX - 4, plot.y].style.foreground == .indexed(1))
    chart.legendPosition = .bottomLeft
    buffer.reset()
    chart.render(in: area, buffer: &buffer)
    #expect(buffer[plot.x + 2, plot.maxY - 1].symbol == "界")
    for width in 0...4 {
        for height in 0...2 {
            var tiny = Buffer(width: width, height: height)
            chart.render(in: Rect(width: width, height: height), buffer: &tiny)
            #expect(!tiny.plainText.contains("界"))
        }
    }
}

@Test func chartInvalidRangesAndNaNBreaksDoNotDrawSpuriousLines() {
    let dataset = ChartDataset(
        points: [
            CanvasPoint(x: 0, y: 0), CanvasPoint(x: .nan, y: .nan),
            CanvasPoint(x: 1, y: 1),
        ], marker: .block, style: Style(foreground: .indexed(4)))
    var chart = Chart(
        datasets: [dataset], xAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)),
        yAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)))
    let area = Rect(width: 10, height: 6)
    var buffer = Buffer(width: 10, height: 6)
    chart.render(in: area, buffer: &buffer)
    let plot = chart.plotArea(in: area)
    #expect(buffer[plot.x + plot.width / 2, plot.y + plot.height / 2].style.foreground != .indexed(4))
    for bounds in [CanvasBounds(min: 1, max: 1), CanvasBounds(min: 2, max: -2), CanvasBounds(min: -.infinity, max: 1)] {
        chart.xAxis.bounds = bounds
        buffer.reset()
        chart.render(in: area, buffer: &buffer)
        #expect(!buffer.plainText.contains("█"))
    }
}

@Test func chartNestedClipAndBarsUseClampedBaseline() {
    let chart = Chart(
        datasets: [
            ChartDataset(
                points: [CanvasPoint(x: 0.5, y: 8)], graphType: .bar,
                marker: .block, style: Style(foreground: .indexed(3)))
        ],
        xAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)),
        yAxis: ChartAxis(bounds: CanvasBounds(min: 5, max: 10)))
    let area = Rect(width: 12, height: 7)
    let clip = Rect(x: 5, y: 2, width: 3, height: 3)
    var buffer = Buffer(width: 12, height: 7)
    buffer.withClip(clip) { chart.render(in: area, buffer: &$0) }
    for y in 0..<buffer.height {
        for x in 0..<buffer.width where !clip.contains(Point(x: x, y: y)) {
            #expect(buffer[x, y].symbol == " ")
        }
    }
    #expect(buffer.plainText.contains("█"))
}

@Test func chartDatasetsRetainSeparateStylesAndClipCrossingSegments() {
    var chart = Chart(
        datasets: [
            ChartDataset(
                points: [CanvasPoint(x: -10, y: 0.5), CanvasPoint(x: 10, y: 0.5)],
                marker: .block, style: Style(foreground: .indexed(1))),
            ChartDataset(
                points: [CanvasPoint(x: 0, y: 0)], graphType: .scatter,
                marker: .dot, style: Style(foreground: .indexed(2))),
        ], xAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)),
        yAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)))
    chart.legendPosition = .hidden
    let area = Rect(width: 10, height: 8)
    let plot = chart.plotArea(in: area)
    var buffer = Buffer(width: 10, height: 8)
    chart.render(in: area, buffer: &buffer)
    #expect(buffer[plot.x, plot.maxY - 1].style.foreground == .indexed(2))
    #expect(buffer[plot.maxX - 1, plot.y + plot.height / 2].style.foreground == .indexed(1))
    #expect(buffer[plot.x - 1, plot.y + plot.height / 2].symbol == "│")
}

@Test func chartExtremeConstantBoundsRemainFiniteAndIncreasing() {
    for value in [-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude] {
        let chart = Chart(datasets: [ChartDataset(points: [CanvasPoint(x: value, y: value)])])
        #expect(chart.resolvedXBounds.min.isFinite)
        #expect(chart.resolvedXBounds.max.isFinite)
        #expect(chart.resolvedXBounds.min < chart.resolvedXBounds.max)
    }
    let chart = Chart(
        datasets: [],
        xAxis: ChartAxis(
            bounds: CanvasBounds(min: -1e308, max: 1e308),
            labels: [
                ChartAxisLabel(value: 0, text: "0")
            ]))
    var buffer = Buffer(width: 8, height: 4)
    chart.render(in: buffer.area, buffer: &buffer)
    #expect(buffer.plainText.contains("0"))
}

@Test func chartExtremeAreaTickMappingStaysRepresentable() {
    for marker in [CanvasMarker.braille, .dot, .block, .halfBlock] {
        let chart = Chart(
            datasets: [ChartDataset(points: [CanvasPoint(x: 0, y: 0), CanvasPoint(x: 1, y: 1)], marker: marker)],
            xAxis: ChartAxis(
                bounds: CanvasBounds(min: 0, max: 1),
                labels: [
                    ChartAxisLabel(value: 0, text: "left"), ChartAxisLabel(value: 1, text: "right"),
                ]),
            yAxis: ChartAxis(
                bounds: CanvasBounds(min: 0, max: 1),
                labels: [
                    ChartAxisLabel(value: 0, text: "bottom"), ChartAxisLabel(value: 1, text: "top"),
                ]))
        for area in [
            Rect(width: Int.max, height: Int.max), Rect(x: Int.min, y: Int.min, width: Int.max, height: Int.max),
            Rect(x: Int.max - 2, y: Int.max - 2, width: Int.max, height: Int.max),
        ] {
            var buffer = Buffer(width: 4, height: 3)
            chart.render(in: area, buffer: &buffer)
            let plot = chart.plotArea(in: area)
            #expect(plot.width >= 0 && plot.height >= 0)
            #expect(plot.maxX >= plot.x && plot.maxY >= plot.y)
        }
    }
}

@Test func chartDatasetsInheritChartAppearance() {
    let chart = Chart(
        datasets: [
            ChartDataset(
                points: [CanvasPoint(x: 0, y: 0)], graphType: .scatter, marker: .block,
                style: Style(foreground: .indexed(2)))
        ],
        xAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)),
        yAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)),
        style: Style(background: .indexed(4), bold: true))
    var buffer = Buffer(width: 5, height: 4)
    let plot = chart.plotArea(in: buffer.area)
    chart.render(in: buffer.area, buffer: &buffer)
    let cell = buffer[plot.x, plot.maxY - 1]
    #expect(cell.style.foreground == .indexed(2))
    #expect(cell.style.background == .indexed(4))
    #expect(cell.style.bold)
}

@Test func chartTickLabelsKeepFirstSourceLabelWhenCellsCollide() {
    var chart = Chart(
        datasets: [],
        xAxis: ChartAxis(
            bounds: CanvasBounds(min: 0, max: 1),
            labels: [
                ChartAxisLabel(value: 0.1, text: "ABCD"),
                ChartAxisLabel(value: 0.2, text: "wxyz"),
                ChartAxisLabel(value: 0.9, text: "R"),
            ]),
        yAxis: ChartAxis(
            bounds: CanvasBounds(min: 0, max: 1),
            labels: [
                ChartAxisLabel(value: 0.4, text: "FIRST"),
                ChartAxisLabel(value: 0.41, text: "last"),
            ]))
    chart.legendPosition = .hidden
    var buffer = Buffer(width: 20, height: 6)
    chart.render(in: buffer.area, buffer: &buffer)
    let plot = chart.plotArea(in: buffer.area)
    #expect(buffer.plainText.contains("ABCD"))
    #expect(buffer.plainText.contains("FIRST"))
    #expect(buffer.plainText.contains("R"))
    #expect(!buffer.plainText.contains("wxyz"))
    #expect(!buffer.plainText.contains("last"))
    // Tick marks remain useful even when their text is omitted.
    #expect(buffer[plot.x + 1, plot.maxY].symbol == "┬")
    #expect(buffer[plot.x + 2, plot.maxY].symbol == "┬")
}

@Test func chartAxesLabelsAndLegendInheritAppearanceUnlessExplicit() {
    let appearance = Style(foreground: .indexed(2), background: .indexed(4), bold: true)
    var chart = Chart(
        datasets: [ChartDataset(name: "series", points: [])],
        xAxis: ChartAxis(title: "X", labels: [ChartAxisLabel(value: 0.5, text: "x")]),
        yAxis: ChartAxis(title: "Y", labels: [ChartAxisLabel(value: 0.5, text: "y")]),
        style: appearance)
    var buffer = Buffer(width: 24, height: 10)
    chart.render(in: buffer.area, buffer: &buffer)
    for y in 0..<buffer.height {
        for x in 0..<buffer.width {
            #expect(buffer[x, y].style == appearance)
        }
    }
    chart.xAxis.style = Style()
    chart.yAxis.labelStyle = Style(italic: true)
    chart.legendStyle = Style(foreground: .indexed(3))
    buffer.reset()
    chart.render(in: buffer.area, buffer: &buffer)
    let plot = chart.plotArea(in: buffer.area)
    #expect(buffer[plot.x, plot.maxY].style == Style())
    #expect(buffer[0, 0].style == Style(italic: true))
    #expect(buffer[plot.maxX - 6, plot.y].style == Style(foreground: .indexed(3)))
}

@Test func chartLegendAllPerimeterPositionsUseUnicodeCellWidth() {
    let positions: [(ChartLegendPosition, Int, Int)] = [
        (.topLeft, 1, 0), (.top, 4, 0), (.topRight, 8, 0),
        (.left, 1, 3), (.right, 8, 3),
        (.bottomLeft, 1, 6), (.bottom, 4, 6), (.bottomRight, 8, 6),
    ]
    for (position, x, y) in positions {
        var chart = Chart(datasets: [ChartDataset(name: "界", points: [])])
        chart.legendPosition = position
        var buffer = Buffer(width: 12, height: 8)
        chart.render(in: buffer.area, buffer: &buffer)
        #expect(buffer[x, y].symbol == "•")
        #expect(buffer[x + 2, y].symbol == "界")
        #expect(buffer[x + 3, y].width == 0)
    }
}

@Test func chartLegendLimitsIncludeExactBoundaryAndHideInvalidRatios() {
    var chart = Chart(datasets: [ChartDataset(name: "界", points: [])])
    chart.legendWidthLimit = .cells(4)
    chart.legendHeightLimit = .ratio(1.0 / 7)
    var buffer = Buffer(width: 12, height: 8)
    chart.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[8, 0].symbol == "•")
    for limit in [ChartLegendLimit.cells(3), .ratio(.nan), .ratio(-1), .ratio(0)] {
        chart.legendWidthLimit = limit
        buffer.reset()
        chart.render(in: buffer.area, buffer: &buffer)
        #expect(buffer[8, 0].symbol == " ")
    }
}

@Test func chartFilledLineUsesExplicitBaselineAndSeparateFillStyle() {
    let line = Style(foreground: .indexed(1))
    let fill = Style(foreground: .indexed(2))
    var chart = Chart(
        datasets: [
            ChartDataset(
                points: [CanvasPoint(x: 0, y: 1), CanvasPoint(x: 1, y: 1)],
                graphType: .filledLine, marker: .block, style: line, baseline: 0.5, fillStyle: fill)
        ],
        xAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)),
        yAxis: ChartAxis(bounds: CanvasBounds(min: 0, max: 1)))
    chart.legendPosition = .hidden
    var buffer = Buffer(width: 4, height: 4)
    chart.render(in: buffer.area, buffer: &buffer)
    #expect(buffer[2, 0].style == line)
    #expect(buffer[2, 1].style == fill)
    #expect(buffer[2, 2].symbol == " ")
}
