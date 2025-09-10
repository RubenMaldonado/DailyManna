import XCTest
@testable import DailyManna

final class TaskListViewModelSectionsTests: XCTestCase {
    func makeViewModel() throws -> TaskListViewModel {
        let deps = Dependencies.shared
        let tasksRepo: TasksRepository = try deps.resolve(type: TasksRepository.self)
        let labelsRepo: LabelsRepository = try deps.resolve(type: LabelsRepository.self)
        let sync: SyncService? = try? deps.resolve(type: SyncService.self)
        let useCases = TaskUseCases(tasksRepository: tasksRepo, labelsRepository: labelsRepo)
        return TaskListViewModel(taskUseCases: useCases, labelUseCases: LabelUseCases(labelsRepository: labelsRepo), userId: UUID(), syncService: sync)
    }

    func testSchedulePreservesTime_WhenDueHasTime() async throws {
        let vm = try makeViewModel()
        vm.featureThisWeekSectionsEnabled = true
        let user = vm.userId
        // Build a task due today at 15:30
        let cal = Calendar.current
        let now = Date()
        var dcomps = cal.dateComponents([.year,.month,.day], from: now)
        dcomps.hour = 15; dcomps.minute = 30
        let due = cal.date(from: dcomps)!
        var task = Task(userId: user, bucketKey: .thisWeek, title: "T1", dueAt: due, dueHasTime: true)
        // Create via repository directly
        let repo: TasksRepository = try Dependencies.shared.resolve(type: TasksRepository.self)
        try await repo.createTask(task)
        // Act: move to tomorrow
        let target = cal.date(byAdding: .day, value: 1, to: now)!
        await vm.schedule(taskId: task.id, to: target)
        let updated = try await repo.fetchTask(by: task.id)
        XCTAssertNotNil(updated)
        let updatedDue = updated!.dueAt!
        // Hour/minute should remain 15:30 but date should be tomorrow
        let up = cal.dateComponents([.year,.month,.day,.hour,.minute], from: updatedDue)
        let tgt = cal.dateComponents([.year,.month,.day], from: target)
        XCTAssertEqual(up.year, tgt.year)
        XCTAssertEqual(up.month, tgt.month)
        XCTAssertEqual(up.day, tgt.day)
        XCTAssertEqual(up.hour, 15)
        XCTAssertEqual(up.minute, 30)
    }

    func testUnscheduleClearsDueDate() async throws {
        let vm = try makeViewModel()
        vm.featureThisWeekSectionsEnabled = true
        let user = vm.userId
        // Create a task with a due date in This Week
        let cal = Calendar.current
        let due = cal.date(byAdding: .day, value: 1, to: Date())!
        var task = Task(userId: user, bucketKey: .thisWeek, title: "T2", dueAt: due, dueHasTime: false)
        let repo: TasksRepository = try Dependencies.shared.resolve(type: TasksRepository.self)
        try await repo.createTask(task)
        // Wire VM list
        await vm.fetchTasks(in: .thisWeek)
        // Act
        await vm.unschedule(taskId: task.id)
        let updated = try await repo.fetchTask(by: task.id)
        XCTAssertNotNil(updated)
        XCTAssertNil(updated!.dueAt)
        XCTAssertEqual(updated!.bucketKey, .thisWeek)
    }
}


