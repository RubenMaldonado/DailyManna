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
}


