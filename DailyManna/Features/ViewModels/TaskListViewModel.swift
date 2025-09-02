//
//  TaskListViewModel.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published var tasksWithLabels: [(Task, [Label])] = []
    @Published var tasksWithRecurrence: Set<UUID> = []
    @Published var subtaskProgressByParent: [UUID: (completed: Int, total: Int)] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isSyncing: Bool = false
    @Published var selectedBucket: TimeBucket = .thisWeek
    @Published var bucketCounts: [TimeBucket: Int] = [:]
    @Published var showCompleted: Bool = false
    @Published var isPresentingTaskForm: Bool = false
    @Published var editingTask: Task? = nil
    @Published var pendingDelete: Task? = nil
    @Published var isBoardModeActive: Bool = false
    @AppStorage("sortByDueDate") private var sortByDueDate: Bool = false
    // Filtering
    @Published var activeFilterLabelIds: Set<UUID> = []
    @Published var matchAll: Bool = false
    @Published var unlabeledOnly: Bool = false
    
    private let taskUseCases: TaskUseCases
    private let labelUseCases: LabelUseCases
    private let syncService: SyncService?
    private let recurrenceUseCases: RecurrenceUseCases?
    let userId: UUID
    // Persist filter selection per user
    @AppStorage("labelFilter_Ids") private var persistedFilterIdsRaw: String = ""
    // Pending selections coming from TaskFormView (via NotificationCenter)
    private var pendingLabelSelections: [UUID: Set<UUID>] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var pendingRecurrenceSelections: [UUID: RecurrenceRule] = [:]
    
    init(taskUseCases: TaskUseCases, labelUseCases: LabelUseCases, userId: UUID, syncService: SyncService? = nil, recurrenceUseCases: RecurrenceUseCases? = nil) {
        self.taskUseCases = taskUseCases
        self.labelUseCases = labelUseCases
        self.userId = userId
        self.syncService = syncService
        self.recurrenceUseCases = recurrenceUseCases
        // Restore persisted filter ids
        if let restored = try? JSONDecoder().decode([UUID].self, from: Data(persistedFilterIdsRaw.utf8)) {
            self.activeFilterLabelIds = Set(restored)
        }

        // Listen for label selections from TaskForm
        NotificationCenter.default.addObserver(forName: Notification.Name("dm.taskform.labels.selection"), object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            guard let taskId = note.userInfo?["taskId"] as? UUID,
                  let ids = note.userInfo?["labelIds"] as? [UUID] else { return }
            _Concurrency.Task { @MainActor in
                self.pendingLabelSelections[taskId] = Set(ids)
            }
        }
        // Listen for recurrence selection from TaskForm
        NotificationCenter.default.addObserver(forName: Notification.Name("dm.taskform.recurrence.selection"), object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            guard let taskId = note.userInfo?["taskId"] as? UUID,
                  let data = note.userInfo?["ruleJSON"] as? Data,
                  let rule = try? JSONDecoder().decode(RecurrenceRule.self, from: data) else { return }
            _Concurrency.Task { @MainActor in
                self.pendingRecurrenceSelections[taskId] = rule
            }
        }
        
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
                        await self.fetchTasks(in: self.isBoardModeActive ? nil : self.selectedBucket)
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    func fetchTasks(in bucket: TimeBucket? = nil) async {
        isLoading = true
        errorMessage = nil
        do {
            var pairs = try await taskUseCases.fetchTasksWithLabels(for: userId, in: bucket)
            // Optional sort by due date
            if sortByDueDate {
                pairs.sort { lhs, rhs in
                    let lt = lhs.0
                    let rt = rhs.0
                    // Incomplete first
                    if lt.isCompleted != rt.isCompleted { return !lt.isCompleted && rt.isCompleted }
                    // Earliest due first; nils last
                    switch (lt.dueAt, rt.dueAt) {
                    case let (l?, r?): return l < r
                    case (nil, _?): return false
                    case (_?, nil): return true
                    default: return lt.position < rt.position
                    }
                }
            }
            // Apply unlabeled-only filter or label-based filter
            if unlabeledOnly {
                pairs = pairs.filter { $0.1.isEmpty }
            } else if activeFilterLabelIds.isEmpty == false {
                pairs = pairs.filter { pair in
                    let ids = Set(pair.1.map { $0.id })
                    return matchAll
                        ? ids.isSuperset(of: activeFilterLabelIds) // AND
                        : ids.intersection(activeFilterLabelIds).isEmpty == false // OR
                }
            }
            // Apply label filtering if any active
            self.tasksWithLabels = pairs
            await loadRecurrenceFlags(for: pairs.map { $0.0.id })
            // Load subtask progress for visible items incrementally
            let parentIds = pairs.map { $0.0.id }
            await loadSubtaskProgressIncremental(for: parentIds)
        } catch {
            errorMessage = "Failed to fetch tasks: \(error.localizedDescription)"
            Logger.shared.error("Failed to fetch tasks", category: .ui, error: error)
        }
        isLoading = false
    }

    private func loadRecurrenceFlags(for taskIds: [UUID]) async {
        guard let recUC = recurrenceUseCases else { return }
        do {
            let recs = try await recUC.list(for: userId)
            let ids = Set(recs.map { $0.taskTemplateId })
            await MainActor.run { self.tasksWithRecurrence = ids.intersection(taskIds) }
        } catch {
            // non-fatal
        }
    }

    func applyLabelFilter(selected: Set<UUID>, matchAll: Bool) {
        self.activeFilterLabelIds = selected
        self.matchAll = matchAll
        self.unlabeledOnly = false
        persistFilterIds()
        _Concurrency.Task {
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket)
        }
    }

    func applyUnlabeledFilter() {
        self.activeFilterLabelIds.removeAll()
        self.matchAll = false
        self.unlabeledOnly = true
        _Concurrency.Task {
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket)
        }
    }

    private func loadSubtaskProgressIncremental(for parentIds: [UUID]) async {
        await withTaskGroup(of: (UUID, (Int, Int)?).self) { group in
            for pid in parentIds {
                group.addTask { [taskUseCases] in
                    if let progress = try? await taskUseCases.getSubtaskProgress(parentTaskId: pid) {
                        return (pid, progress)
                    }
                    return (pid, nil)
                }
            }
            var map: [UUID: (Int, Int)] = [:]
            for await (pid, progress) in group {
                if let p = progress { map[pid] = p }
            }
            // Merge to preserve any cached values for tasks still off-screen
            self.subtaskProgressByParent.merge(map) { _, new in new }
        }
    }

    func clearFilters() {
        activeFilterLabelIds.removeAll()
        matchAll = false
        unlabeledOnly = false
        _Concurrency.Task { await fetchTasks(in: isBoardModeActive ? nil : selectedBucket) }
        persistFilterIds()
    }

    func select(bucket: TimeBucket) {
        selectedBucket = bucket
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            async let fetch: Void = self.fetchTasks(in: bucket)
            async let counts: Void = self.refreshCounts()
            _ = await (fetch, counts)
        }
    }

    private func persistFilterIds() {
        if let data = try? JSONEncoder().encode(Array(activeFilterLabelIds)) {
            persistedFilterIdsRaw = String(decoding: data, as: UTF8.self)
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
        await toggleTaskCompletion(task: task, refreshIn: isBoardModeActive ? nil : selectedBucket)
    }

    func toggleTaskCompletion(task: Task, refreshIn filter: TimeBucket?) async {
        do {
            if let progress = subtaskProgressByParent[task.id], progress.total > 0 {
                try await taskUseCases.toggleParentCompletionCascade(parentId: task.id)
            } else {
                try await taskUseCases.toggleTaskCompletion(id: task.id, userId: userId)
            }
            await refreshCounts()
            await fetchTasks(in: filter)
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
                if let due = updated.dueAt, !updated.isCompleted {
                    await NotificationsManager.scheduleDueNotification(taskId: updated.id, title: updated.title, dueAt: due, bucketKey: updated.bucketKey.rawValue)
                } else {
                    await NotificationsManager.cancelDueNotification(taskId: updated.id)
                }
                // Persist label selections if available
                if let desired = pendingLabelSelections[updated.id] {
                    try await taskUseCases.setLabels(for: updated.id, to: desired, userId: userId)
                    pendingLabelSelections.removeValue(forKey: updated.id)
                }
                // Apply recurrence if selected
                if let rule = pendingRecurrenceSelections[updated.id], let recUC = recurrenceUseCases {
                    let recurrence = Recurrence(userId: userId, taskTemplateId: updated.id, rule: rule)
                    try? await recUC.create(recurrence)
                    pendingRecurrenceSelections.removeValue(forKey: updated.id)
                }
            } else {
                let newTask = draft.toNewTask()
                try await taskUseCases.createTask(newTask)
                if let due = newTask.dueAt {
                    await NotificationsManager.scheduleDueNotification(taskId: newTask.id, title: newTask.title, dueAt: due, bucketKey: newTask.bucketKey.rawValue)
                }
                if let desired = pendingLabelSelections[newTask.id] {
                    try await taskUseCases.setLabels(for: newTask.id, to: desired, userId: userId)
                    pendingLabelSelections.removeValue(forKey: newTask.id)
                }
                if let rule = pendingRecurrenceSelections[newTask.id], let recUC = recurrenceUseCases {
                    let recurrence = Recurrence(userId: userId, taskTemplateId: newTask.id, rule: rule)
                    try? await recUC.create(recurrence)
                    pendingRecurrenceSelections.removeValue(forKey: newTask.id)
                }
            }
            await refreshCounts()
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket)
        } catch {
            errorMessage = "Failed to save task: \(error.localizedDescription)"
            Logger.shared.error("Failed to save task", category: .ui, error: error)
        }
    }

    private func persistLabelSelections(taskId: UUID) async {}

    func confirmDelete(_ task: Task) {
        pendingDelete = task
    }
    
    func performDelete() async {
        guard let task = pendingDelete else { return }
        pendingDelete = nil
        await deleteTask(task: task)
        await refreshCounts()
    }

    func performDelete(refreshIn filter: TimeBucket?) async {
        guard let task = pendingDelete else { return }
        pendingDelete = nil
        do {
            try await taskUseCases.deleteTask(by: task.id, for: userId)
            await refreshCounts()
            await fetchTasks(in: isBoardModeActive ? nil : filter)
        } catch {
            errorMessage = "Failed to delete task: \(error.localizedDescription)"
            Logger.shared.error("Failed to delete task", category: .ui, error: error)
        }
    }
    
    func move(taskId: UUID, to bucket: TimeBucket) async {
        // Backward-compatible: refresh current list bucket
        await move(taskId: taskId, to: bucket, refreshIn: isBoardModeActive ? nil : selectedBucket)
    }

    /// Move task and refresh using a specific filter. Pass `nil` to refresh all buckets (board view).
    func move(taskId: UUID, to bucket: TimeBucket, refreshIn filter: TimeBucket?) async {
        do {
            try await taskUseCases.moveTask(id: taskId, to: bucket, for: userId)
            await refreshCounts()
            await fetchTasks(in: filter)
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
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket)
        } catch {
            errorMessage = "Failed to add task: \(error.localizedDescription)"
            Logger.shared.error("Failed to add task", category: .ui, error: error)
        }
    }
    
    func deleteTask(task: Task) async {
        do {
            try await taskUseCases.deleteTask(by: task.id, for: userId)
            await refreshCounts()
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket)
        } catch {
            errorMessage = "Failed to delete task: \(error.localizedDescription)"
            Logger.shared.error("Failed to delete task", category: .ui, error: error)
        }
    }
    
    /// Optimistically move a task locally to a new bucket to avoid snap-back animations in board view.
    func optimisticMoveLocal(taskId: UUID, to bucket: TimeBucket) {
        guard let index = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) else { return }
        var pair = tasksWithLabels[index]
        let oldBucket = pair.0.bucketKey
        guard oldBucket != bucket else { return }
        pair.0.bucketKey = bucket
        // Reset position locally; actual position will be set by reorder logic
        pair.0.position = 0
        tasksWithLabels[index] = pair
        // Update counts optimistically
        if let old = bucketCounts[oldBucket], old > 0 { bucketCounts[oldBucket] = old - 1 }
        bucketCounts[bucket] = (bucketCounts[bucket] ?? 0) + 1
    }

    /// Reorder within a bucket or across buckets: compute position by neighbor midpoints.
    func reorder(taskId: UUID, to bucket: TimeBucket, targetIndex: Int) async {
        // Build arrays per bucket, with incomplete tasks only for ordering
        var columns: [TimeBucket: [(Task, [Label])]] = [:]
        for (t, ls) in tasksWithLabels {
            let key = t.bucketKey
            columns[key, default: []].append((t, ls))
        }
        // Filter out completed for ordering calculations
        func incomplete(_ arr: [(Task, [Label])]) -> [(Task, [Label])] { arr.filter { !$0.0.isCompleted } }
        let sourceBucket = tasksWithLabels.first(where: { $0.0.id == taskId })?.0.bucketKey
        guard let source = sourceBucket else { return }

        var sourceArr = incomplete(columns[source] ?? [])
        var destArr = incomplete(columns[bucket] ?? [])

        // Extract the task
        guard let srcIdx = sourceArr.firstIndex(where: { $0.0.id == taskId }) else { return }
        let moving = sourceArr.remove(at: srcIdx)
        let clampedIndex = max(0, min(targetIndex, destArr.count))
        destArr.insert(moving, at: clampedIndex)

        // Compute new position using neighbors (stride 1024)
        let stride: Double = 1024
        func positionFor(index: Int, in arr: [(Task, [Label])]) -> Double {
            if arr.isEmpty { return stride }
            if index == 0 { return (arr.first!.0.position - stride).rounded() }
            if index >= arr.count - 1 { return (arr.last!.0.position + stride).rounded() }
            let prev = arr[index - 1].0.position
            let next = arr[index + 1].0.position
            let mid = (prev + next) / 2
            return mid
        }

        let newPos = positionFor(index: clampedIndex, in: destArr)

        // Optimistically update local state list and reorder array within the destination bucket
        guard let currentGlobalIdx = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) else { return }
        var movingPair = tasksWithLabels.remove(at: currentGlobalIdx)
        movingPair.0.bucketKey = bucket
        movingPair.0.position = newPos

        // Build global insertion point relative to incomplete items in destination bucket
        let destIncompleteEnumerated = tasksWithLabels
            .enumerated()
            .filter { $0.element.0.bucketKey == bucket && $0.element.0.isCompleted == false }
            .map { (idx: $0.offset, task: $0.element.0) }

        let globalInsertIdx: Int = {
            if clampedIndex <= 0 { return destIncompleteEnumerated.first?.idx ?? tasksWithLabels.endIndex }
            if clampedIndex >= destIncompleteEnumerated.count { return (destIncompleteEnumerated.last?.idx ?? (tasksWithLabels.endIndex - 1)) + 1 }
            return destIncompleteEnumerated[clampedIndex].idx
        }()

        tasksWithLabels.insert(movingPair, at: min(globalInsertIdx, tasksWithLabels.count))

        // Persist remotely
        do {
            try await taskUseCases.updateTaskOrderAndBucket(id: taskId, to: bucket, position: newPos, userId: userId)
        } catch {
            errorMessage = "Failed to reorder: \(error.localizedDescription)"
            Logger.shared.error("Failed to reorder task", category: .ui, error: error)
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
        await fetchTasks(in: isBoardModeActive ? nil : selectedBucket)
    }
    
    func startPeriodicSync() {
        syncService?.startPeriodicSync(for: userId)
    }
    
    func initialSyncIfNeeded() async {
        guard let syncService = syncService else { return }
        await syncService.performInitialSync(for: userId)
    }
}
