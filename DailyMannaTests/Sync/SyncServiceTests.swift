import Foundation
import XCTest
@testable import DailyManna

@MainActor
final class SyncServiceTests: XCTestCase {
    func testPushLocalChangesMarksNeedsSyncFalse() async throws {
        let container = try DataContainer.test()
        let localTasks = container.tasksRepository
        let localLabels = container.labelsRepository
        let remoteTasks = FakeRemoteTasksRepository()
        let remoteLabels = FakeRemoteLabelsRepository()
        let sync = SyncService(
            localTasksRepository: localTasks,
            remoteTasksRepository: remoteTasks,
            localLabelsRepository: localLabels,
            remoteLabelsRepository: remoteLabels
        )
        let user = TestFactories.userId(1)
        var t = TestFactories.task(userId: user)
        try await localTasks.createTask(t)
        await sync.sync(for: user)
        let fetched = try await localTasks.fetchTask(by: t.id)
        XCTAssertEqual(fetched?.needsSync, false)
        XCTAssertNotNil(fetched?.remoteId)
    }
    
    func testPullRemoteChangesAppliesLWW() async throws {
        let container = try DataContainer.test()
        let localTasks = container.tasksRepository
        let localLabels = container.labelsRepository
        let remoteTasks = FakeRemoteTasksRepository()
        let remoteLabels = FakeRemoteLabelsRepository()
        let sync = SyncService(
            localTasksRepository: localTasks,
            remoteTasksRepository: remoteTasks,
            localLabelsRepository: localLabels,
            remoteLabelsRepository: remoteLabels
        )
        let user = TestFactories.userId(1)
        var local = TestFactories.task(userId: user, title: "local")
        try await localTasks.createTask(local)
        var remote = local
        remote.title = "remote"
        remote.updatedAt = local.updatedAt.addingTimeInterval(10)
        remoteTasks.sinceResponses = [nil: [remote]]
        await sync.sync(for: user)
        let fetched = try await localTasks.fetchTask(by: local.id)
        XCTAssertEqual(fetched?.title, "remote")
    }
}


