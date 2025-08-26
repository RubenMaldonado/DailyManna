import Foundation
import XCTest
@testable import DailyManna

final class SupabaseContractTests: XCTestCase {
    override class func setUp() {
        super.setUp()
    }
    
    func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] == "1"
    }
    
    func testCRUDAndDeltaAndTombstone_whenEnabled() async throws {
        try XCTSkipUnless(isEnabled(), "Integration tests disabled; set INTEGRATION_TESTS=1 to enable")
        let client = SupabaseConfig.shared.client
        let remote = SupabaseTasksRepository(client: client)
        let user = TestFactories.userId(10)
        var t = TestFactories.task(userId: user, title: "contract")
        let created = try await remote.createTask(t)
        XCTAssertEqual(created.title, t.title)
        
        var updated = created
        updated.title = "updated"
        updated.updatedAt = Date()
        let afterUpdate = try await remote.updateTask(updated)
        XCTAssertEqual(afterUpdate.title, "updated")
        
        let since = try await remote.fetchTasks(since: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(since.contains { $0.id == created.id })
        
        try await remote.deleteTask(id: created.id)
        let tombstoned = try await remote.fetchTasks(since: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(tombstoned.contains { $0.id == created.id })
    }
}


