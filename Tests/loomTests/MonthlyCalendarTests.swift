import Testing
import loom

@Test func calendarDatesValidateGregorianLeapYearsAndBoundaries() throws {
    #expect(try CalendarMonth(year: 2000, month: 2).dayCount == 29)
    #expect(try CalendarMonth(year: 1900, month: 2).dayCount == 28)
    #expect(try CalendarMonth(year: 2024, month: 2).dayCount == 29)
    #expect(throws: CalendarDateError.invalidDay(29)) { try CalendarDay(year: 2023, month: 2, day: 29) }
    #expect(throws: CalendarDateError.invalidMonth(13)) { try CalendarMonth(year: 2026, month: 13) }
    #expect(throws: CalendarDateError.invalidYear(0)) { try CalendarMonth(year: 0, month: 1) }
    let minimum = try CalendarDay(year: 1, month: 1, day: 1)
    let maximum = try CalendarDay(year: 9999, month: 12, day: 31)
    #expect(minimum.weekday == .monday)
    #expect(minimum.adding(days: -1) == nil)
    #expect(maximum.adding(days: 1) == nil)
    #expect(maximum.adding(days: Int.max) == nil)
    #expect(minimum.adding(days: Int.min) == nil)
    #expect(minimum.adding(days: 3_652_058) == maximum)
    #expect(maximum.adding(days: -3_652_058) == minimum)
    #expect(
        try CalendarDay(year: 2024, month: 2, day: 28).adding(days: 1) == CalendarDay(year: 2024, month: 2, day: 29))
    #expect(
        try CalendarDay(year: 2023, month: 12, day: 31).adding(days: 1) == CalendarDay(year: 2024, month: 1, day: 1))
}

@Test func monthlyGridUsesSameGeometryForRenderingAndHits() throws {
    var calendar = MonthlyCalendar(month: try CalendarMonth(year: 2026, month: 10))
    let area = Rect(x: 2, y: 1, width: 21, height: 8)
    var buffer = Buffer(width: 25, height: 10)
    calendar.render(in: area, buffer: &buffer)
    #expect(calendar.requiredHeight == 7)
    #expect(buffer[12, 3].symbol == "1")
    #expect(try calendar.date(at: Point(x: 12, y: 3), in: area) == CalendarDay(year: 2026, month: 10, day: 1))
    #expect(calendar.date(at: Point(x: 13, y: 3), in: area) == nil)
    #expect(calendar.date(at: Point(x: 2, y: 1), in: area) == nil)
    #expect(calendar.date(at: Point(x: 2, y: 3), in: area) == nil)
    calendar.firstWeekday = .sunday
    #expect(try calendar.date(at: Point(x: 15, y: 3), in: area) == CalendarDay(year: 2026, month: 10, day: 1))
    calendar.showsSurroundingDays = true
    #expect(try calendar.date(at: Point(x: 2, y: 3), in: area) == CalendarDay(year: 2026, month: 9, day: 27))
}

@Test func calendarEventTodayAndSelectionPatchesComposeInOrder() throws {
    let date = try CalendarDay(year: 2026, month: 10, day: 3)
    var calendar = MonthlyCalendar(month: try CalendarMonth(year: 2026, month: 10))
    calendar.style = Style(foreground: .indexed(7), background: .indexed(1))
    calendar.weekendPatch = StylePatch(dim: true)
    calendar.events[date] = StylePatch(foreground: .indexed(2), bold: true)
    calendar.today = date
    calendar.selectedDay = date
    calendar.selectionPatch = StylePatch(bold: false, reversed: true)
    var buffer = Buffer(width: 21, height: 8)
    calendar.render(in: buffer.area, buffer: &buffer)
    let actual = buffer[15, 2].style
    #expect(actual.foreground == .indexed(2) && actual.background == .indexed(1))
    #expect(actual.dim && actual.underlined && actual.reversed && !actual.bold)
}

@Test func monthlyCalendarHandlesFourAndSixWeekMonthsAndSurroundingLimits() throws {
    let four = MonthlyCalendar(month: try CalendarMonth(year: 2021, month: 2))
    #expect(four.requiredHeight == 6)
    var six = MonthlyCalendar(month: try CalendarMonth(year: 2020, month: 8))
    #expect(six.requiredHeight == 8)
    six.showsMonthHeader = false
    six.showsWeekdays = false
    #expect(six.requiredHeight == 6)
    var minimum = MonthlyCalendar(month: try CalendarMonth(year: 1, month: 1))
    minimum.firstWeekday = .sunday
    minimum.showsSurroundingDays = true
    #expect(minimum.date(at: Point(x: 0, y: 2), in: Rect(width: 21, height: 8)) == nil)
    var maximum = MonthlyCalendar(month: try CalendarMonth(year: 9999, month: 12))
    maximum.showsSurroundingDays = true
    maximum.fixedWeekCount = true
    #expect(maximum.date(at: Point(x: 19, y: 7), in: Rect(width: 21, height: 8)) == nil)
}

@Test func calendarClipsLocalizedWideLabelsAndNestedRegions() throws {
    var calendar = MonthlyCalendar(month: try CalendarMonth(year: 2026, month: 10))
    calendar.weekdayLabels = Array(repeating: "界", count: 7)
    calendar.monthNames = []
    for width in 0...23 {
        for height in 0...9 {
            var buffer = Buffer(width: 25, height: 12)
            buffer.fill(buffer.area, symbol: ".")
            let area = Rect(x: 1, y: 1, width: width, height: height)
            buffer.withClip(Rect(x: 2, y: 2, width: 20, height: 8)) { calendar.render(in: area, buffer: &$0) }
            #expect(buffer[0, 0].symbol == ".")
            #expect(buffer[24, 11].symbol == ".")
            for y in 0..<buffer.height {
                for x in 0..<buffer.width where buffer[x, y].width == 0 {
                    #expect(x > 0 && buffer[x - 1, y].width == 2)
                }
            }
        }
    }
}

@Test func monthlyCalendarHitDatesRoundTripAcrossGregorianCenturyMonths() throws {
    for year in [1, 1900, 2000, 2024, 2026, 9999] {
        for month in 1...12 {
            let period = try CalendarMonth(year: year, month: month)
            for first in CalendarWeekday.allCases {
                var calendar = MonthlyCalendar(month: period)
                calendar.firstWeekday = first
                let area = Rect(width: 21, height: 8)
                var found: Set<CalendarDay> = []
                for row in 2..<calendar.requiredHeight {
                    for column in 0..<7 {
                        if let date = calendar.date(at: Point(x: column * 3, y: row), in: area) { found.insert(date) }
                    }
                }
                #expect(found.count == period.dayCount)
                #expect(found.allSatisfy { $0.year == year && $0.month == month })
            }
        }
    }
}

@Test func monthlyCalendarExtremeAndMutatedAreasRemainBounded() throws {
    let calendar = MonthlyCalendar(month: try CalendarMonth(year: 2026, month: 10))
    var negative = Rect(width: 21, height: 8)
    negative.width = Int.min
    negative.height = Int.min
    for area in [
        Rect(x: Int.max - 1, y: Int.max - 1, width: Int.max, height: Int.max),
        Rect(x: Int.min, y: Int.min, width: Int.max, height: Int.max),
        Rect(width: Int.max, height: Int.max), negative,
    ] {
        var buffer = Buffer(width: 4, height: 3)
        calendar.render(in: area, buffer: &buffer)
        #expect(calendar.date(at: Point(x: Int.max, y: Int.max), in: area) == nil)
    }
}
