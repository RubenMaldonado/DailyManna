//
//  SoakTestHarness.swift
//  DailyManna
//
//  Debug-only harness to generate background activity that simulates
//  real usage: periodic syncs, task creations, moves, label churn.
//

import Foundation

@MainActor
final class SoakTestHarness: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    private var task: _Concurrency.Task<Void, Never>? = nil

    private let userId: UUID
    private let syncService: SyncService
    private let taskUseCases: TaskUseCases
    private let labelUseCases: LabelUseCases

    init(userId: UUID, syncService: SyncService, taskUseCases: TaskUseCases, labelUseCases: LabelUseCases) {
        self.userId = userId
        self.syncService = syncService
        self.taskUseCases = taskUseCases
        self.labelUseCases = labelUseCases
    }

    func start() {
        guard isRunning == false else { return }
        isRunning = true
        task = _Concurrency.Task { [weak self] in
            await self?.run()
        }
        Logger.shared.info("Soak harness started", category: .perf)
    }

    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        Logger.shared.info("Soak harness stopped", category: .perf)
    }

    private func randomTitle() -> String {
        let verbs = ["Plan", "Draft", "Polish", "Review", "Refactor", "Test", "Ship"]
        let nouns = ["feature", "design", "migration", "query", "recurrence", "labeling", "sync"]
        return "\(verbs.randomElement()!) \(nouns.randomElement()!) \(Int.random(in: 1...999))"
    }

    private func randomBucket() -> TimeBucket { TimeBucket.allCases.randomElement() ?? .thisWeek }

    private func randomDueDate() -> Date? {
        if Bool.random() == false { return nil }
        let delta = TimeInterval(Int.random(in: -86_400...86_400))
        return Date().addingTimeInterval(delta)
    }

    private func randomDelay() -> UInt64 {
        // Between 0.5s and 2.5s
        let seconds = Double.random(in: 0.5...2.5)
        return UInt64(seconds * 1_000_000_000)
    }

    private func randomSmallDelay() -> UInt64 {
        let seconds = Double.random(in: 0.2...0.6)
        return UInt64(seconds * 1_000_000_000)
    }

    private func jitterSync() async {
        await syncService.sync(for: userId)
    }

    private func createRandomTask() async {
        let t = Task(
            userId: userId,
            bucketKey: randomBucket(),
            title: randomTitle(),
            description: Bool.random() ? "Autogen task" : nil,
            dueAt: randomDueDate()
        )
        try? await taskUseCases.createTask(t)
        if let due = t.dueAt {
            await NotificationsManager.scheduleDueNotification(taskId: t.id, title: t.title, dueAt: due, bucketKey: t.bucketKey.rawValue)
        }
    }

    private func moveRandomTask() async {
        guard let pairs = try? await taskUseCases.fetchTasksWithLabels(for: userId, in: nil), pairs.isEmpty == false else { return }
        let incomplete = pairs.map { $0.0 }.filter { $0.isCompleted == false }
        guard let pick = incomplete.randomElement() else { return }
        let newBucket = randomBucket()
        if newBucket != pick.bucketKey {
            try? await taskUseCases.moveTask(id: pick.id, to: newBucket, for: userId)
        }
    }

    private func toggleRandomCompletion() async {
        guard let pairs = try? await taskUseCases.fetchTasksWithLabels(for: userId, in: nil), pairs.isEmpty == false else { return }
        guard let pick = pairs.map({ $0.0 }).randomElement() else { return }
        try? await taskUseCases.toggleTaskCompletion(id: pick.id, userId: userId)
    }

    private func churnLabels() async {
        // Create a small set of labels and randomly assign to tasks
        let palette = ["#EA4335", "#FBBC05", "#34A853", "#4285F4", "#A142F4"]
        let existing = (try? await labelUseCases.fetchLabels(for: userId)) ?? []
        if existing.count < 3 {
            let name = "L\(Int.random(in: 1...999))"
            let color = palette.randomElement() ?? "#4285F4"
            let l = Label(userId: userId, name: name, color: color)
            try? await labelUseCases.createLabel(l)
        }

        let labels = (try? await labelUseCases.fetchLabels(for: userId)) ?? []
        guard labels.isEmpty == false else { return }
        guard let pairs = try? await taskUseCases.fetchTasksWithLabels(for: userId, in: nil) else { return }
        for (t, _) in pairs.shuffled().prefix(3) {
            var set = Set<UUID>()
            for lab in labels.shuffled().prefix(Int.random(in: 0...min(2, labels.count))) {
                set.insert(lab.id)
            }
            try? await labelUseCases.setLabels(for: t.id, to: set, userId: userId)
        }
    }

    private func run() async {
        while isRunning && _Concurrency.Task.isCancelled == false {
            // Randomly pick an action
            let roll = Int.random(in: 0...9)
            switch roll {
            case 0:
                await jitterSync()
            case 1:
                await createRandomTask()
            case 2:
                await moveRandomTask()
            case 3:
                await toggleRandomCompletion()
            case 4:
                await churnLabels()
            default:
                break
            }

            try? await _Concurrency.Task.sleep(nanoseconds: randomDelay())
        }
    }
}


