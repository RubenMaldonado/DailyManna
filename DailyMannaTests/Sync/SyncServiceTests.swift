import Foundation
import SwiftData
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
        let localWorking = SwiftDataWorkingLogRepository(modelContext: ModelContext(container.modelContainer))
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
        let localWorking = SwiftDataWorkingLogRepository(modelContext: ModelContext(container.modelContainer))
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

    func testTemplateRebucketMovesOccurrences() async throws {
        Dependencies.shared.reset()
        let data = try DataContainer.test()
        let localTasks = data.tasksRepository
        let localLabels = data.labelsRepository
        Dependencies.shared.registerSingleton(type: TasksRepository.self) { localTasks }
        Dependencies.shared.registerSingleton(type: LabelsRepository.self) { localLabels }

        let sync = SyncService(
            localTasksRepository: localTasks,
            remoteTasksRepository: FakeRemoteTasksRepository(),
            localLabelsRepository: localLabels,
            remoteLabelsRepository: FakeRemoteLabelsRepository(),
            syncStateStore: data.syncStateStore,
            localWorkingLogRepository: data.workingLogRepository,
            remoteWorkingLogRepository: FakeRemoteWorkingLogRepository()
        )

        defer { Dependencies.shared.reset() }

        let userId = TestFactories.userId(80)
        let templateId = UUID()
        var root = TestFactories.task(id: templateId, userId: userId, bucket: .routines, title: "Template Root")
        root.templateId = templateId
        root.parentTaskId = nil
        root.dueAt = nil
        root.dueHasTime = false
        try await localTasks.createTask(root)

        let cal = Calendar.current
        let now = Date()
        let nextMonday = WeekPlanner.nextMonday(after: now)
        var nextWeekChild = TestFactories.task(userId: userId, bucket: .routines, title: "Next Week Occurrence")
        nextWeekChild.templateId = templateId
        nextWeekChild.parentTaskId = templateId
        nextWeekChild.dueAt = nextMonday
        nextWeekChild.occurrenceDate = nextMonday
        try await localTasks.createTask(nextWeekChild)

        let thisWeekMonday = WeekPlanner.mondayOfCurrentWeek(for: now, calendar: cal)
        let thisWeekDue = cal.date(byAdding: .day, value: 2, to: thisWeekMonday) ?? thisWeekMonday
        var thisWeekChild = TestFactories.task(userId: userId, bucket: .routines, title: "This Week Occurrence")
        thisWeekChild.templateId = templateId
        thisWeekChild.parentTaskId = templateId
        thisWeekChild.dueAt = thisWeekDue
        thisWeekChild.occurrenceDate = cal.startOfDay(for: thisWeekDue)
        try await localTasks.createTask(thisWeekChild)

        let futureDue = cal.date(byAdding: .day, value: 20, to: now) ?? now
        var futureChild = TestFactories.task(userId: userId, bucket: .routines, title: "Future Occurrence")
        futureChild.templateId = templateId
        futureChild.parentTaskId = templateId
        futureChild.dueAt = futureDue
        futureChild.occurrenceDate = cal.startOfDay(for: futureDue)
        try await localTasks.createTask(futureChild)

        let moved = await sync.rebucketTemplateOccurrencesIfNeeded(userId: userId)
        XCTAssertEqual(moved, 2)

        let refreshedNextWeek = try await localTasks.fetchTask(by: nextWeekChild.id)
        XCTAssertEqual(refreshedNextWeek?.bucketKey, .nextWeek)

        let refreshedThisWeek = try await localTasks.fetchTask(by: thisWeekChild.id)
        XCTAssertEqual(refreshedThisWeek?.bucketKey, .thisWeek)

        let refreshedFuture = try await localTasks.fetchTask(by: futureChild.id)
        XCTAssertEqual(refreshedFuture?.bucketKey, .routines)
    }
}


