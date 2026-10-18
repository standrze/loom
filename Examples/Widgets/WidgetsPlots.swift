import loom

/// Deterministic plotting fixtures; the application owns routing and selected dates.
struct WidgetsPlots {
    func render(_ frame: inout Frame) {
        let sections = Layout(.vertical, [.length(1), .length(3), .fill(1), .fill(1)]).split(frame.area)
        paint(
            "loom plots | Sparkline / BarChart / Chart / Canvas / Calendar | p returns", in: sections[0], frame: &frame)
        let sparkPanel = Panel(title: "Sparkline: requests")
        frame.render(sparkPanel, in: sections[1])
        let spark = Sparkline([2, 4, 1, 8, 5, 3, 9, 4, 6, 2, 8, 10, 4, 7, 3, 9])
        frame.render(spark, in: sparkPanel.inner(sections[1]))
        let upper = Layout(.horizontal, [.fill(1), .fill(1)], spacing: 1).split(sections[2])
        let barPanel = Panel(title: "BarChart: workers")
        frame.render(barPanel, in: upper[0])
        renderBars(in: barPanel.inner(upper[0]), frame: &frame)
        let chartPanel = Panel(title: "Chart: throughput")
        frame.render(chartPanel, in: upper[1])
        let chart = Chart(
            datasets: [
                ChartDataset(
                    name: "alpha",
                    points: [
                        CanvasPoint(x: 0, y: 0), CanvasPoint(x: 1, y: 3), CanvasPoint(x: 2, y: 1),
                        CanvasPoint(x: 3, y: 4),
                    ],
                    style: Style(foreground: .indexed(6))),
                ChartDataset(
                    name: "beta",
                    points: [
                        CanvasPoint(x: 0, y: 2), CanvasPoint(x: 1, y: 1), CanvasPoint(x: 2, y: 4),
                        CanvasPoint(x: 3, y: 3),
                    ],
                    marker: .dot, style: Style(foreground: .indexed(3))),
            ],
            xAxis: ChartAxis(
                bounds: CanvasBounds(min: 0, max: 3),
                labels: [ChartAxisLabel(value: 0, text: "0"), ChartAxisLabel(value: 3, text: "3s")]),
            yAxis: ChartAxis(
                bounds: CanvasBounds(min: 0, max: 4),
                labels: [ChartAxisLabel(value: 0, text: "0"), ChartAxisLabel(value: 4, text: "4")]))
        frame.render(chart, in: chartPanel.inner(upper[1]))
        let lower = Layout(.horizontal, [.fill(1), .length(23)], spacing: 1).split(sections[3])
        let canvasPanel = Panel(title: "Canvas: layered shapes")
        frame.render(canvasPanel, in: lower[0])
        let canvas = Canvas(xBounds: CanvasBounds(min: -10, max: 10), yBounds: CanvasBounds(min: -5, max: 5)) {
            context in
            context.rectangle(
                origin: CanvasPoint(x: -8, y: -3), width: 16, height: 6, style: Style(foreground: .indexed(4)))
            context.circle(center: CanvasPoint(x: 0, y: 0), radius: 3, style: Style(foreground: .indexed(2)))
            context.line(
                from: CanvasPoint(x: -12, y: -4), to: CanvasPoint(x: 12, y: 4), style: Style(foreground: .indexed(6)))
            context.print("loom", at: CanvasPoint(x: -2, y: 1), style: Style(bold: true))
        }
        frame.render(canvas, in: canvasPanel.inner(lower[0]))
        let calendarPanel = Panel(title: "Monthly calendar")
        frame.render(calendarPanel, in: lower[1])
        if let month = try? CalendarMonth(year: 2026, month: 10),
            let release = try? CalendarDay(year: 2026, month: 10, day: 17)
        {
            var calendar = MonthlyCalendar(month: month)
            calendar.events[release] = StylePatch(foreground: .indexed(2), bold: true)
            calendar.selectedDay = release
            frame.render(calendar, in: calendarPanel.inner(lower[1]))
        }
    }

    private func renderBars(in area: Rect, frame: inout Frame) {
        var bars = BarChart(groups: [
            BarGroup(
                [
                    Bar(6, label: "web", style: StylePatch(foreground: .indexed(6))),
                    Bar(4, label: "api", style: StylePatch(foreground: .indexed(2))),
                ], label: "East"),
            BarGroup(
                [
                    Bar(3, label: "web", style: StylePatch(foreground: .indexed(6))),
                    Bar(8, label: "api", style: StylePatch(foreground: .indexed(2))),
                ], label: "West"),
        ])
        bars.barWidth = 5
        frame.render(bars, in: area)
    }

    private func paint(_ text: String, in area: Rect, frame: inout Frame) {
        frame.render(Paragraph(TextLayout(text, width: max(1, area.width))), in: area)
    }
}
