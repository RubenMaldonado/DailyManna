//
//  WeekPlanner.swift
//  DailyManna
//
//  Utilities for computing weekday sections (Mon–Fri) relative to today
//

import Foundation

public struct WeekdaySection: Identifiable, Hashable {
    public let id: String // yyyy-MM-dd
    public let date: Date
    public let title: String
    public let isToday: Bool
}

public enum WeekPlanner {
    // MARK: - Date helpers
    public static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Monday of the current week for the given date using the user's locale calendar, normalized to start of day
    public static func mondayOfCurrentWeek(for date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let startOfDay = cal.startOfDay(for: date)
        let weekdayIndex = cal.component(.weekday, from: startOfDay)
        // Convert to Monday-based index: Monday=2 ... Sunday=1 -> offset back to Monday
        // Compute distance from Monday
        let distanceFromMonday: Int = (weekdayIndex == 1) ? 6 : (weekdayIndex - 2)
        return cal.date(byAdding: .day, value: -distanceFromMonday, to: startOfDay) ?? startOfDay
    }

    /// Returns the Date for the Friday of the current week for the given date (start of day)
    public static func fridayOfCurrentWeek(for date: Date, calendar: Calendar = .current) -> Date {
        let monday = mondayOfCurrentWeek(for: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 4, to: monday) ?? monday
    }

    /// Returns the next Monday following the provided date (not inclusive). Normalized to start of day.
    public static func nextMonday(after date: Date = Date(), calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let start = cal.startOfDay(for: date)
        // Compute Monday of current week then add 7 days to get next week's Monday
        let thisWeekMonday = mondayOfCurrentWeek(for: start, calendar: cal)
        return cal.date(byAdding: .day, value: 7, to: thisWeekMonday) ?? thisWeekMonday
    }

    /// Returns the Sunday for the next week (Mon+6) relative to the provided date
    public static func nextSunday(after date: Date = Date(), calendar: Calendar = .current) -> Date {
        let cal = calendar
        let nextMon = nextMonday(after: date, calendar: cal)
        return cal.date(byAdding: .day, value: 6, to: nextMon).map { cal.startOfDay(for: $0) } ?? nextMon
    }

    /// Returns the nearest upcoming Saturday relative to `date` (including today if Saturday).
    /// If the day is Sunday, returns Sunday (today). Always start of day.
    public static func weekendAnchor(for date: Date = Date(), calendar: Calendar = .current) -> Date {
        let cal = calendar
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start) // Sunday=1 ... Saturday=7
        if weekday == 7 { return start } // Saturday
        if weekday == 1 { return start } // Sunday
        // Weekday: compute next Saturday
        let daysUntilSaturday = 7 - weekday
        return cal.date(byAdding: .day, value: daysUntilSaturday, to: start) ?? start
    }

    /// Returns dates for remaining weekdays from `today` (inclusive Today for section titles) to Friday, excluding weekends
    public static func remainingWeekdays(from today: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let cal = calendar
        let startToday = cal.startOfDay(for: today)
        let friday = fridayOfCurrentWeek(for: startToday, calendar: cal)
        var dates: [Date] = []
        var cursor = startToday
        while cursor <= friday {
            let weekday = cal.component(.weekday, from: cursor)
            // Monday=2...Friday=6 when firstWeekday=1 (system default). Using standard Apple mapping where Sunday=1
            if weekday >= 2 && weekday <= 6 { dates.append(cursor) }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            if cursor == startToday { break } // safety
        }
        return dates
    }

    /// Builds weekday sections (Today + remaining Mon–Fri) with local formatted titles
    public static func buildSections(for today: Date = Date(), calendar: Calendar = .current, dateFormatter: DateFormatter = WeekPlanner.headerDateFormatter) -> [WeekdaySection] {
        let cal = calendar
        let todayStart = cal.startOfDay(for: today)
        let dates = remainingWeekdays(from: todayStart, calendar: cal)
        return dates.map { date in
            let isToday = (date == todayStart)
            let title = isToday ? "Today" : dateFormatter.string(from: date)
            return WeekdaySection(id: isoDayKey(for: date, calendar: cal), date: date, title: title, isToday: isToday)
        }
    }

    /// Returns the Saturday and Sunday (start of day) for the current week of the provided date
    public static func saturdayAndSundayOfCurrentWeek(for date: Date = Date(), calendar: Calendar = .current) -> (saturday: Date, sunday: Date) {
        let cal = calendar
        let monday = mondayOfCurrentWeek(for: date, calendar: cal)
        let saturday = cal.date(byAdding: .day, value: 5, to: monday).map { cal.startOfDay(for: $0) } ?? monday
        let sunday = cal.date(byAdding: .day, value: 6, to: monday).map { cal.startOfDay(for: $0) } ?? saturday
        return (saturday, sunday)
    }

    /// Returns two dates representing this weekend (Saturday and Sunday) of the current week
    public static func thisWeekendDates(for date: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let pair = saturdayAndSundayOfCurrentWeek(for: date, calendar: calendar)
        return [pair.saturday, pair.sunday]
    }

    /// Returns seven start-of-day dates for next week (Mon–Sun) relative to the provided date
    public static func datesOfNextWeek(from date: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let cal = calendar
        let nextMon = nextMonday(after: date, calendar: cal)
        return (0...6).compactMap { offset in cal.date(byAdding: .day, value: offset, to: nextMon) }.map { cal.startOfDay(for: $0) }
    }

    /// Builds seven sections for next week (Mon–Sun) with localized short titles (e.g., "Tue, Sep 16")
    public static func buildNextWeekSections(for today: Date = Date(), calendar: Calendar = .current, dateFormatter: DateFormatter = WeekPlanner.shortHeaderDateFormatter) -> [WeekdaySection] {
        let cal = calendar
        let dates = datesOfNextWeek(from: today, calendar: cal)
        return dates.map { date in
            let title = dateFormatter.string(from: date)
            return WeekdaySection(id: isoDayKey(for: date, calendar: cal), date: date, title: title, isToday: false)
        }
    }

    /// ISO-like day key yyyy-MM-dd in local time
    public static func isoDayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        let mm = String(format: "%02d", m)
        let dd = String(format: "%02d", d)
        return "\(y)-\(mm)-\(dd)"
    }

    // MARK: - Formatters
    public static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE • MMM d"
        return f
    }()

    /// Short header format used for Next Week sections
    public static let shortHeaderDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}


