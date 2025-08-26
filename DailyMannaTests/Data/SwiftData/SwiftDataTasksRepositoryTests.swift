import Foundation
import XCTest
import SwiftData
@testable import DailyManna

final class SwiftDataTasksRepositoryTests: XCTestCase {
    var container: DataContainer! = nil
    var repo: TasksRepository! = nil
    
    override func setUpWithError() throws {
        container = try DataContainer.test()
        repo = container.tasksRepository
    }
    
    override func tearDownWithError() throws {
        container = nil
        repo = nil
    }
    
    func testCreateFetchUpdateSoftDeleteAndPurge() async throws {
        let user = TestFactories.userId(1)
        var t = TestFactories.task(userId: user)
        try await repo.createTask(t)
        
        // Fetch by id
        var fetched = try await repo.fetchTask(by: t.id)
        XCTAssertNotNil(fetched)
        
        // Update
        fetched?.title = "Updated"
        fetched?.updatedAt = Date()
        try await repo.updateTask(fetched!)
        let updated = try await repo.fetchTask(by: t.id)
        XCTAssertEqual(updated?.title, "Updated")
        
        // Soft delete
        try await repo.deleteTask(by: t.id)
        let afterDelete = try await repo.fetchTask(by: t.id)
        XCTAssertNil(afterDelete?.deletedAt == nil ? afterDelete : nil) // still present but soft-deleted
        
        // Purge
        let purgeDate = Date().addingTimeInterval(60)
        try await repo.purgeDeletedTasks(olderThan: purgeDate)
        let afterPurge = try await repo.fetchTask(by: t.id)
        XCTAssertNil(afterPurge)
    }
    
    func testFetchByBucketAndSorting() async throws {
        let user = TestFactories.userId(2)
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late = early.addingTimeInterval(3600)
        var a = TestFactories.task(userId: user, bucket: .thisWeek, title: "A", now: early)
        var b = TestFactories.task(userId: user, bucket: .thisWeek, title: "B", now: late)
        var c = TestFactories.task(userId: user, bucket: .nextWeek, title: "C", now: early)
        try await repo.createTask(a)
        try await repo.createTask(b)
        try await repo.createTask(c)
        
        let allThisWeek = try await repo.fetchTasks(for: user, in: .thisWeek)
        XCTAssertEqual(allThisWeek.count, 2)
        XCTAssertEqual(allThisWeek.map { $0.title }, ["A", "B"]) // sorted by dueAt then createdAt
        
        let allAny = try await repo.fetchTasks(for: user, in: nil)
        XCTAssertEqual(allAny.count, 3)
    }
}


