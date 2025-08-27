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


