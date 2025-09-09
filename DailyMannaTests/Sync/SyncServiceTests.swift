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
            remoteLabelsRepository: remoteLabels,
            syncStateStore: container.syncStateStore
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
            remoteLabelsRepository: remoteLabels,
            syncStateStore: container.syncStateStore
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

    func testWorkingLogSyncPushPull() async throws {
        let container = try DataContainer.test()
        let localTasks = container.tasksRepository
        let localLabels = container.labelsRepository
        let localWorking = SwiftDataWorkingLogRepository(modelContext: ModelContext(container.modelContainer))
        let remoteTasks = FakeRemoteTasksRepository()
        let remoteLabels = FakeRemoteLabelsRepository()
        let remoteWorking = FakeRemoteWorkingLogRepository()
        let sync = SyncService(
            localTasksRepository: localTasks,
            remoteTasksRepository: remoteTasks,
            localLabelsRepository: localLabels,
            remoteLabelsRepository: remoteLabels,
            syncStateStore: container.syncStateStore,
            localWorkingLogRepository: localWorking,
            remoteWorkingLogRepository: remoteWorking
        )
        let user = TestFactories.userId(99)
        let item = WorkingLogItem(userId: user, title: "Win", description: "Shipped", occurredAt: Date().addingTimeInterval(-3600))
        try await localWorking.create(item)
        await sync.sync(for: user)
        XCTAssertEqual(remoteWorking.upserts.count, 1)
        var server = item
        server.updatedAt = Date().addingTimeInterval(120)
        remoteWorking.sinceResponses = [nil: [server]]
        await sync.sync(for: user)
        let fetched = try await localWorking.fetch(by: item.id)
        XCTAssertEqual(fetched?.updatedAt, server.updatedAt)
    }

    func testToggleParentCascadesToChildren() async throws {
        // Arrange
        let container = Dependencies.shared
        let tasksRepo: TasksRepository = try! container.resolve(type: TasksRepository.self)
        let labelsRepo: LabelsRepository = try! container.resolve(type: LabelsRepository.self)
        let useCases = TaskUseCases(tasksRepository: tasksRepo, labelsRepository: labelsRepo)
        let userId = TestFactories.userId(42)
        let parent = TestFactories.task(userId: userId, title: "Parent")
        try await tasksRepo.createTask(parent)
        _ = try await useCases.createSubtask(parentId: parent.id, userId: userId, title: "S1")
        _ = try await useCases.createSubtask(parentId: parent.id, userId: userId, title: "S2")

        // Act
        try await useCases.toggleParentCompletionCascade(parentId: parent.id)

        // Assert
        let refreshedParent = try await tasksRepo.fetchTask(by: parent.id)
        let children = try await tasksRepo.fetchSubTasks(for: parent.id)
        XCTAssertEqual(refreshedParent?.isCompleted, true)
        XCTAssertTrue(children.allSatisfy { $0.isCompleted })

        // Toggle back
        try await useCases.toggleParentCompletionCascade(parentId: parent.id)
        let childrenBack = try await tasksRepo.fetchSubTasks(for: parent.id)
        XCTAssertFalse(childrenBack.contains { $0.isCompleted })
    }

    func testSubtaskProgress() async throws {
        let container = Dependencies.shared
        let tasksRepo: TasksRepository = try! container.resolve(type: TasksRepository.self)
        let labelsRepo: LabelsRepository = try! container.resolve(type: LabelsRepository.self)
        let useCases = TaskUseCases(tasksRepository: tasksRepo, labelsRepository: labelsRepo)
        let userId = TestFactories.userId(7)
        let parent = TestFactories.task(userId: userId, title: "Parent")
        try await tasksRepo.createTask(parent)
        let s1 = try await useCases.createSubtask(parentId: parent.id, userId: userId, title: "S1")
        _ = try await useCases.createSubtask(parentId: parent.id, userId: userId, title: "S2")
        _ = try await useCases.toggleSubtaskCompletion(id: s1.id)
        let (completed, total) = try await useCases.getSubtaskProgress(parentTaskId: parent.id)
        XCTAssertEqual(total, 2)
        XCTAssertEqual(completed, 1)
    }
}


