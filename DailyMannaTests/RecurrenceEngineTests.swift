import XCTest
@testable import DailyManna

final class RecurrenceEngineTests: XCTestCase {
    func testMonthlyClampsToLastDay() {
        let engine = RecurrenceEngine()
        var comps = DateComponents(year: 2025, month: 1, day: 31, hour: 9, minute: 0)
        let cal = Calendar.current
        let jan31 = cal.date(from: comps)!
        let rule = RecurrenceRule(freq: .monthly, interval: 1, byMonthDay: [31], time: "09:00")
        let next = engine.nextOccurrence(from: jan31, rule: rule, calendar: cal)
        // February does not have 31 days; expect clamped to Feb 28 or 29 depending on leap year
        XCTAssertNotNil(next)
        let d = next!
        let dc = cal.dateComponents([.year,.month,.day], from: d)
        XCTAssertEqual(dc.month, 2)
        XCTAssertTrue((dc.day ?? 0) >= 28 && (dc.day ?? 0) <= 29)
    }

    func testWeeklyWeekdaysSelection() {
        let engine = RecurrenceEngine()
        // Anchor on Monday
        var comps = DateComponents(year: 2025, month: 8, day: 4) // 2025-08-04 is Monday
        let cal = Calendar.current
        let anchor = cal.date(from: comps)!
        let rule = RecurrenceRule(freq: .weekly, interval: 1, byWeekday: ["WE","FR"], time: "08:00")
        let next = engine.nextOccurrence(from: anchor, rule: rule, calendar: cal)
        XCTAssertNotNil(next)
        let wd = cal.component(.weekday, from: next!)
        // Expect Wednesday (4) in Gregorian 1=Sun..7=Sat
        XCTAssertEqual(wd, 4)
    }

    func testSeriesMonthlyEveryFourMonthsFromOct1() {
        let engine = RecurrenceEngine()
        var comps = DateComponents(year: 2025, month: 10, day: 1)
        let cal = Calendar.current
        let oct1 = cal.date(from: comps)!
        let rule = RecurrenceRule(freq: .monthly, interval: 4, byMonthDay: [1], time: "09:00")
        // Oct 1 -> next should be Feb 1, 2026 when iterating from Oct 1
        let next = engine.nextOccurrence(from: oct1, rule: rule, calendar: cal)
        XCTAssertNotNil(next)
        let dc = cal.dateComponents([.year,.month,.day], from: next!)
        XCTAssertEqual(dc.year, 2026)
        XCTAssertEqual(dc.month, 2)
        XCTAssertEqual(dc.day, 1)
    }

    func testYearlyNthWeekday() {
        let engine = RecurrenceEngine()
        var comps = DateComponents(year: 2025, month: 1, day: 1)
        let cal = Calendar.current
        let anchor = cal.date(from: comps)!
        // Every year: third Monday of March at 10:30
        let rule = RecurrenceRule(freq: .yearly, interval: 1, byWeekday: ["MO"], bySetPos: [3], byMonth: [3], time: "10:30")
        let next = engine.nextOccurrence(from: anchor, rule: rule, calendar: cal)
        XCTAssertNotNil(next)
        let dc = cal.dateComponents([.month,.weekday,.hour,.minute], from: next!)
        XCTAssertEqual(dc.month, 3)
        XCTAssertEqual(dc.weekday, 2) // Monday
        XCTAssertEqual(dc.hour, 10)
        XCTAssertEqual(dc.minute, 30)
    }
}


