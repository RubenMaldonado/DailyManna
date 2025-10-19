import XCTest
@testable import DailyManna

final class NewTemplateSummaryTests: XCTestCase {
    func testWeeklySummaryAndPreview() async throws {
        let uid = UUID()
        let vm = NewTemplateViewModel(userId: uid)
        vm.name = "Weekly Review"
        vm.frequency = .weekly
        vm.interval = 1
        vm.selectedWeekdays = [2,5] // Mon & Thu
        vm.defaultTime = Date(timeIntervalSince1970: 0) // 12:00 AM UTC -> formatted by locale
        vm.startsOn = date(2025, 10, 6) // Monday
        vm.endRule = .afterCount(5)
        vm.recomputePreview()
        XCTAssertTrue(vm.summaryText.contains("Every week"))
        XCTAssertTrue(vm.summaryText.contains("on"))
        XCTAssertEqual(vm.upcomingPreview.count, 5)
        // First preview should be Monday or Thursday after start; engine returns next from anchor
        let cal = Calendar.current
        let firstWD = cal.component(.weekday, from: vm.upcomingPreview.first!)
        XCTAssertTrue([2,5].contains(firstWD))
    }

    func testMonthlyNthWeekdaySummary() {
        let uid = UUID()
        let vm = NewTemplateViewModel(userId: uid)
        vm.name = "Team Retro"
        vm.frequency = .monthly
        vm.interval = 1
        vm.monthlyKind = .nthWeekday
        vm.monthlyOrdinal = 3
        vm.monthlyWeekday = 5 // Thursday
        vm.startsOn = date(2025, 10, 1)
        vm.recomputePreview()
        XCTAssertTrue(vm.summaryText.contains("3rd"))
        XCTAssertTrue(vm.summaryText.contains("Thursday"))
        XCTAssertFalse(vm.upcomingPreview.isEmpty)
    }

    func testYearlyDaySummary() {
        let uid = UUID()
        let vm = NewTemplateViewModel(userId: uid)
        vm.name = "Anniversary"
        vm.frequency = .yearly
        vm.interval = 1
        vm.yearlyKind = .dayOfMonth
        vm.yearlyMonth = 12
        vm.yearlyDay = 25
        vm.startsOn = date(2025, 6, 1)
        vm.recomputePreview()
        XCTAssertTrue(vm.summaryText.contains("December"))
        XCTAssertTrue(vm.summaryText.contains("25"))
        XCTAssertFalse(vm.upcomingPreview.isEmpty)
    }

    // MARK: - Helpers
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        return Calendar.current.date(from: comps) ?? Date()
    }
}


