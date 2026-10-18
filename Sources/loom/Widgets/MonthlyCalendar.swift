/// A date-only monthly grid with caller-owned event, today, and selection styling.
///
/// Seven three-cell columns make a 21-cell grid. Narrow viewports clip whole
/// glyphs without changing date geometry. Weekday labels use Monday-first array
/// order and are rotated according to `firstWeekday`. Names are caller-localizable;
/// the widget never reads the wall clock or changes terminal modes.
public struct MonthlyCalendar: Widget, Sendable {
    public var month: CalendarMonth
    public var firstWeekday: CalendarWeekday = .monday
    public var showsMonthHeader = true
    public var showsWeekdays = true
    public var showsSurroundingDays = false
    public var fixedWeekCount = false
    public var monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
    public var weekdayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    public var style = Style()
    public var headerStyle = Style(bold: true)
    public var weekdayStyle = Style(bold: true)
    public var weekendPatch = StylePatch()
    public var surroundingPatch = StylePatch(dim: true)
    public var events: [CalendarDay: StylePatch] = [:]
    public var today: CalendarDay?
    public var todayPatch = StylePatch(underlined: true)
    public var selectedDay: CalendarDay?
    public var selectionPatch = StylePatch(reversed: true)

    public init(month: CalendarMonth, events: [CalendarDay: StylePatch] = [:]) {
        self.month = month
        self.events = events
    }

    /// Number of rows needed for all enabled headers and weeks, before clipping.
    public var requiredHeight: Int { headerRows + weekCount }

    /// Maps a visible day label to its date.
    ///
    /// Separators, headers, and hidden surrounding days have no target.
    public func date(at point: Point, in area: Rect) -> CalendarDay? {
        let area = representableBorderArea(area)
        guard area.contains(point) else { return nil }
        let column = point.x.subtractingReportingOverflow(area.x)
        let row = point.y.subtractingReportingOverflow(area.y)
        guard !column.overflow, !row.overflow, (0..<21).contains(column.partialValue),
            column.partialValue % 3 < 2,
            (headerRows..<requiredHeight).contains(row.partialValue)
        else { return nil }
        return dateForCell(week: row.partialValue - headerRows, weekday: column.partialValue / 3)
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        let area = representableBorderArea(area)
        guard area.width > 0, area.height > 0 else { return }
        // A grid has at most eight rows. Restrict iteration to visible physical rows,
        // retaining coordinates so clipping never shifts the weekday columns.
        buffer.withClip(area) { target in
            target.fill(area, style: style)
            if showsMonthHeader {
                let name =
                    monthNames.indices.contains(month.month - 1) ? monthNames[month.month - 1] : String(month.month)
                paint(
                    "\(name) \(month.year)", column: 0, row: 0, width: 20, in: area,
                    style: collectionStyle(style, overlay: headerStyle), buffer: &target)
            }
            if showsWeekdays {
                for column in 0..<7 {
                    let index = (firstWeekday.rawValue + column) % 7
                    let name = weekdayLabels.indices.contains(index) ? weekdayLabels[index] : ""
                    paint(
                        name, column: column * 3, row: showsMonthHeader ? 1 : 0, width: 2, in: area,
                        style: collectionStyle(style, overlay: weekdayStyle), buffer: &target)
                }
            }
            for week in 0..<weekCount {
                for column in 0..<7 {
                    guard let date = dateForCell(week: week, weekday: column) else { continue }
                    var appearance = style
                    if date.weekday == .saturday || date.weekday == .sunday {
                        appearance = appearance.applying(weekendPatch)
                    }
                    if date.month != month.month || date.year != month.year {
                        appearance = appearance.applying(surroundingPatch)
                    }
                    if let event = events[date] { appearance = appearance.applying(event) }
                    if date == today { appearance = appearance.applying(todayPatch) }
                    if date == selectedDay { appearance = appearance.applying(selectionPatch) }
                    paint(
                        date.day < 10 ? " \(date.day)" : String(date.day), column: column * 3,
                        row: headerRows + week, width: 2, in: area, style: appearance, buffer: &target)
                }
            }
        }
    }

    private var headerRows: Int { (showsMonthHeader ? 1 : 0) + (showsWeekdays ? 1 : 0) }
    private var leadingDays: Int { (month.firstDay.weekday.rawValue - firstWeekday.rawValue + 7) % 7 }
    private var weekCount: Int { fixedWeekCount ? 6 : (leadingDays + month.dayCount + 6) / 7 }

    private func dateForCell(week: Int, weekday: Int) -> CalendarDay? {
        guard let date = month.firstDay.adding(days: week * 7 + weekday - leadingDays) else { return nil }
        return showsSurroundingDays || (date.month == month.month && date.year == month.year) ? date : nil
    }

    private func paint(
        _ text: String, column: Int, row: Int, width: Int, in area: Rect, style: Style, buffer: inout Buffer
    ) {
        guard column < area.width, row < area.height else { return }
        let x = area.x.addingReportingOverflow(column)
        let y = area.y.addingReportingOverflow(row)
        guard !x.overflow, !y.overflow else { return }
        let paintArea = representableBorderArea(
            Rect(x: x.partialValue, y: y.partialValue, width: min(width, area.width - column), height: 1))
        let layout = TextLayout(text, width: max(1, width), wrapping: .none)
        layout.paint(
            in: paintArea,
            style: style, buffer: &buffer)
    }
}
