import XCTest
@testable import DailyManna

final class PerformanceTests: XCTestCase {
    func test_labelFilterPerformance_onLargeDataset() throws {
        let uid = TestFactories.userId(100)
        let labels = TestFixtures.makeLabels(count: 200, userId: uid)
        let tasks = TestFixtures.makeTasks(count: 1000, userId: uid)
        let pairs = TestFixtures.assignLabelsToTasks(tasks: tasks, labelPool: labels, minPerTask: 0, maxPerTask: 3)
        // Choose a random filter of ~3 labels
        let target = Set(labels.prefix(3).map { $0.id })
        measure(metrics: [XCTClockMetric()]) {
            // Build id sets map as in production code
            let idSetsByTask: [UUID: Set<UUID>] = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.id, Set($0.1.map { $0.id })) })
            let matchAll = true
            let filtered = pairs.filter { pair in
                let ids = idSetsByTask[pair.0.id] ?? []
                return matchAll ? ids.isSuperset(of: target) : ids.intersection(target).isEmpty == false
            }
            XCTAssertNotNil(filtered)
        }
    }

    func test_availableFilterPerformance_onLargeDataset() throws {
        let uid = TestFactories.userId(101)
        let tasks = TestFixtures.makeTasks(count: 1000, userId: uid)
        let pairs = tasks.map { ($0, [Label]()) }
        let cutoff = StubAvailableCutoff().availableCutoffEndOfToday()
        measure(metrics: [XCTClockMetric()]) {
            let filtered = pairs.filter { pair in
                let t = pair.0
                guard t.isCompleted == false else { return false }
                if let due = t.dueAt { return due <= cutoff }
                return true
            }
            XCTAssertNotNil(filtered)
        }
    }
}

private final class StubAvailableCutoff {
    fileprivate var availableCutoffCache: (dayKey: String, cutoff: Date)? = nil
    func availableCutoffEndOfToday() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        let dayKey = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        if let cached = availableCutoffCache, cached.dayKey == dayKey {
            return cached.cutoff
        }
        let cutoff = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        availableCutoffCache = (dayKey, cutoff)
        return cutoff
    }
}
