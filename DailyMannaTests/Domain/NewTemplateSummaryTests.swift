import XCTest
@testable import DailyManna

final class NewTemplateSummaryTests: XCTestCase {
    func testViewModelPersistsSelectedLabelsOnCreate() async throws {
        let uid = UUID()
        let vm = NewTemplateViewModel(userId: uid)
        vm.name = "Weekly Review"
        vm.selectedLabelIds = [UUID(), UUID()]
        // Wire a local-only repo stack to avoid crashing on save; intercept create
        let deps = Dependencies.shared
        deps.reset()
        try await MainActor.run { try? deps.configure() }
        // Swap templates repository with an in-memory spy
        class SpyTemplatesRepo: TemplatesRepository {
            var lastCreated: Template? = nil
            func list(ownerId: UUID) async throws -> [Template] { return [] }
            func get(id: UUID, ownerId: UUID) async throws -> Template? { return nil }
            func create(_ template: Template) async throws { lastCreated = template }
            func update(_ template: Template) async throws {}
            func delete(id: UUID, ownerId: UUID) async throws {}
        }
        let spy = SpyTemplatesRepo()
        Dependencies.shared.registerSingleton(type: TemplatesRepository.self) { spy }
        Dependencies.shared.registerSingleton(type: TemplatesUseCases.self) {
            try! TemplatesUseCases(local: Dependencies.shared.resolve(type: TemplatesRepository.self))
        }
        await vm.save()
        XCTAssertEqual(Set(spy.lastCreated?.labelsDefault ?? []), vm.selectedLabelIds)
    }
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


