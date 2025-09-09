import XCTest
@testable import DailyManna

final class WeekPlannerTests: XCTestCase {
    func testRemainingWeekdays_Midweek() {
        // Wed 2025-09-10 10:00 local
        var comps = DateComponents(); comps.year = 2025; comps.month = 9; comps.day = 10; comps.hour = 10; comps.minute = 0
        let cal = Calendar.current
        guard let date = cal.date(from: comps) else { return XCTFail("bad date") }
        let days = WeekPlanner.remainingWeekdays(from: date)
        XCTAssertFalse(days.isEmpty)
        // First should be start of that Wednesday
        XCTAssertEqual(cal.startOfDay(for: date), days.first)
        // Should not go beyond Friday
        XCTAssertLessThanOrEqual(days.count, 3)
    }

    func testBuildSections_TodayLabelAndDates() {
        // Mon 2025-09-08
        var comps = DateComponents(); comps.year = 2025; comps.month = 9; comps.day = 8; comps.hour = 9
        let cal = Calendar.current
        guard let monday = cal.date(from: comps) else { return XCTFail("bad date") }
        let sections = WeekPlanner.buildSections(for: monday)
        XCTAssertGreaterThan(sections.count, 0)
        XCTAssertTrue(sections.first?.isToday == true)
        XCTAssertEqual(sections.first?.title, "Today")
        // Last should be Friday of that week
        let friday = WeekPlanner.fridayOfCurrentWeek(for: monday)
        XCTAssertEqual(sections.last?.date, friday)
    }
}


