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
}


