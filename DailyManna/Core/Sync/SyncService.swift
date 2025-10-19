//
//  SyncService.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Combine
import Supabase

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
    private let realtimeCoordinator: RealtimeCoordinator = RealtimeCoordinator()
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

    // MARK: - Helpers
    /// Compute the appropriate bucket for a given due date based on current local week rules
    private func computeAutoBucketForDue(_ dueAt: Date, now: Date = Date()) -> TimeBucket {
        let cal = Calendar.current
        let startDue = cal.startOfDay(for: dueAt)
        let weekMonday = WeekPlanner.mondayOfCurrentWeek(for: now, calendar: cal)
        let weekFriday = WeekPlanner.fridayOfCurrentWeek(for: now, calendar: cal)
        let weekend = WeekPlanner.saturdayAndSundayOfCurrentWeek(for: now, calendar: cal)
        let nextMon = WeekPlanner.nextMonday(after: now, calendar: cal)
        let nextSun = WeekPlanner.nextSunday(after: now, calendar: cal)
        if startDue >= weekMonday && startDue <= weekFriday { return .thisWeek }
        if startDue == weekend.saturday || startDue == weekend.sunday { return .weekend }
        if startDue >= nextMon && startDue <= nextSun { return .nextWeek }
        if startDue > nextSun { return .nextMonth }
        return .thisWeek
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

            // Weekend rollover first so moves are included in the same push
            let didRolloverEarly = await WeeklyRolloverService().performIfNeeded(userId: userId)
            if didRolloverEarly {
                Logger.shared.info("Weekly rollover performed before push; including moves in this sync", category: .sync)
            }
            
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
            
            // Series-based routines generation (weekly/monthly/yearly via rule)
            if FeatureFlags.routinesTemplatesEnabled {
                try await withRetry { [weak self] in
                    guard let self else { return }
                    _ = try await Logger.shared.time("seriesRoutinesGeneration") {
                        try await self.generateSeriesInstancesIfNeeded(userId: userId)
                    }
                }
            }

            lastSyncDate = Date()
            // Weekly rollover: run from Saturday 00:00 (local) onward, once per upcoming week
            let didRollover = await WeeklyRolloverService().performIfNeeded(userId: userId)
            if didRollover {
                // Refresh local state after rollover so UI reflects moves
                NotificationCenter.default.post(name: Notification.Name("dm.remote.tasks.changed"), object: nil)
            }
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
        
        // 0. Local reconciliation for ROUTINES templates: ensure single root per template
        if FeatureFlags.routinesTemplatesEnabled {
            await reconcileRoutinesRootsLocally(userId: userId)
        }

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

    /// Consolidate ROUTINES roots: keep one root per template; convert duplicates to children
    private func reconcileRoutinesRootsLocally(userId: UUID) async {
        do {
            let all = try await localTasksRepository.fetchTasks(for: userId, in: .routines)
            // Group by templateId (fallback to title if templateId missing)
            let groups: [String: [Task]] = Dictionary(grouping: all.filter { $0.deletedAt == nil }) { t in
                if let tid = t.templateId { return "TPL::\(tid.uuidString)" }
                return "TITLE::\(t.title.uppercased())"
            }
            for (_, tasks) in groups {
                // Identify roots (no parent)
                let roots = tasks.filter { $0.parentTaskId == nil }
                guard roots.count > 1 else {
                    // Normalize single root: ensure due_at is nil
                    if let root = roots.first, root.dueAt != nil {
                        var fixed = root
                        fixed.dueAt = nil
                        fixed.dueHasTime = false
                        fixed.needsSync = true
                        try await localTasksRepository.updateTask(fixed)
                    }
                    continue
                }
                // Keep the oldest by createdAt
                let kept = roots.sorted { ($0.createdAt) < ($1.createdAt) }.first!
                // Ensure kept has no due
                if kept.dueAt != nil {
                    var fixed = kept
                    fixed.dueAt = nil
                    fixed.dueHasTime = false
                    fixed.needsSync = true
                    try await localTasksRepository.updateTask(fixed)
                }
                // Convert other roots into children under kept
                for dup in roots where dup.id != kept.id {
                    var moved = dup
                    moved.parentTaskId = kept.id
                    // If it has a due date, set occurrence_date from due
                    if let d = dup.dueAt { moved.occurrenceDate = Calendar.current.startOfDay(for: d) }
                    // Move position under parent
                    let pos = try await localTasksRepository.nextSubtaskBottomPosition(parentTaskId: kept.id)
                    moved.position = pos
                    moved.needsSync = true
                    try await localTasksRepository.updateTask(moved)
                }
            }
        } catch {
            Logger.shared.error("Local routines reconciliation failed", category: .sync, error: error)
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
                do {
                    if link.deletedAt == nil {
                        try await remoteLabelsRepository.link(link)
                    } else {
                        try await remoteLabelsRepository.unlink(taskId: link.taskId, labelId: link.labelId)
                    }
                    try await localLabelsRepository.markTaskLabelLinkSynced(taskId: link.taskId, labelId: link.labelId)
                } catch {
                    if let pgError = error as? PostgrestError,
                       pgError.message.contains("violates foreign key constraint \"task_labels_task_id_fkey\"") {
                        // The remote task does not exist; discard the local link to avoid infinite retries
                        Logger.shared.error("Discarding task-label link due to missing remote task id=\(link.taskId)", category: .sync, error: error)
                        // Soft-delete locally; will translate to a harmless remote unlink (no-op) next cycle
                        try? await localLabelsRepository.removeLabel(link.labelId, from: link.taskId, for: link.userId)
                        continue
                    }
                    throw error
                }
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

    // MARK: - Weekly routines generation (templates/series)
    private func generateWeeklyRoutinesIfNeeded(userId: UUID) async throws {
        let deps = Dependencies.shared
        // Resolve use cases and repositories
        let templatesUC = try deps.resolve(type: TemplatesUseCases.self)
        let seriesUC = try deps.resolve(type: SeriesUseCases.self)
        let taskUC = try TaskUseCases(
            tasksRepository: deps.resolve(type: TasksRepository.self),
            labelsRepository: deps.resolve(type: LabelsRepository.self)
        )

        // Today forward window [today, today+7)
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return }

        // Enumerate active series
        let allSeries = try await seriesUC.list(ownerId: userId)
        let activeSeries = allSeries.filter { $0.status == "active" && ($0.endsOn == nil || $0.endsOn! >= start) }

        for series in activeSeries {
            // Fetch template for defaults
            guard let template = try await templatesUC.get(id: series.templateId, ownerId: userId) else { continue }
            // Compute schedule within window using anchorWeekday (or startsOn weekday) and intervalWeeks.
            // Idempotency: check existing tasks for (seriesId, occurrenceDate)

            // Build candidate days [start, end)
            var day = start
            while day < end {
                let dateOnly = cal.startOfDay(for: day)
                // Only generate on matching weekday relative to anchor
                let anchorW = series.anchorWeekday ?? cal.component(.weekday, from: series.startsOn)
                let candidateWeekday = cal.component(.weekday, from: dateOnly)
                guard anchorW == candidateWeekday else {
                    guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                    continue
                }
                // Respect weekly interval: number of weeks between series.startsOn and dateOnly must be multiple of intervalWeeks
                let weeksBetween: Int = {
                    let comps = cal.dateComponents([.weekOfYear], from: cal.startOfDay(for: series.startsOn), to: dateOnly)
                    return abs(comps.weekOfYear ?? 0)
                }()
                if weeksBetween % max(1, series.intervalWeeks) != 0 {
                    guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                    continue
                }
                // Find or create template root in ROUTINES (root has no due_at)
                let routinesTasks = try await localTasksRepository.fetchTasks(for: userId, in: .routines)
                var root = routinesTasks.first { $0.parentTaskId == nil && $0.templateId == template.id && $0.deletedAt == nil }
                if root == nil {
                    let pos = try await localTasksRepository.nextPositionForBottom(userId: userId, in: .routines)
                    let rootTask = Task(
                        userId: userId,
                        bucketKey: .routines,
                        position: pos,
                        parentTaskId: nil,
                        templateId: template.id,
                        seriesId: series.id,
                        title: template.name,
                        description: template.description,
                        dueAt: nil,
                        dueHasTime: false,
                        occurrenceDate: nil,
                        recurrenceRule: nil,
                        priority: template.priority,
                        reminders: nil,
                        exceptionMask: nil,
                        isCompleted: false
                    )
                    try await taskUC.createTask(rootTask)
                    root = rootTask
                    let labelIds = Set(template.labelsDefault)
                    if !labelIds.isEmpty { try? await taskUC.setLabels(for: rootTask.id, to: labelIds, userId: userId) }
                }

                // If child occurrence for this date does not exist, create under root
                let already = routinesTasks.contains { $0.seriesId == series.id && $0.occurrenceDate == dateOnly && $0.parentTaskId == root?.id && $0.deletedAt == nil }
                if already == false, let parentId = root?.id {
                    let childPos = try await localTasksRepository.nextSubtaskBottomPosition(parentTaskId: parentId)
                    // Compose dueAt from dateOnly + template default time if provided
                    let dueAt: Date? = {
                        if let comps = template.defaultDueTime, let h = comps.hour, let m = comps.minute {
                            var full = cal.dateComponents([.year,.month,.day], from: dateOnly)
                            full.hour = h; full.minute = m
                            return cal.date(from: full)
                        }
                        return dateOnly // fallback to date-only due date if no time
                    }()
                    let child = Task(
                        userId: userId,
                        bucketKey: .routines,
                        position: childPos,
                        parentTaskId: parentId,
                        templateId: template.id,
                        seriesId: series.id,
                        title: template.name,
                        description: template.description,
                        dueAt: dueAt,
                        dueHasTime: dueAt != nil,
                        occurrenceDate: dateOnly,
                        recurrenceRule: nil,
                        priority: template.priority,
                        reminders: nil,
                        exceptionMask: nil,
                        isCompleted: false
                    )
                    try await taskUC.createTask(child)
                    let labelIds = Set(template.labelsDefault)
                    if !labelIds.isEmpty { try? await taskUC.setLabels(for: child.id, to: labelIds, userId: userId) }
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
    }

    // MARK: - Series routines generation (weekly/monthly/yearly via rule)
    private func generateSeriesInstancesIfNeeded(userId: UUID) async throws {
        let deps = Dependencies.shared
        // Resolve use cases and repositories
        let templatesUC = try deps.resolve(type: TemplatesUseCases.self)
        let seriesUC = try deps.resolve(type: SeriesUseCases.self)
        let taskUC = try TaskUseCases(
            tasksRepository: deps.resolve(type: TasksRepository.self),
            labelsRepository: deps.resolve(type: LabelsRepository.self)
        )

        // Today forward window [today, today+7)
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return }

        // Enumerate active series
        let allSeries = try await seriesUC.list(ownerId: userId)
        let activeSeries = allSeries.filter { $0.status == "active" && ($0.endsOn == nil || $0.endsOn! >= start) }

        let engine = RecurrenceEngine()

        for series in activeSeries {
            // Fetch template for defaults
            guard let template = try await templatesUC.get(id: series.templateId, ownerId: userId) else { continue }

            // Build rule (fallback to legacy weekly fields)
            let rule: RecurrenceRule = {
                if let r = series.rule { return r }
                let anchor = series.anchorWeekday ?? cal.component(.weekday, from: series.startsOn)
                let code: String = { switch anchor { case 1: return "SU"; case 2: return "MO"; case 3: return "TU"; case 4: return "WE"; case 5: return "TH"; case 6: return "FR"; case 7: return "SA"; default: return "MO" } }()
                return RecurrenceRule(freq: .weekly, interval: max(1, series.intervalWeeks), byWeekday: [code])
            }()

            // Iterate occurrences in window
            var occurrences: [Date] = []
            var probe = cal.startOfDay(for: series.startsOn)
            var safety = 0
            while let next = engine.nextOccurrence(from: probe, rule: rule, calendar: cal), next < end, safety < 1000 {
                safety += 1
                if next >= start { occurrences.append(cal.startOfDay(for: next)) }
                probe = next
            }

            // Generate instances
            for dateOnly in occurrences {
                // Find or create template root in ROUTINES (root has no due_at)
                let routinesTasks = try await localTasksRepository.fetchTasks(for: userId, in: .routines)
                var root = routinesTasks.first { $0.parentTaskId == nil && $0.templateId == template.id && $0.deletedAt == nil }
                if root == nil {
                    let pos = try await localTasksRepository.nextPositionForBottom(userId: userId, in: .routines)
                    let rootTask = Task(
                        userId: userId,
                        bucketKey: .routines,
                        position: pos,
                        parentTaskId: nil,
                        templateId: template.id,
                        seriesId: series.id,
                        title: template.name,
                        description: template.description,
                        dueAt: nil,
                        dueHasTime: false,
                        occurrenceDate: nil,
                        recurrenceRule: nil,
                        priority: template.priority,
                        reminders: nil,
                        exceptionMask: nil,
                        isCompleted: false
                    )
                    try await taskUC.createTask(rootTask)
                    root = rootTask
                    let labelIds = Set(template.labelsDefault)
                    if !labelIds.isEmpty { try? await taskUC.setLabels(for: rootTask.id, to: labelIds, userId: userId) }
                }

                // If child occurrence for this date does not exist, create under root
                let already = routinesTasks.contains { $0.seriesId == series.id && $0.occurrenceDate == dateOnly && $0.parentTaskId == root?.id && $0.deletedAt == nil }
                if already == false, let parentId = root?.id {
                    let childPos = try await localTasksRepository.nextSubtaskBottomPosition(parentTaskId: parentId)
                    // Compose dueAt from dateOnly + template default time if provided, else rule.time
                    let dueAt: Date? = {
                        if let comps = template.defaultDueTime, let h = comps.hour, let m = comps.minute {
                            var full = cal.dateComponents([.year,.month,.day], from: dateOnly)
                            full.hour = h; full.minute = m
                            return cal.date(from: full)
                        }
                        if let t = rule.time {
                            let parts = t.split(separator: ":")
                            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                                var full = cal.dateComponents([.year,.month,.day], from: dateOnly)
                                full.hour = h; full.minute = m
                                return cal.date(from: full)
                            }
                        }
                        return dateOnly
                    }()
                    let child = Task(
                        userId: userId,
                        bucketKey: .routines,
                        position: childPos,
                        parentTaskId: parentId,
                        templateId: template.id,
                        seriesId: series.id,
                        title: template.name,
                        description: template.description,
                        dueAt: dueAt,
                        dueHasTime: dueAt != nil,
                        occurrenceDate: dateOnly,
                        recurrenceRule: nil,
                        priority: template.priority,
                        reminders: nil,
                        exceptionMask: nil,
                        isCompleted: false
                    )
                    try await taskUC.createTask(child)
                    let labelIds = Set(template.labelsDefault)
                    if !labelIds.isEmpty { try? await taskUC.setLabels(for: child.id, to: labelIds, userId: userId) }
                }
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
                    // Duplicate guard: if a child exists for this parent+due, skip creating and just advance recurrence
                    let existingChildren = try? await taskUC.fetchSubTasks(for: template.id)
                    if let children = existingChildren, children.contains(where: { $0.deletedAt == nil && $0.dueAt == next }) {
                        var updatedRec = rec
                        updatedRec.lastGeneratedAt = Date()
                        if let upcoming = recUC.nextOccurrence(from: next, rule: rec.rule) {
                            updatedRec.nextScheduledAt = upcoming
                        } else {
                            updatedRec.status = "paused"
                        }
                        try? await recUC.update(updatedRec)
                        continue
                    }

                    // Generate instance and auto-bucket by due date
                    let instanceBucket = computeAutoBucketForDue(next)
                    let newTask = Task(userId: template.userId, bucketKey: instanceBucket, parentTaskId: template.id, title: template.title, description: template.description, dueAt: next)
                    try await taskUC.createTask(newTask)
                    let labelIds = Set(labels.map { $0.id })
                    try await taskUC.setLabels(for: newTask.id, to: labelIds, userId: userId)
                    if let due = newTask.dueAt {
                        await NotificationsManager.scheduleDueNotification(taskId: newTask.id, title: newTask.title, dueAt: due, bucketKey: newTask.bucketKey.rawValue)
                    }
                    Logger.shared.info("Catch-up: generated instance for recurrence template=\(rec.taskTemplateId) at=\(next)", category: .sync)
                    // Advance recurrence to the next-after-created occurrence
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
        await realtimeCoordinator.start(for: userId)
        // Consume typed realtime streams -> targeted upserts
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            for await change in await self.realtimeCoordinator.taskChanges {
                await self.applyTargetedTaskChange(change: change, userId: userId)
            }
        }
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            for await change in await self.realtimeCoordinator.labelChanges {
                await self.applyTargetedLabelChange(change: change, userId: userId)
            }
        }
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            for await _ in await self.realtimeCoordinator.templateChanges {
                NotificationCenter.default.post(name: Notification.Name("dm.remote.tasks.changed"), object: nil)
            }
        }
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            for await _ in await self.realtimeCoordinator.seriesChanges {
                NotificationCenter.default.post(name: Notification.Name("dm.remote.tasks.changed"), object: nil)
            }
        }
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
                // Do not retry on unique constraint violations or invalid ON CONFLICT targets; reconcile instead upstream
                if let pgError = error as? PostgrestError {
                    let message = pgError.message
                    if message.contains("duplicate key value violates unique constraint") ||
                        message.contains("there is no unique or exclusion constraint matching the ON CONFLICT specification") {
                        Logger.shared.error("Not retrying due to constraint error", category: .sync, error: error)
                        throw error
                    }
                }
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

// MARK: - Realtime targeted change appliers
private extension SyncService {
    func applyTargetedTaskChange(change: TaskChange, userId: UUID) async {
        guard currentUserId == userId else { return }
        guard let id = change.id else {
            NotificationCenter.default.post(name: Notification.Name("dm.remote.tasks.changed"), object: nil)
            return
        }
        do {
            if change.action == .delete {
                try await localTasksRepository.deleteTask(by: id)
            } else if let remote = try await remoteTasksRepository.fetchTask(id: id) {
                if let existing = try await localTasksRepository.fetchTask(by: id) {
                    if remote.updatedAt > existing.updatedAt {
                        var updated = remote
                        updated.needsSync = false
                        try await localTasksRepository.updateTask(updated)
                    }
                } else {
                    var created = remote
                    created.needsSync = false
                    try await localTasksRepository.createTask(created)
                }
            }
        } catch {
            NotificationCenter.default.post(name: Notification.Name("dm.remote.tasks.changed"), object: nil)
        }
    }

    func applyTargetedLabelChange(change: LabelChange, userId: UUID) async {
        guard currentUserId == userId else { return }
        guard let id = change.id else {
            NotificationCenter.default.post(name: Notification.Name("dm.remote.labels.changed"), object: nil)
            return
        }
        do {
            if change.action == .delete {
                try await localLabelsRepository.deleteLabel(by: id)
            } else if let remote = try await remoteLabelsRepository.fetchLabel(id: id) {
                if let existing = try await localLabelsRepository.fetchLabel(by: id) {
                    if remote.updatedAt > existing.updatedAt {
                        var updated = remote
                        updated.needsSync = false
                        try await localLabelsRepository.updateLabel(updated)
                    }
                } else {
                    var created = remote
                    created.needsSync = false
                    try await localLabelsRepository.createLabel(created)
                }
            }
        } catch {
            NotificationCenter.default.post(name: Notification.Name("dm.remote.labels.changed"), object: nil)
        }
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
