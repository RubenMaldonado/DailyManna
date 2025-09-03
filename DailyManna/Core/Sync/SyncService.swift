//
//  SyncService.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Combine

@MainActor
final class SyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?
    
    private let localTasksRepository: TasksRepository
    private let remoteTasksRepository: RemoteTasksRepository
    private let localLabelsRepository: LabelsRepository
    private let remoteLabelsRepository: RemoteLabelsRepository
    private let syncStateStore: SyncStateStore
    private var realtimeObserver: NSObjectProtocol?
    private var realtimeDebounceScheduled = false
    private var currentUserId: UUID?
    
    init(
        localTasksRepository: TasksRepository,
        remoteTasksRepository: RemoteTasksRepository,
        localLabelsRepository: LabelsRepository,
        remoteLabelsRepository: RemoteLabelsRepository,
        syncStateStore: SyncStateStore
    ) {
        self.localTasksRepository = localTasksRepository
        self.remoteTasksRepository = remoteTasksRepository
        self.localLabelsRepository = localLabelsRepository
        self.remoteLabelsRepository = remoteLabelsRepository
        self.syncStateStore = syncStateStore
    }
    
    private var periodicCancellable: AnyCancellable?
    
    /// Performs a full bidirectional sync for a specific user
    func sync(for userId: UUID) async {
        // Single-flight with queued rerun
        struct Flags { static var rerunRequested = false }
        if isSyncing {
            Flags.rerunRequested = true
            Logger.shared.info("Sync already in progress, queueing rerun", category: .sync)
            return
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            Logger.shared.info("Starting sync operation", category: .sync)
            
            // Sync tasks
            try await withRetry { [weak self] in
                guard let self else { return }
                try await self.syncTasks(userId: userId)
            }
            
            // Sync labels
            try await withRetry { [weak self] in
                guard let self else { return }
                try await self.syncLabels(userId: userId)
            }

            // Recurrences (pull + catch-up)
            try await withRetry { [weak self] in
                guard let self else { return }
                try await self.syncRecurrences(userId: userId)
            }
            try await withRetry { [weak self] in
                guard let self else { return }
                await self.catchUpRecurrencesIfNeeded(userId: userId)
            }
            
            lastSyncDate = Date()
            Logger.shared.info("Sync completed successfully", category: .sync)
            
        } catch {
            Logger.shared.error("Sync failed", category: .sync, error: error)
            syncError = error
        }
        
        isSyncing = false
        if Flags.rerunRequested {
            Flags.rerunRequested = false
            _Concurrency.Task { await self.sync(for: userId) }
        }
    }
    
    /// Syncs tasks bidirectionally
    private func syncTasks(userId: UUID) async throws {
        // Resolve checkpoints
        let checkpoints = try await syncStateStore.loadSnapshot(userId: userId)
        
        // 1. Push local changes to remote
        // Prefer targeted fetch for items needing sync
        let tasksNeedingSync = (try? await localTasksRepository.fetchTasksNeedingSync(for: userId)) ?? []
        
        if !tasksNeedingSync.isEmpty {
            Logger.shared.info("Pushing \(tasksNeedingSync.count) local task changes", category: .sync)
            let syncedTasks = try await remoteTasksRepository.syncTasks(tasksNeedingSync)
            
            // Update local tasks with remote data
            for syncedTask in syncedTasks {
                var updatedTask = syncedTask
                updatedTask.needsSync = false
                try await localTasksRepository.updateTask(updatedTask)
            }
        }
        
        // 2. Pull remote changes (delta)
        // Determine if local store is empty to bootstrap with full sync
        let localAll = try await localTasksRepository.fetchTasks(for: userId, in: nil)
        let isColdStart = localAll.isEmpty
        // Add small overlap to heal clock skew or missed events
        let sinceBase = checkpoints?.lastTasksSyncAt ?? lastSyncDate
        let since = isColdStart ? nil : sinceBase?.addingTimeInterval(-120)
        var remoteTasks = try await remoteTasksRepository.fetchTasks(since: since)
        // Fallback: if we expected deltas but got nothing on an empty store, fetch all
        if remoteTasks.isEmpty && isColdStart && since != nil {
            remoteTasks = try await remoteTasksRepository.fetchTasks(since: nil)
        }
        
        if !remoteTasks.isEmpty {
            Logger.shared.info("Pulling \(remoteTasks.count) remote task changes", category: .sync)
            
            for remoteTask in remoteTasks {
                do {
                    // Check if task exists locally
                    if let existingTask = try await localTasksRepository.fetchTask(by: remoteTask.id) {
                        // Apply conflict resolution (last-write-wins for now)
                        if remoteTask.updatedAt > existingTask.updatedAt {
                            var taskToUpdate = remoteTask
                            taskToUpdate.needsSync = false
                            try await localTasksRepository.updateTask(taskToUpdate)
                        }
                    } else {
                        // Create new local task
                        var newTask = remoteTask
                        newTask.needsSync = false
                        try await localTasksRepository.createTask(newTask)
                    }
                } catch {
                    Logger.shared.error("Failed to sync task \(remoteTask.id)", category: .sync, error: error)
                }
            }
        }
        // Update checkpoint using server-sourced timestamps to avoid device clock skew
        if let maxServerUpdated = remoteTasks.map({ $0.updatedAt }).max() {
            try await syncStateStore.updateTasksCheckpoint(userId: userId, to: maxServerUpdated)
        }
    }
    
    /// Syncs labels bidirectionally
    private func syncLabels(userId: UUID) async throws {
        // Resolve checkpoints
        let checkpoints = try await syncStateStore.loadSnapshot(userId: userId)
        
        // 1. Push local changes to remote
        // Prefer targeted fetch for items needing sync
        let labelsNeedingSync = (try? await localLabelsRepository.fetchLabelsNeedingSync(for: userId)) ?? []
        
        if !labelsNeedingSync.isEmpty {
            Logger.shared.info("Pushing \(labelsNeedingSync.count) local label changes", category: .sync)
            let syncedLabels = try await remoteLabelsRepository.syncLabels(labelsNeedingSync)
            
            // Update local labels with remote data
            for syncedLabel in syncedLabels {
                var updatedLabel = syncedLabel
                updatedLabel.needsSync = false
                try await localLabelsRepository.updateLabel(updatedLabel)
            }
        }
        
        // 2. Pull remote changes (delta)
        // Bootstrap labels as well if local store has none
        let localLabelsAll = try await localLabelsRepository.fetchLabels(for: userId)
        let isColdStartLabels = localLabelsAll.isEmpty
        let sinceBaseL = checkpoints?.lastLabelsSyncAt ?? lastSyncDate
        let sinceL = isColdStartLabels ? nil : sinceBaseL?.addingTimeInterval(-120)
        var remoteLabels = try await remoteLabelsRepository.fetchLabels(since: sinceL)
        if remoteLabels.isEmpty && isColdStartLabels && sinceL != nil {
            remoteLabels = try await remoteLabelsRepository.fetchLabels(since: nil)
        }
        
        if !remoteLabels.isEmpty {
            Logger.shared.info("Pulling \(remoteLabels.count) remote label changes", category: .sync)
            
            for remoteLabel in remoteLabels {
                do {
                    // Check if label exists locally
                    if let existingLabel = try await localLabelsRepository.fetchLabel(by: remoteLabel.id) {
                        // Apply conflict resolution (last-write-wins for now)
                        if remoteLabel.updatedAt > existingLabel.updatedAt {
                            var labelToUpdate = remoteLabel
                            labelToUpdate.needsSync = false
                            try await localLabelsRepository.updateLabel(labelToUpdate)
                        }
                    } else {
                        // Create new local label
                        var newLabel = remoteLabel
                        newLabel.needsSync = false
                        try await localLabelsRepository.createLabel(newLabel)
                    }
                } catch {
                    Logger.shared.error("Failed to sync label \(remoteLabel.id)", category: .sync, error: error)
                }
            }
        }
        if let maxServerUpdated = remoteLabels.map({ $0.updatedAt }).max() {
            try await syncStateStore.updateLabelsCheckpoint(userId: userId, to: maxServerUpdated)
        }

        // 3a. Push local task-label link changes
        let pendingLinks = (try? await localLabelsRepository.fetchTaskLabelLinksNeedingSync(for: userId)) ?? []
        if !pendingLinks.isEmpty {
            Logger.shared.info("Pushing \(pendingLinks.count) task-label link changes", category: .sync)
            for link in pendingLinks {
                if link.deletedAt == nil {
                    try await remoteLabelsRepository.link(link)
                } else {
                    try await remoteLabelsRepository.unlink(taskId: link.taskId, labelId: link.labelId)
                }
                try await localLabelsRepository.markTaskLabelLinkSynced(taskId: link.taskId, labelId: link.labelId)
            }
        }

        // 3b. Pull task-label links (junction) - delta
        let sinceLinks = isColdStartLabels ? nil : sinceL
        let remoteLinks = try await remoteLabelsRepository.fetchTaskLabelLinks(since: sinceLinks)
        if !remoteLinks.isEmpty {
            Logger.shared.info("Pulling \(remoteLinks.count) remote task-label link changes", category: .sync)
            for link in remoteLinks {
                try await localLabelsRepository.upsertTaskLabelLink(link)
            }
        }
    }

    // MARK: - Recurrences (pull-only v1; app creates/updates eagerly)
    private func syncRecurrences(userId: UUID) async throws {
        // Pull-only for v1: refresh recurrence flags by reading server rows
        // This assumes RecurrenceUseCases local repo is always updated when user edits locally.
        do {
            let deps = Dependencies.shared
            let recUC = try deps.resolve(type: RecurrenceUseCases.self)
            _ = try await recUC.list(for: userId) // trigger local cache refresh if remote repo used elsewhere
        } catch {
            Logger.shared.error("Failed to sync recurrences", category: .sync, error: error)
        }
    }

    /// Generate missed instances if next_scheduled_at is in the past (single step catch-up per recurrence)
    private func catchUpRecurrencesIfNeeded(userId: UUID) async {
        do {
            let deps = Dependencies.shared
            let recUC = try deps.resolve(type: RecurrenceUseCases.self)
            let taskUC = try TaskUseCases(
                tasksRepository: deps.resolve(type: TasksRepository.self),
                labelsRepository: deps.resolve(type: LabelsRepository.self)
            )
            let recurrences = try await recUC.list(for: userId)
            for rec in recurrences where rec.status == "active" {
                guard let next = rec.nextScheduledAt, next <= Date() else { continue }
                // Load template task and labels
                if let (template, labels) = try await taskUC.fetchTaskWithLabels(by: rec.taskTemplateId) {
                    let newTask = Task(userId: template.userId, bucketKey: template.bucketKey, title: template.title, description: template.description, dueAt: next)
                    try await taskUC.createTask(newTask)
                    let labelIds = Set(labels.map { $0.id })
                    try await taskUC.setLabels(for: newTask.id, to: labelIds, userId: userId)
                    if let due = newTask.dueAt {
                        await NotificationsManager.scheduleDueNotification(taskId: newTask.id, title: newTask.title, dueAt: due, bucketKey: newTask.bucketKey.rawValue)
                    }
                    Logger.shared.info("Catch-up: generated instance for recurrence template=\(rec.taskTemplateId) at=\(next)", category: .sync)
                }
            }
        } catch {
            Logger.shared.error("Recurrence catch-up failed", category: .sync, error: error)
        }
    }
    
    /// Performs initial sync for a user
    func performInitialSync(for userId: UUID) async {
        Logger.shared.info("Performing initial sync", category: .sync)
        self.currentUserId = userId
        // Start realtime (no-op stubs in Epic 1.3)
        try? await remoteTasksRepository.startRealtime(userId: userId)
        try? await remoteLabelsRepository.startRealtime(userId: userId)
        startRealtimeHints(for: userId)
        await sync(for: userId)
    }
    
    /// Schedules periodic sync
    func startPeriodicSync(for userId: UUID, intervalSeconds: TimeInterval = 60) {
        periodicCancellable?.cancel()
        periodicCancellable = Timer.publish(every: intervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                _Concurrency.Task { await self.sync(for: userId) }
            }
    }

    // MARK: - Realtime hint handling
    private func startRealtimeHints(for userId: UUID) {
        // Debounced sync on change notifications emitted by remote repositories
        realtimeObserver = NotificationCenter.default.addObserver(forName: Notification.Name("dm.remote.tasks.changed"), object: nil, queue: .main) { [weak self] _ in
            // Hop to the main actor explicitly to safely touch actor-isolated state in Swift 6
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.currentUserId == userId else { return }
                if self.realtimeDebounceScheduled { return }
                self.realtimeDebounceScheduled = true
                try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                self.realtimeDebounceScheduled = false
                await self.sync(for: userId)
            }
        }
    }

    /// Resets saved sync checkpoints for a user
    func resetSyncState(for userId: UUID) async throws {
        try await syncStateStore.reset(userId: userId)
    }
    
    // MARK: - Retry helper
    private func withRetry(_ operation: @escaping () async throws -> Void) async throws {
        let maxAttempts = 5
        var attempt = 0
        var lastError: Error?
        while attempt < maxAttempts {
            do {
                try await operation()
                return
            } catch {
                lastError = error
                attempt += 1
                let backoff = min(pow(2.0, Double(attempt)), 30.0)
                let jitter = Double.random(in: 0...0.3)
                let delay = backoff + jitter
                Logger.shared.error("Retrying sync phase (attempt #\(attempt)) in \(String(format: "%.1f", delay))s", category: .sync, error: error)
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw lastError ?? NSError(domain: "Sync", code: -1)
    }
}
