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
    private let localWorkingLogRepository: WorkingLogRepository
    private let remoteWorkingLogRepository: RemoteWorkingLogRepository
    private var realtimeObserver: NSObjectProtocol?
    private var realtimeDebounceScheduled = false
    private var currentUserId: UUID?
    #if DEBUG
    // DEBUG counters for telemetry
    @Published private(set) var debugRealtimeHintsReceived: Int = 0
    @Published private(set) var debugDroppedRealtimeHints: Int = 0
    @Published private(set) var debugOverlappingSyncAttempts: Int = 0
    #endif

    // Current view context for trimming remote pulls
    struct ViewContext {
        var bucketKey: String?
        var dueBy: Date?
    }
    private var currentViewContext: ViewContext = .init(bucketKey: nil, dueBy: nil)
    
    init(
        localTasksRepository: TasksRepository,
        remoteTasksRepository: RemoteTasksRepository,
        localLabelsRepository: LabelsRepository,
        remoteLabelsRepository: RemoteLabelsRepository,
        syncStateStore: SyncStateStore,
        localWorkingLogRepository: WorkingLogRepository,
        remoteWorkingLogRepository: RemoteWorkingLogRepository
    ) {
        self.localTasksRepository = localTasksRepository
        self.remoteTasksRepository = remoteTasksRepository
        self.localLabelsRepository = localLabelsRepository
        self.remoteLabelsRepository = remoteLabelsRepository
        self.syncStateStore = syncStateStore
        self.localWorkingLogRepository = localWorkingLogRepository
        self.remoteWorkingLogRepository = remoteWorkingLogRepository
    }

    /// Updates the current view context used to trim remote deltas during sync
    func setViewContext(bucketKey: String?, dueBy: Date?) {
        currentViewContext = .init(bucketKey: bucketKey, dueBy: dueBy)
    }
    
    private var periodicCancellable: AnyCancellable?
    
    /// Performs a full bidirectional sync for a specific user
    func sync(for userId: UUID) async {
        // Single-flight with queued rerun
        struct Flags { static var rerunRequested = false }
        if isSyncing {
            Flags.rerunRequested = true
            Logger.shared.info("Sync already in progress, queueing rerun", category: .sync)
            #if DEBUG
            debugOverlappingSyncAttempts += 1
            #endif
            return
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            Logger.shared.info("Starting sync operation", category: .sync)
            
            // Sync tasks
            try await withRetry { [weak self] in
                guard let self else { return }
                _ = try await Logger.shared.time("syncTasks") {
                    try await self.syncTasks(userId: userId)
                }
            }
            
            // Sync labels
            try await withRetry { [weak self] in
                guard let self else { return }
                _ = try await Logger.shared.time("syncLabels") {
                    try await self.syncLabels(userId: userId)
                }
            }

            // Recurrences (pull + catch-up)
            try await withRetry { [weak self] in
                guard let self else { return }
                _ = try await Logger.shared.time("syncRecurrences") {
                    try await self.syncRecurrences(userId: userId)
                }
            }
            try await withRetry { [weak self] in
                guard let self else { return }
                _ = await Logger.shared.time("recurrenceCatchUp") {
                    await self.catchUpRecurrencesIfNeeded(userId: userId)
                }
            }

            // Working Log
            try await withRetry { [weak self] in
                guard let self else { return }
                _ = try await Logger.shared.time("syncWorkingLog") {
                    try await self.syncWorkingLog(userId: userId)
                }
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
        let bucketKey = currentViewContext.bucketKey
        let dueBy = currentViewContext.dueBy
        var remoteTasks: [Task]
        if bucketKey != nil || dueBy != nil {
            remoteTasks = try await remoteTasksRepository.fetchTasks(since: since, bucketKey: bucketKey, dueBy: dueBy)
        } else {
            remoteTasks = try await remoteTasksRepository.fetchTasks(since: since)
        }
        // Fallback: if we expected deltas but got nothing on an empty store, fetch all
        if remoteTasks.isEmpty && isColdStart && since != nil {
            remoteTasks = try await remoteTasksRepository.fetchTasks(since: nil, bucketKey: bucketKey, dueBy: dueBy)
        }
        
        if !remoteTasks.isEmpty {
            Logger.shared.info("Pulling \(remoteTasks.count) remote task changes", category: .sync)
            
            for remoteTask in remoteTasks {
                do {
                    // Check if task exists locally
                    if let existingTask = try await localTasksRepository.fetchTask(by: remoteTask.id) {
                        // Apply conflict resolution (last-write-wins for now)
                        if remoteTask.updatedAt > existingTask.updatedAt {
                            // Fast no-op skip: if equal after dropping volatile fields, skip write
                            if fastEqual(existingTask, remoteTask) {
                                continue
                            }
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

    // MARK: - Working Log
    private func syncWorkingLog(userId: UUID) async throws {
        // Push local changes
        let pending = (try? await localWorkingLogRepository.fetchNeedingSync(for: userId)) ?? []
        for item in pending {
            if item.deletedAt == nil {
                let synced = try await remoteWorkingLogRepository.upsert(item)
                var updated = synced
                updated.needsSync = false
                try await localWorkingLogRepository.update(updated)
            } else {
                // Soft delete remotely as well
                try await remoteWorkingLogRepository.softDelete(id: item.id)
                var updated = item
                updated.needsSync = false
                try await localWorkingLogRepository.update(updated)
            }
        }
        
        // Pull remote changes (delta)
        let checkpoints = try await syncStateStore.loadSnapshot(userId: userId)
        let since = checkpoints?.lastLabelsSyncAt ?? lastSyncDate // reuse labels checkpoint to avoid schema change
        let remoteItems = try await remoteWorkingLogRepository.fetchItems(since: since)
        if !remoteItems.isEmpty {
            for remote in remoteItems {
                if let existing = try await localWorkingLogRepository.fetch(by: remote.id) {
                    if remote.updatedAt > existing.updatedAt {
                        var updated = remote
                        updated.needsSync = false
                        try await localWorkingLogRepository.update(updated)
                    }
                } else {
                    var newItem = remote
                    newItem.needsSync = false
                    try await localWorkingLogRepository.create(newItem)
                }
            }
        }
        if let maxServerUpdated = remoteItems.map({ $0.updatedAt }).max() {
            // Piggyback on labels checkpoint to avoid expanding SyncStateEntity now
            try await syncStateStore.updateLabelsCheckpoint(userId: userId, to: maxServerUpdated)
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
                    // Advance recurrence so we don't re-generate in the same or next cycles
                    var updatedRec = rec
                    updatedRec.lastGeneratedAt = Date()
                    if let upcoming = recUC.nextOccurrence(from: next, rule: rec.rule) {
                        updatedRec.nextScheduledAt = upcoming
                    } else {
                        // If rule does not produce a next date, pause
                        updatedRec.status = "paused"
                    }
                    try? await recUC.update(updatedRec)
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

    /// Stops periodic sync timer
    func stopPeriodicSync() {
        periodicCancellable?.cancel()
        periodicCancellable = nil
    }

    // MARK: - Realtime hint handling
    private func startRealtimeHints(for userId: UUID) {
        // Debounced sync on change notifications emitted by remote repositories
        realtimeObserver = NotificationCenter.default.addObserver(forName: Notification.Name("dm.remote.tasks.changed"), object: nil, queue: .main) { [weak self] _ in
            // Hop to the main actor explicitly to safely touch actor-isolated state in Swift 6
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.currentUserId == userId else { return }
                #if DEBUG
                self.debugRealtimeHintsReceived += 1
                #endif
                if self.realtimeDebounceScheduled {
                    #if DEBUG
                    self.debugDroppedRealtimeHints += 1
                    #endif
                    return
                }
                self.realtimeDebounceScheduled = true
                try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                self.realtimeDebounceScheduled = false
                await self.sync(for: userId)
            }
        }

        // Targeted upsert handler: when we receive a specific row id, fetch and apply only that row
        _ = NotificationCenter.default.addObserver(forName: Notification.Name("dm.remote.tasks.changed.targeted"), object: nil, queue: .main) { [weak self] note in
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.currentUserId == userId else { return }
                guard let id = note.userInfo?["id"] as? UUID else {
                    return
                }
                do {
                    // Fetch the authoritative row from the server
                    if let remoteTask = try await self.remoteTasksRepository.fetchTask(id: id) {
                        if let existing = try await self.localTasksRepository.fetchTask(by: id) {
                            if remoteTask.updatedAt > existing.updatedAt {
                                var updated = remoteTask
                                updated.needsSync = false
                                try await self.localTasksRepository.updateTask(updated)
                            }
                        } else {
                            var newTask = remoteTask
                            newTask.needsSync = false
                            try await self.localTasksRepository.createTask(newTask)
                        }
                    } else {
                        // If remote row is gone (hard-deleted or tombstoned), mirror locally
                        if let existing = try await self.localTasksRepository.fetchTask(by: id) {
                            var updated = existing
                            updated.deletedAt = updated.deletedAt ?? Date()
                            updated.needsSync = false
                            try await self.localTasksRepository.updateTask(updated)
                        }
                    }
                } catch {
                    // On any failure, fallback to the coarse debounced delta pull
                    NotificationCenter.default.post(name: Notification.Name("dm.remote.tasks.changed"), object: nil)
                }
            }
        }

        // Labels targeted upsert handler
        _ = NotificationCenter.default.addObserver(forName: Notification.Name("dm.remote.labels.changed.targeted"), object: nil, queue: .main) { [weak self] note in
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.currentUserId == userId else { return }
                guard let id = note.userInfo?["id"] as? UUID else {
                    return
                }
                do {
                    if let remoteLabel = try await self.remoteLabelsRepository.fetchLabel(id: id) {
                        if let existing = try await self.localLabelsRepository.fetchLabel(by: id) {
                            if remoteLabel.updatedAt > existing.updatedAt {
                                var updated = remoteLabel
                                updated.needsSync = false
                                try await self.localLabelsRepository.updateLabel(updated)
                            }
                        } else {
                            var newLabel = remoteLabel
                            newLabel.needsSync = false
                            try await self.localLabelsRepository.createLabel(newLabel)
                        }
                    } else {
                        if let existing = try await self.localLabelsRepository.fetchLabel(by: id) {
                            var updated = existing
                            updated.deletedAt = updated.deletedAt ?? Date()
                            updated.needsSync = false
                            try await self.localLabelsRepository.updateLabel(updated)
                        }
                    }
                } catch {
                    NotificationCenter.default.post(name: Notification.Name("dm.remote.labels.changed"), object: nil)
                }
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

// MARK: - Fast compare helpers
private func fastEqual(_ lhs: Task, _ rhs: Task) -> Bool {
    return lhs.title == rhs.title &&
    lhs.description == rhs.description &&
    lhs.bucketKey == rhs.bucketKey &&
    lhs.position == rhs.position &&
    lhs.isCompleted == rhs.isCompleted &&
    lhs.dueAt == rhs.dueAt &&
    lhs.deletedAt == rhs.deletedAt
}
