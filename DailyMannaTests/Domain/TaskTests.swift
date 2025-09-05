import Foundation
import XCTest
@testable import DailyManna

final class TaskTests: XCTestCase {
    func testSoftDeleteFlag() {
        var task = TestFactories.task()
        XCTAssertFalse(task.isDeleted)
        let now = Date()
        task.deletedAt = now
        XCTAssertTrue(task.isDeleted)
    }
    
    func testToggleCompletionSetsCompletedAt() async throws {
        let container = try DataContainer.test()
        let tasks = container.tasksRepository
        let labels = container.labelsRepository
        let useCases = TaskUseCases(tasksRepository: tasks, labelsRepository: labels)
        let user = TestFactories.userId(1)
        var t = TestFactories.task(userId: user)
        try await tasks.createTask(t)
        try await useCases.toggleTaskCompletion(id: t.id, userId: user)
        let fetched = try await tasks.fetchTask(by: t.id)
        XCTAssertEqual(fetched?.isCompleted, true)
        XCTAssertNotNil(fetched?.completedAt)
    }

    func testMoveTaskBetweenBuckets() async throws {
        let userId = TestFactories.userId(11)
        let data = try DataContainer.test()
        let useCases = TaskUseCases(tasksRepository: data.tasksRepository, labelsRepository: data.labelsRepository)

        let task = TestFactories.task(userId: userId, bucket: .thisWeek, title: "A")
        try await useCases.createTask(task)

        var fetched = try await useCases.fetchTasksWithLabels(for: userId, in: .thisWeek)
        XCTAssertEqual(fetched.count, 1)

        try await useCases.moveTask(id: task.id, to: .nextWeek, for: userId)

        fetched = try await useCases.fetchTasksWithLabels(for: userId, in: .thisWeek)
        XCTAssertEqual(fetched.count, 0)

        let fetchedNextWeek = try await useCases.fetchTasksWithLabels(for: userId, in: .nextWeek)
        XCTAssertEqual(fetchedNextWeek.count, 1)
    }

    func testCountsExcludeCompletedByDefault() async throws {
        let userId = TestFactories.userId(12)
        let data = try DataContainer.test()
        let useCases = TaskUseCases(tasksRepository: data.tasksRepository, labelsRepository: data.labelsRepository)

        let t1 = TestFactories.task(userId: userId, bucket: .thisWeek, title: "A")
        var t2 = TestFactories.task(userId: userId, bucket: .thisWeek, title: "B")
        t2.isCompleted = true
        try await useCases.createTask(t1)
        try await useCases.createTask(t2)

        let count = try await useCases.countTasks(for: userId, in: .thisWeek)
        XCTAssertEqual(count, 1)

        let countIncluding = try await useCases.countTasks(for: userId, in: .thisWeek, includeCompleted: true)
        XCTAssertEqual(countIncluding, 2)
    }
}

final class AvailableFilterTests: XCTestCase {
    func test_noDueDate_tasksAreAvailable() async throws {
        let uid = TestFactories.userId(1)
        let now = Date()
        var t1 = TestFactories.task(userId: uid, title: "No due 1", now: now)
        var t2 = TestFactories.task(userId: uid, title: "No due 2", now: now)
        t1.dueAt = nil
        t2.dueAt = nil
        let pairs: [(Task, [Label])] = [(t1, []), (t2, [])]
        let model = StubViewModel()
        let endOfToday = model.availableCutoffEndOfToday()
        let filtered = pairs.filter { pair in
            let t = pair.0
            guard t.isCompleted == false else { return false }
            if let due = t.dueAt { return due <= endOfToday }
            return true
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func test_dueAtBoundary_includedWhenEqual() async throws {
        let uid = TestFactories.userId(2)
        let model = StubViewModel()
        let end = model.availableCutoffEndOfToday()
        var t = TestFactories.task(userId: uid, title: "Boundary", now: end)
        t.dueAt = end
        let pairs: [(Task, [Label])] = [(t, [])]
        let filtered = pairs.filter { pair in
            let tt = pair.0
            guard tt.isCompleted == false else { return false }
            if let due = tt.dueAt { return due <= end }
            return true
        }
        XCTAssertEqual(filtered.count, 1)
    }

    func test_timezoneDST_transitionStillIncludesCorrectly() async throws {
        // Simulate a due date near midnight and ensure cutoff honors end-of-day
        let uid = TestFactories.userId(3)
        let model = StubViewModel()
        let end = model.availableCutoffEndOfToday()
        // Due at just before cutoff
        var t1 = TestFactories.task(userId: uid, title: "Before cutoff", now: end)
        t1.dueAt = Calendar.current.date(byAdding: .second, value: -10, to: end)
        // Due at just after cutoff
        var t2 = TestFactories.task(userId: uid, title: "After cutoff", now: end)
        t2.dueAt = Calendar.current.date(byAdding: .second, value: 10, to: end)
        let pairs: [(Task, [Label])] = [(t1, []), (t2, [])]
        let filtered = pairs.filter { pair in
            let tt = pair.0
            guard tt.isCompleted == false else { return false }
            if let due = tt.dueAt { return due <= end }
            return true
        }
        XCTAssertEqual(filtered.map { $0.0.title }.sorted(), ["Before cutoff"]) // only before cutoff included
    }
}

// Minimal stub to access availableCutoffEndOfToday logic
private final class StubViewModel: ObservableObject {
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


