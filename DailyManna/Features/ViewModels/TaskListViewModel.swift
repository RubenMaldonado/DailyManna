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
    
    func toggleTaskCompletion(task: Task) async {
        do {
            try await taskUseCases.toggleTaskCompletion(id: task.id, userId: userId)
            // Re-fetch or update locally
            await fetchTasks()
        } catch {
            errorMessage = "Failed to toggle task completion: \(error.localizedDescription)"
            Logger.shared.error("Failed to toggle task completion", category: .ui, error: error)
        }
    }
    
    func addTask(title: String, description: String?, bucket: TimeBucket) async {
        let newTask = Task(userId: userId, bucketKey: bucket, title: title, description: description)
        do {
            try await taskUseCases.createTask(newTask)
            await fetchTasks()
        } catch {
            errorMessage = "Failed to add task: \(error.localizedDescription)"
            Logger.shared.error("Failed to add task", category: .ui, error: error)
        }
    }
    
    func deleteTask(task: Task) async {
        do {
            try await taskUseCases.deleteTask(by: task.id, for: userId)
            await fetchTasks()
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
        await fetchTasks()
    }
    
    func startPeriodicSync() {
        syncService?.startPeriodicSync(for: userId)
    }
}
