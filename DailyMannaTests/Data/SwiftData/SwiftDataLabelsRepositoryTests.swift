import Foundation
import XCTest
import SwiftData
@testable import DailyManna

final class SwiftDataLabelsRepositoryTests: XCTestCase {
    var container: DataContainer! = nil
    var repo: LabelsRepository! = nil
    var tasksRepo: TasksRepository! = nil
    
    override func setUpWithError() throws {
        container = try DataContainer.test()
        repo = container.labelsRepository
        tasksRepo = container.tasksRepository
    }
    
    override func tearDownWithError() throws {
        container = nil
        repo = nil
        tasksRepo = nil
    }
    
    func testCreateFetchUpdateSoftDeleteAndPurge() async throws {
        let user = TestFactories.userId(1)
        var l = TestFactories.label(userId: user)
        try await repo.createLabel(l)
        
        var fetched = try await repo.fetchLabel(by: l.id)
        XCTAssertNotNil(fetched)
        
        fetched?.name = "@home"
        fetched?.updatedAt = Date()
        try await repo.updateLabel(fetched!)
        let updated = try await repo.fetchLabel(by: l.id)
        XCTAssertEqual(updated?.name, "@home")
        
        try await repo.deleteLabel(by: l.id)
        let afterDelete = try await repo.fetchLabel(by: l.id)
        XCTAssertNil(afterDelete?.deletedAt == nil ? afterDelete : nil)
        
        let purgeDate = Date().addingTimeInterval(60)
        try await repo.purgeDeletedLabels(olderThan: purgeDate)
        let afterPurge = try await repo.fetchLabel(by: l.id)
        XCTAssertNil(afterPurge)
    }
    
    func testLabelTaskJunctionQueries() async throws {
        let user = TestFactories.userId(2)
        let t1 = TestFactories.task(userId: user, title: "T1")
        let t2 = TestFactories.task(userId: user, title: "T2")
        let lab = TestFactories.label(userId: user, name: "@work")
        try await tasksRepo.createTask(t1)
        try await tasksRepo.createTask(t2)
        try await repo.createLabel(lab)
        
        try await repo.addLabel(lab.id, to: t1.id, for: user)
        try await repo.addLabel(lab.id, to: t2.id, for: user)
        
        let labelsForT1 = try await repo.fetchLabelsForTask(t1.id)
        XCTAssertEqual(labelsForT1.map { $0.id }, [lab.id])
        
        let tasksForLabel = try await repo.fetchTasks(with: lab.id)
        XCTAssertEqual(Set(tasksForLabel.map { $0.id }), Set([t1.id, t2.id]))
        
        try await repo.removeLabel(lab.id, from: t2.id, for: user)
        let tasksForLabelAfter = try await repo.fetchTasks(with: lab.id)
        XCTAssertEqual(Set(tasksForLabelAfter.map { $0.id }), Set([t1.id]))
    }
}


