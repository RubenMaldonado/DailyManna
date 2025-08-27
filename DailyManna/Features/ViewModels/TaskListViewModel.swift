//
//  TaskListViewModel.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Combine

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published var tasksWithLabels: [(Task, [Label])] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isSyncing: Bool = false
    @Published var selectedBucket: TimeBucket = .thisWeek
    @Published var bucketCounts: [TimeBucket: Int] = [:]
    @Published var showCompleted: Bool = false
    @Published var isPresentingTaskForm: Bool = false
    @Published var editingTask: Task? = nil
    @Published var pendingDelete: Task? = nil
    
    private let taskUseCases: TaskUseCases
    private let labelUseCases: LabelUseCases
    private let syncService: SyncService?
    private let userId: UUID
    private var cancellables: Set<AnyCancellable> = []
    
    init(taskUseCases: TaskUseCases, labelUseCases: LabelUseCases, userId: UUID, syncService: SyncService? = nil) {
        self.taskUseCases = taskUseCases
        self.labelUseCases = labelUseCases
        self.userId = userId
        self.syncService = syncService
        
        // Start observing sync state if available (Combine to avoid Task name clash)
        if let syncService = syncService {
            syncService.$isSyncing
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    self?.isSyncing = value
                }
                .store(in: &cancellables)
            // Refresh lists whenever a sync cycle finishes successfully
            syncService.$lastSyncDate
                .removeDuplicates()
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    _Concurrency.Task {
                        await self.refreshCounts()
                        await self.fetchTasks(in: self.selectedBucket)
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    func fetchTasks(in bucket: TimeBucket? = nil) async {
        isLoading = true
        errorMessage = nil
        do {
            self.tasksWithLabels = try await taskUseCases.fetchTasksWithLabels(for: userId, in: bucket)
        } catch {
            errorMessage = "Failed to fetch tasks: \(error.localizedDescription)"
            Logger.shared.error("Failed to fetch tasks", category: .ui, error: error)
        }
        isLoading = false
    }

    func select(bucket: TimeBucket) {
        selectedBucket = bucket
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            async let _ = self.fetchTasks(in: bucket)
            async let _ = self.refreshCounts()
            _ = await ()
        }
    }

    func refreshCounts() async {
        var counts: [TimeBucket: Int] = [:]
        await withTaskGroup(of: (TimeBucket, Int).self) { group in
            for bucket in TimeBucket.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                group.addTask { [userId, taskUseCases, showCompleted] in
                    let count = (try? await taskUseCases.countTasks(for: userId, in: bucket, includeCompleted: showCompleted)) ?? 0
                    return (bucket, count)
                }
            }
            for await (bucket, count) in group {
                counts[bucket] = count
            }
        }
        await MainActor.run {
            self.bucketCounts = counts
        }
    }
    
    func toggleTaskCompletion(task: Task) async {
        do {
            try await taskUseCases.toggleTaskCompletion(id: task.id, userId: userId)
            // Re-fetch or update locally
            await refreshCounts()
            await fetchTasks(in: selectedBucket)
        } catch {
            errorMessage = "Failed to toggle task completion: \(error.localizedDescription)"
            Logger.shared.error("Failed to toggle task completion", category: .ui, error: error)
        }
    }
    
    func presentCreateForm() {
        editingTask = nil
        isPresentingTaskForm = true
    }
    
    func presentEditForm(task: Task) {
        editingTask = task
        isPresentingTaskForm = true
    }
    
    func save(draft: TaskDraft) async {
        do {
            if let editing = editingTask {
                let updated = draft.applying(to: editing)
                try await taskUseCases.updateTask(updated)
            } else {
                let newTask = draft.toNewTask()
                try await taskUseCases.createTask(newTask)
            }
            await refreshCounts()
            await fetchTasks(in: selectedBucket)
        } catch {
            errorMessage = "Failed to save task: \(error.localizedDescription)"
            Logger.shared.error("Failed to save task", category: .ui, error: error)
        }
    }

    func confirmDelete(_ task: Task) {
        pendingDelete = task
    }
    
    func performDelete() async {
        guard let task = pendingDelete else { return }
        pendingDelete = nil
        await deleteTask(task: task)
        await refreshCounts()
    }
    
    func move(taskId: UUID, to bucket: TimeBucket) async {
        do {
            try await taskUseCases.moveTask(id: taskId, to: bucket, for: userId)
            await refreshCounts()
            await fetchTasks(in: selectedBucket)
        } catch {
            errorMessage = "Failed to move task: \(error.localizedDescription)"
            Logger.shared.error("Failed to move task", category: .ui, error: error)
        }
    }

    func addTask(title: String, description: String?, bucket: TimeBucket) async {
        let newTask = Task(userId: userId, bucketKey: bucket, title: title, description: description)
        do {
            try await taskUseCases.createTask(newTask)
            await refreshCounts()
            await fetchTasks(in: selectedBucket)
        } catch {
            errorMessage = "Failed to add task: \(error.localizedDescription)"
            Logger.shared.error("Failed to add task", category: .ui, error: error)
        }
    }
    
    func deleteTask(task: Task) async {
        do {
            try await taskUseCases.deleteTask(by: task.id, for: userId)
            await refreshCounts()
            await fetchTasks(in: selectedBucket)
        } catch {
            errorMessage = "Failed to delete task: \(error.localizedDescription)"
            Logger.shared.error("Failed to delete task", category: .ui, error: error)
        }
    }
    
    func sync() async {
        guard let syncService = syncService else {
            Logger.shared.info("No sync service available", category: .ui)
            return
        }
        
        await syncService.sync(for: userId)
        // Refresh tasks after sync
        await refreshCounts()
        await fetchTasks(in: selectedBucket)
    }
    
    func startPeriodicSync() {
        syncService?.startPeriodicSync(for: userId)
    }
    
    func initialSyncIfNeeded() async {
        guard let syncService = syncService else { return }
        await syncService.performInitialSync(for: userId)
    }
}
