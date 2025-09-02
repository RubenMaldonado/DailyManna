import Foundation

/// Minimal v1 recurrence engine supporting next occurrence for daily/weekly/monthly/yearly.
struct RecurrenceEngine {
    func nextOccurrence(from anchor: Date, rule: RecurrenceRule, calendar: Calendar = Calendar.current) -> Date? {
        switch rule.freq {
        case .daily:
            return addDays(anchor, rule.interval, calendar, time: rule.time)
        case .weekly:
            return nextWeekly(from: anchor, rule: rule, calendar: calendar)
        case .monthly:
            return nextMonthly(from: anchor, rule: rule, calendar: calendar)
        case .yearly:
            return nextYearly(from: anchor, rule: rule, calendar: calendar)
        }
    }

    private func addDays(_ date: Date, _ n: Int, _ cal: Calendar, time: String?) -> Date? {
        let next = cal.date(byAdding: .day, value: max(1, n), to: date)
        return applyTime(next, time, cal)
    }

    private func applyTime(_ date: Date?, _ time: String?, _ cal: Calendar) -> Date? {
        guard let date else { return nil }
        guard let time else { return date }
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return date }
        var comps = cal.dateComponents([.year,.month,.day], from: date)
        comps.hour = h; comps.minute = m
        return cal.date(from: comps)
    }

    private func nextWeekly(from anchor: Date, rule: RecurrenceRule, calendar cal: Calendar) -> Date? {
        let weekdays = (rule.byWeekday ?? []).compactMap { weekdayMap[$0.uppercased()] }
        guard weekdays.isEmpty == false else { return addDays(anchor, 7 * max(1, rule.interval), cal, time: rule.time) }
        let todayWD = cal.component(.weekday, from: anchor)
        // search next 14 days
        for i in 1...(14) {
            if let d = cal.date(byAdding: .day, value: i, to: anchor) {
                let wd = cal.component(.weekday, from: d)
                if weekdays.contains(wd) {
                    // ensure interval weeks boundary
                    if i % (7 * max(1, rule.interval)) == 0 || weekdays.count > 1 { return applyTime(d, rule.time, cal) }
                }
            }
        }
        return nil
    }

    private func nextMonthly(from anchor: Date, rule: RecurrenceRule, calendar cal: Calendar) -> Date? {
        let interval = max(1, rule.interval)
        var nextMonth = cal.date(byAdding: .month, value: interval, to: anchor) ?? anchor
        if let days = rule.byMonthDay, let day = days.first {
            var comps = cal.dateComponents([.year,.month], from: nextMonth)
            comps.day = min(day, 28) // safe default; follow-up passes adjust overflow
            return applyTime(cal.date(from: comps), rule.time, cal)
        }
        if let byWD = rule.byWeekday, let byPos = rule.bySetPos?.first, let wdSym = byWD.first, let wd = weekdayMap[wdSym] {
            // nth weekday of month
            var comps = cal.dateComponents([.year,.month], from: nextMonth)
            comps.weekday = wd
            comps.weekdayOrdinal = byPos
            return applyTime(cal.date(from: comps), rule.time, cal)
        }
        return cal.date(byAdding: .month, value: interval, to: anchor)
    }

    private func nextYearly(from anchor: Date, rule: RecurrenceRule, calendar cal: Calendar) -> Date? {
        let interval = max(1, rule.interval)
        guard let month = rule.byMonth?.first else { return cal.date(byAdding: .year, value: interval, to: anchor) }
        let day = rule.byMonthDay?.first ?? cal.component(.day, from: anchor)
        var comps = cal.dateComponents([.year], from: anchor)
        comps.year = comps.year! + interval
        comps.month = month
        comps.day = min(day, 28)
        return applyTime(cal.date(from: comps), rule.time, cal)
    }

    private let weekdayMap: [String: Int] = [
        "SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7
    ]
}


