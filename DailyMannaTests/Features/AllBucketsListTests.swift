import XCTest
@testable import DailyManna

@MainActor
final class AllBucketsListTests: XCTestCase {
    func makeViewModel(user: UUID) throws -> TaskListViewModel {
        let deps = Dependencies.shared
        let tasksRepo: TasksRepository = try deps.resolve(type: TasksRepository.self)
        let labelsRepo: LabelsRepository = try deps.resolve(type: LabelsRepository.self)
        let sync: SyncService? = try? deps.resolve(type: SyncService.self)
        return TaskListViewModel(taskUseCases: TaskUseCases(tasksRepository: tasksRepo, labelsRepository: labelsRepo), labelUseCases: LabelUseCases(labelsRepository: labelsRepo), userId: user, syncService: sync)
    }

    func testFetchAllBuckets_appliesGlobalFilters() async throws {
        let user = TestFactories.userId(101)
        let vm = try makeViewModel(user: user)
        // Seed tasks across buckets
        let deps = Dependencies.shared
        let tasksRepo: TasksRepository = try deps.resolve(type: TasksRepository.self)
        let labelRepo: LabelsRepository = try deps.resolve(type: LabelsRepository.self)
        let l1 = Label(userId: user, name: "Blue", color: "#0000FF")
        try await labelRepo.createLabel(l1)
        let t1 = Task(userId: user, bucketKey: .thisWeek, title: "A")
        let t2 = Task(userId: user, bucketKey: .nextWeek, title: "B")
        try await tasksRepo.createTask(t1)
        try await tasksRepo.createTask(t2)
        // assign label to t2 only
        let useCases = TaskUseCases(tasksRepository: tasksRepo, labelsRepository: labelRepo)
        try await useCases.setLabels(for: t2.id, to: [l1.id], userId: user)

        vm.isBoardModeActive = true
        await vm.fetchTasks(in: nil)
        XCTAssertEqual(vm.tasksWithLabels.count, 2)
        vm.applyLabelFilter(selected: [l1.id], matchAll: false)
        // allow async refresh
        try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.tasksWithLabels.count, 1)
        XCTAssertEqual(vm.tasksWithLabels.first?.0.id, t2.id)
    }

    func testReorderAcrossBuckets_movesBucket() async throws {
        let user = TestFactories.userId(102)
        let vm = try makeViewModel(user: user)
        let deps = Dependencies.shared
        let tasksRepo: TasksRepository = try deps.resolve(type: TasksRepository.self)
        let t1 = Task(userId: user, bucketKey: .thisWeek, position: 0, title: "A")
        let t2 = Task(userId: user, bucketKey: .nextWeek, position: 0, title: "B")
        try await tasksRepo.createTask(t1)
        try await tasksRepo.createTask(t2)
        vm.isBoardModeActive = true
        await vm.fetchTasks(in: nil)
        await vm.reorder(taskId: t1.id, to: .nextWeek, targetIndex: 0)
        // refresh
        await vm.fetchTasks(in: nil, showLoading: false)
        let moved = try await tasksRepo.fetchTask(by: t1.id)
        XCTAssertEqual(moved?.bucketKey, .nextWeek)
    }

    func testThisWeekSections_grouping() async throws {
        let user = TestFactories.userId(103)
        let vm = try makeViewModel(user: user)
        vm.featureThisWeekSectionsEnabled = true
        vm.selectedBucket = .thisWeek
        // Seed tasks for today and a future weekday
        let deps = Dependencies.shared
        let tasksRepo: TasksRepository = try deps.resolve(type: TasksRepository.self)
        let today = Calendar.current.startOfDay(for: Date())
        let thursday = Calendar.current.date(byAdding: .day, value: 3, to: today)!
        var a = Task(userId: user, bucketKey: .thisWeek, title: "Today", dueAt: today)
        a.dueHasTime = false
        var b = Task(userId: user, bucketKey: .thisWeek, title: "Thu", dueAt: thursday)
        b.dueHasTime = false
        try await tasksRepo.createTask(a)
        try await tasksRepo.createTask(b)
        await vm.fetchTasks(in: .thisWeek)
        XCTAssertFalse(vm.thisWeekSections.isEmpty)
        XCTAssertTrue(vm.tasksByDayKey.values.contains { pairs in pairs.contains { $0.0.title == "Today" } })
    }
}


