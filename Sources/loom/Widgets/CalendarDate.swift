/// Errors for date-only Gregorian calendar values.
public enum CalendarDateError: Error, Equatable, Sendable {
    case invalidYear(Int)
    case invalidMonth(Int)
    case invalidDay(Int)
}

/// A weekday in Monday-first order, independent of locale or timezone.
public enum CalendarWeekday: Int, CaseIterable, Sendable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
}

/// A validated Gregorian month in years 1 through 9999.
public struct CalendarMonth: Hashable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) throws {
        guard (1...9999).contains(year) else { throw CalendarDateError.invalidYear(year) }
        guard (1...12).contains(month) else { throw CalendarDateError.invalidMonth(month) }
        self.year = year
        self.month = month
    }

    public var dayCount: Int {
        switch month {
        case 2: return year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100)) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public var firstDay: CalendarDay { CalendarDay(validatedYear: year, month: month, day: 1) }
}

/// A date-only Gregorian day with no implicit clock, timezone, or daylight-saving conversion.
public struct CalendarDay: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        let period = try CalendarMonth(year: year, month: month)
        guard (1...period.dayCount).contains(day) else { throw CalendarDateError.invalidDay(day) }
        self.init(validatedYear: year, month: month, day: day)
    }

    fileprivate init(validatedYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var weekday: CalendarWeekday { CalendarWeekday(rawValue: ordinal % 7)! }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Adds whole calendar days; returns nil outside years 1...9999 or on integer overflow.
    public func adding(days: Int) -> CalendarDay? {
        let result = ordinal.addingReportingOverflow(days)
        guard !result.overflow, (0..<3_652_059).contains(result.partialValue) else { return nil }
        let ordinal = result.partialValue
        var lower = 1
        var upper = 10000
        while lower + 1 < upper {
            let middle = lower + (upper - lower) / 2
            if Self.daysBefore(year: middle) <= ordinal { lower = middle } else { upper = middle }
        }
        var remaining = ordinal - Self.daysBefore(year: lower)
        for month in 1...12 {
            // Bounds are established by the binary search and the fixed month range.
            let period = try! CalendarMonth(year: lower, month: month)
            if remaining < period.dayCount {
                return CalendarDay(validatedYear: lower, month: month, day: remaining + 1)
            }
            remaining -= period.dayCount
        }
        return nil
    }

    private var ordinal: Int {
        var result = Self.daysBefore(year: year) + day - 1
        for previous in 1..<month {
            result += try! CalendarMonth(year: year, month: previous).dayCount
        }
        return result
    }

    private static func daysBefore(year: Int) -> Int {
        let previous = year - 1
        return previous * 365 + previous / 4 - previous / 100 + previous / 400
    }
}
