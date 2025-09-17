//
//  TaskListViewModel.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Combine
import SwiftUI
import Foundation

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
    // When true, list mode should fetch across all buckets (explicitly all-buckets)
    @Published var forceAllBuckets: Bool = false
    @Published var syncErrorMessage: String? = nil
    @Published var prefilledDraft: TaskDraft? = nil
    @Published var lastCreatedTaskId: UUID? = nil
    @AppStorage("sortByDueDate") private var sortByDueDate: Bool = false
    // Filtering
    @Published var activeFilterLabelIds: Set<UUID> = []
    @Published var matchAll: Bool = false
    @Published var unlabeledOnly: Bool = false
    @Published var availableOnly: Bool = false
    
    private let taskUseCases: TaskUseCases
    private let labelUseCases: LabelUseCases
    private let syncService: SyncService?
    private let recurrenceUseCases: RecurrenceUseCases?
    let userId: UUID
    private static let countsThrottleKey = "countsThrottleKey"
    // Persist filter selection per user
    @AppStorage("labelFilter_Ids") private var persistedFilterIdsRaw: String = ""
    // Pending selections coming from TaskFormView (via NotificationCenter)
    private var pendingLabelSelections: [UUID: Set<UUID>] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var pendingRecurrenceSelections: [UUID: RecurrenceRule] = [:]
    private var availableCutoffCache: (dayKey: String, cutoff: Date)? = nil
    // Caches
    private var recurringTemplateIdsCache: Set<UUID> = []
    private var recurrenceCacheDirty: Bool = true
    private var labelIdSetByTaskId: [UUID: Set<UUID>] = [:]
    // Fetch single-flight to avoid overlapping mutations during view updates
    private var fetchInFlight: Bool = false
    private var fetchQueued: Bool = false
    // Feature flag: enable weekday sections inside This Week
    @AppStorage("feature.thisWeekSections") var featureThisWeekSectionsEnabled: Bool = true
    // Feature flag: enable weekday sections inside Next Week
    @AppStorage("feature.nextWeekSections") var featureNextWeekSectionsEnabled: Bool = true
    // Collapsed state persistence for per-day sections (keys are yyyy-MM-dd)
    @AppStorage("thisWeek.collapsedDayKeys") private var collapsedDaysRaw: String = ""
    private var collapsedDayKeys: Set<String> {
        get { (try? JSONDecoder().decode(Set<String>.self, from: Data(collapsedDaysRaw.utf8))) ?? [] }
        set { if let data = try? JSONEncoder().encode(Array(newValue)) { collapsedDaysRaw = String(decoding: data, as: UTF8.self) } }
    }
    // Derived sections & grouping for This Week bucket
    @Published var thisWeekSections: [WeekdaySection] = []
    @Published var tasksByDayKey: [String: [(Task, [Label])]] = [:]
    // Derived sections & grouping for Next Week bucket
    @Published var nextWeekSections: [WeekdaySection] = []
    @Published var tasksByNextWeekDayKey: [String: [(Task, [Label])]] = [:]
    
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
        NotificationCenter.default.addObserver(forName: Notification.Name("dm.taskform.labels.selection"), object: nil, queue: nil) { [weak self] note in
            guard let self else { return }
            guard let taskId = note.userInfo?["taskId"] as? UUID,
                  let ids = note.userInfo?["labelIds"] as? [UUID] else { return }
            _Concurrency.Task { @MainActor in
                self.pendingLabelSelections[taskId] = Set(ids)
            }
        }
        // Listen for recurrence selection from TaskForm
        NotificationCenter.default.addObserver(forName: Notification.Name("dm.taskform.recurrence.selection"), object: nil, queue: nil) { [weak self] note in
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
            // Observe sync error for lightweight banner
            syncService.$syncError
                .receive(on: DispatchQueue.main)
                .sink { [weak self] error in
                    self?.syncErrorMessage = error?.localizedDescription
                }
                .store(in: &cancellables)
            // Refresh lists whenever a sync cycle finishes successfully
            syncService.$lastSyncDate
                .removeDuplicates()
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    // Auto-hide sync error on success
                    self.syncErrorMessage = nil
                    // Mark recurrence cache dirty so we refresh flags lazily on next fetch
                    self.recurrenceCacheDirty = true
                    _Concurrency.Task {
                        await self.refreshCounts()
                        let filter: TimeBucket? = (self.forceAllBuckets || self.isBoardModeActive) ? nil : self.selectedBucket
                        await self.fetchTasks(in: filter, showLoading: false)
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    func fetchTasks(in bucket: TimeBucket? = nil, showLoading: Bool = true) async {
        // Single-flight guard: coalesce overlapping fetches
        if fetchInFlight {
            fetchQueued = true
            return
        }
        fetchInFlight = true
        // Keep sync view context aligned with current UI
        // If an explicit bucket is provided, honor it (including nil = all buckets)
        // Otherwise, default to selectedBucket unless an all-buckets mode is active (board)
        let effectiveBucket: TimeBucket? = {
            if let explicit = bucket { return explicit }
            return (forceAllBuckets || isBoardModeActive) ? nil : selectedBucket
        }()
        let bucketKey = effectiveBucket?.rawValue
        let dueBy = availableOnly ? availableCutoffEndOfToday() : nil
        syncService?.setViewContext(bucketKey: bucketKey, dueBy: dueBy)
        // Keep current content visible when changing filters in all-buckets/macOS to avoid blank UI
        if showLoading { isLoading = true }
        errorMessage = nil
        do {
            let rawPairs = try await Logger.shared.time("fetchTasksWithLabels", category: .perf) {
                try await taskUseCases.fetchTasksWithLabels(for: userId, in: effectiveBucket)
            }
            // Perform sort/filter/build label-id sets off the main actor to avoid UI stalls
            let availableOnlyLocal = self.availableOnly
            let unlabeledOnlyLocal = self.unlabeledOnly
            let activeIdsLocal = self.activeFilterLabelIds
            let matchAllLocal = self.matchAll
            let sortByDueLocal = self.sortByDueDate
            let endOfTodayLocal = availableOnlyLocal ? self.availableCutoffEndOfToday() : nil
            let (pairs, idSetsByTask) = await _Concurrency.Task.detached(priority: _Concurrency.TaskPriority.userInitiated) { () -> ([(Task, [Label])], [UUID: Set<UUID>]) in
                var working = rawPairs
                let showCompletedLocal = await self.showCompleted
                // Helper to compute effective due (date-only as end-of-day)
                func effectiveDue(_ t: Task) -> Date? {
                    guard let due = t.dueAt else { return nil }
                    if t.dueHasTime { return due }
                    let cal = Calendar.current
                    let start = cal.startOfDay(for: due)
                    return cal.date(byAdding: .day, value: 1, to: start) ?? due
                }
                // Exclude completed tasks unless explicitly showing them
                if showCompletedLocal == false {
                    working = working.filter { pair in pair.0.isCompleted == false }
                }
                // Optional sort by due date
                if sortByDueLocal {
                    working.sort { lhs, rhs in
                        let lt = lhs.0
                        let rt = rhs.0
                        if lt.isCompleted != rt.isCompleted { return !lt.isCompleted && rt.isCompleted }
                        switch (effectiveDue(lt), effectiveDue(rt)) {
                        case let (l?, r?): return l < r
                        case (nil, _?): return false
                        case (_?, nil): return true
                        default: return lt.position < rt.position
                        }
                    }
                }
                if availableOnlyLocal, let end = endOfTodayLocal {
                    working = working.filter { pair in
                        let t = pair.0
                        guard t.isCompleted == false else { return false }
                        if let due = effectiveDue(t) { return due <= end }
                        return true
                    }
                }
                if unlabeledOnlyLocal {
                    working = working.filter { $0.1.isEmpty }
                } else if activeIdsLocal.isEmpty == false {
                    let idSetsByTask: [UUID: Set<UUID>] = Dictionary(uniqueKeysWithValues: working.map { ($0.0.id, Set($0.1.map { $0.id })) })
                    working = working.filter { pair in
                        let ids = idSetsByTask[pair.0.id] ?? []
                        return matchAllLocal ? ids.isSuperset(of: activeIdsLocal) : ids.intersection(activeIdsLocal).isEmpty == false
                    }
                    return (working, idSetsByTask)
                }
                let idSetsByTask: [UUID: Set<UUID>] = Dictionary(uniqueKeysWithValues: working.map { ($0.0.id, Set($0.1.map { $0.id })) })
                return (working, idSetsByTask)
            }.value
            // Persist memoized sets for visible rows
            self.labelIdSetByTaskId = idSetsByTask
            // DEBUG batch telemetry: tasks and distinct labels per render batch
            #if DEBUG
            let distinctLabelCount: Int = {
                var set: Set<UUID> = []
                for (_, labels) in pairs { labels.forEach { set.insert($0.id) } }
                return set.count
            }()
            Logger.shared.debug("renderBatch tasks=\(pairs.count) distinctLabels=\(distinctLabelCount)", category: .perf)
            #endif
            // Commit result; when in all-buckets list (forceAllBuckets) avoid clearing to empty first
            if self.forceAllBuckets || self.isBoardModeActive {
                // Replace in place to minimize flicker
                self.tasksWithLabels = pairs
            } else {
                self.tasksWithLabels = pairs
            }
            await loadRecurrenceFlags(for: pairs.map { $0.0.id })
            // Load subtask progress for visible items incrementally
            let parentIds = pairs.map { $0.0.id }
            await loadSubtaskProgressIncremental(for: parentIds)
            // Derive weekday sections/groupings when relevant
            if featureThisWeekSectionsEnabled { deriveThisWeekSectionsAndGroups() }
            if featureNextWeekSectionsEnabled { deriveNextWeekSectionsAndGroups() }
        } catch {
            errorMessage = "Failed to fetch tasks: \(error.localizedDescription)"
            Logger.shared.error("Failed to fetch tasks", category: .ui, error: error)
        }
        if showLoading { isLoading = false }
        fetchInFlight = false
        if fetchQueued {
            fetchQueued = false
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket, showLoading: false)
        }
    }

    /// Batch-apply large list diffs to reduce a single massive diff cost in SwiftUI.
    private func applyTasksListBatched(_ pairs: [(Task, [Label])]) async {
        let threshold = 400
        let chunkSize = 200
        guard pairs.count > threshold else {
            self.tasksWithLabels = pairs
            return
        }
        // Stage in chunks to avoid heavy single diff
        self.tasksWithLabels = []
        var index = 0
        while index < pairs.count {
            let end = min(index + chunkSize, pairs.count)
            let slice = pairs[index..<end]
            self.tasksWithLabels.append(contentsOf: slice)
            index = end
            // Yield to the runloop to allow UI to breathe between chunks
            try? await _Concurrency.Task.sleep(nanoseconds: 3_000_000) // 3ms
        }
    }

    private func loadRecurrenceFlags(for taskIds: [UUID]) async {
        guard let recUC = recurrenceUseCases else { return }
        do {
            if recurrenceCacheDirty {
                let recs = try await recUC.list(for: userId)
                recurringTemplateIdsCache = Set(recs.map { $0.taskTemplateId })
                recurrenceCacheDirty = false
            }
            let ids = recurringTemplateIdsCache
            await MainActor.run { self.tasksWithRecurrence = ids.intersection(taskIds) }
        } catch {
            // non-fatal
        }
    }

    func applyLabelFilter(selected: Set<UUID>, matchAll: Bool) {
        guard self.activeFilterLabelIds != selected || self.matchAll != matchAll else { return }
        self.activeFilterLabelIds = selected
        self.matchAll = matchAll
        self.unlabeledOnly = false
        persistFilterIds()
        _Concurrency.Task {
            let param: TimeBucket? = (self.forceAllBuckets || self.isBoardModeActive) ? nil : self.selectedBucket
            await self.fetchTasks(in: param, showLoading: false)
        }
    }

    func applyUnlabeledFilter() {
        self.activeFilterLabelIds.removeAll()
        self.matchAll = false
        self.unlabeledOnly = true
        _Concurrency.Task {
            let param: TimeBucket? = (self.forceAllBuckets || self.isBoardModeActive) ? nil : self.selectedBucket
            await self.fetchTasks(in: param, showLoading: false)
        }
    }

    func setAvailableFilter(_ enabled: Bool) {
        guard self.availableOnly != enabled else { return }
        self.availableOnly = enabled
        _Concurrency.Task {
            let param: TimeBucket? = (self.forceAllBuckets || self.isBoardModeActive) ? nil : self.selectedBucket
            await self.fetchTasks(in: param, showLoading: false)
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
        availableOnly = false
        _Concurrency.Task {
            let param: TimeBucket? = (self.forceAllBuckets || self.isBoardModeActive) ? nil : self.selectedBucket
            await self.fetchTasks(in: param, showLoading: false)
        }
        persistFilterIds()
        if featureThisWeekSectionsEnabled { deriveThisWeekSectionsAndGroups() }
        if featureNextWeekSectionsEnabled { deriveNextWeekSectionsAndGroups() }
    }

    func select(bucket: TimeBucket) {
        selectedBucket = bucket
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            // Update context bucket
            let dueBy = self.availableOnly ? self.availableCutoffEndOfToday() : nil
            syncService?.setViewContext(bucketKey: bucket.rawValue, dueBy: dueBy)
            async let fetch: Void = self.fetchTasks(in: bucket)
            async let counts: Void = self.refreshCounts()
            _ = await (fetch, counts)
            if self.featureThisWeekSectionsEnabled { self.deriveThisWeekSectionsAndGroups() }
            if self.featureNextWeekSectionsEnabled { self.deriveNextWeekSectionsAndGroups() }
        }
    }

    private func availableCutoffEndOfToday() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        let dayKey = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        if let cached = availableCutoffCache, cached.dayKey == dayKey { return cached.cutoff }
        // Use start of tomorrow (midnight next day) as inclusive cutoff for date-only due dates
        let startToday = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: 1, to: startToday) ?? now
        availableCutoffCache = (dayKey, cutoff)
        return cutoff
    }

    private func persistFilterIds() {
        if let data = try? JSONEncoder().encode(Array(activeFilterLabelIds)) {
            persistedFilterIdsRaw = String(decoding: data, as: UTF8.self)
        }
    }

    func refreshCounts() async {
        // Throttle to at most 2/sec under churn
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: Self.countsThrottleKey)
        if now - last < 0.5 { return }
        UserDefaults.standard.set(now, forKey: Self.countsThrottleKey)

        var counts: [TimeBucket: Int] = [:]
        await withTaskGroup(of: (TimeBucket, Int).self) { group in
            for bucket in TimeBucket.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                group.addTask { [userId, taskUseCases, showCompleted] in
                    let count = (try? await Logger.shared.time("count_\(bucket.rawValue)", category: .perf) {
                        try await taskUseCases.countTasks(for: userId, in: bucket, includeCompleted: showCompleted)
                    }) ?? 0
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
        let filter: TimeBucket? = (forceAllBuckets || isBoardModeActive) ? nil : selectedBucket
        await toggleTaskCompletion(task: task, refreshIn: filter)
    }

    func toggleTaskCompletion(task: Task, refreshIn filter: TimeBucket?) async {
        do {
            let wasCompleted = task.isCompleted
            if let progress = subtaskProgressByParent[task.id], progress.total > 0 {
                _ = try await Logger.shared.time("toggleParentCompletionCascade", category: .perf) {
                    try await taskUseCases.toggleParentCompletionCascade(parentId: task.id)
                }
            } else {
                _ = try await Logger.shared.time("toggleTaskCompletion", category: .perf) {
                    try await taskUseCases.toggleTaskCompletion(id: task.id, userId: userId)
                }
            }
            await refreshCounts()
            // Small delay to allow completion animation to read before row disappears under filters
            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000) // 0.2s
            await fetchTasks(in: filter, showLoading: false)
            // Notify working log to refresh if open
            NotificationCenter.default.post(name: Notification.Name("dm.task.completed.changed"), object: nil, userInfo: ["taskId": task.id])
            // If this task just became completed and has a recurrence, generate the next instance
            if wasCompleted == false {
                await generateNextInstanceIfRecurring(templateTaskId: task.id)
            }
        } catch {
            errorMessage = "Failed to toggle task completion: \(error.localizedDescription)"
            Logger.shared.error("Failed to toggle task completion", category: .ui, error: error)
        }
    }

    // MARK: - Recurrence Actions
    func generateNow(taskId: UUID) async {
        await generateNextInstanceIfRecurring(templateTaskId: taskId, anchor: Date())
    }

    func pauseResume(taskId: UUID) async {
        guard let recUC = recurrenceUseCases else { return }
        do {
            if var rec = try await recUC.getByTaskTemplateId(taskId, userId: userId) {
                rec.status = (rec.status == "active") ? "paused" : "active"
                Logger.shared.info("Toggle recurrence status for template=\(taskId) -> \(rec.status)", category: .ui)
                try await recUC.update(rec)
                let filter: TimeBucket? = (forceAllBuckets || isBoardModeActive) ? nil : selectedBucket
                await fetchTasks(in: filter)
            }
        } catch {
            Logger.shared.error("Failed to pause/resume recurrence", category: .ui, error: error)
        }
    }

    func skipNext(taskId: UUID) async {
        guard let recUC = recurrenceUseCases else { return }
        do {
            if var rec = try await recUC.getByTaskTemplateId(taskId, userId: userId) {
                let anchor = rec.nextScheduledAt ?? Date()
                if let next = recUC.nextOccurrence(from: anchor, rule: rec.rule) {
                    rec.nextScheduledAt = next
                    Logger.shared.info("Skip next for template=\(taskId) new next=\(next)", category: .ui)
                    try await recUC.update(rec)
                }
            }
        } catch {
            Logger.shared.error("Failed to skip next occurrence", category: .ui, error: error)
        }
    }

    private func generateNextInstanceIfRecurring(templateTaskId: UUID, anchor: Date? = nil) async {
        guard let recUC = recurrenceUseCases else { return }
        do {
            let deps = Dependencies.shared
            let taskUseCases = try TaskUseCases(
                tasksRepository: deps.resolve(type: TasksRepository.self),
                labelsRepository: deps.resolve(type: LabelsRepository.self)
            )

            // Resolve the true template ID: if no recurrence exists for the given id,
            // check whether this task is a generated instance with a parent template.
            let effectiveTemplateId: UUID
            if let _ = try? await recUC.getByTaskTemplateId(templateTaskId, userId: userId) {
                effectiveTemplateId = templateTaskId
            } else if let (candidate, _) = try? await taskUseCases.fetchTaskWithLabels(by: templateTaskId), let parent = candidate.parentTaskId,
                      let _ = try? await recUC.getByTaskTemplateId(parent, userId: userId) {
                effectiveTemplateId = parent
            } else {
                effectiveTemplateId = templateTaskId
            }

            guard let rec = try await recUC.getByTaskTemplateId(effectiveTemplateId, userId: userId) else { return }

            // Load template task with labels
            guard let (template, labels) = try await taskUseCases.fetchTaskWithLabels(by: effectiveTemplateId) else { return }
            // Use completion time if provided; otherwise fall back to template's dueAt or now
            let anchorDate = anchor ?? Date()
            guard let next = recUC.nextOccurrence(from: anchorDate, rule: rec.rule) else { return }
            Logger.shared.info("Generate next instance for template=\(effectiveTemplateId) at=\(next)", category: .ui)
            // Important: link new instance to template via parentTaskId
            let newTask = Task(userId: template.userId, bucketKey: template.bucketKey, parentTaskId: effectiveTemplateId, title: template.title, description: template.description, dueAt: next)
            try await taskUseCases.createTask(newTask)
            // Persist next scheduled on recurrence to avoid duplicate generation bursts
            var updatedRec = rec
            updatedRec.lastGeneratedAt = Date()
            updatedRec.nextScheduledAt = next
            try? await recUC.update(updatedRec)
            if let due = newTask.dueAt {
                await NotificationsManager.scheduleDueNotification(taskId: newTask.id, title: newTask.title, dueAt: due, bucketKey: newTask.bucketKey.rawValue)
            }
            // copy labels from template
            let ids = Set(labels.map { $0.id })
            try await taskUseCases.setLabels(for: newTask.id, to: ids, userId: userId)
            await refreshCounts()
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket, showLoading: false)
        } catch {
            Logger.shared.error("Failed to generate next instance", category: .ui, error: error)
        }
    }
    
    func presentCreateForm() {
        editingTask = nil
        isPresentingTaskForm = true
    }

    /// Present the lightweight composer prefilled for a specific bucket with default due date policy.
    func presentCreateForm(bucket: TimeBucket) {
        selectedBucket = bucket
        prefilledDraft = makeDraftForBucket(bucket)
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
                var localDraft = draft
                // Client auto-bucketing guard
                if let due = localDraft.dueAt { localDraft.bucket = computeAutoBucket(for: due) }
                let updated = localDraft.applying(to: editing)
                try await taskUseCases.updateTask(updated)
                if let due = updated.dueAt, !updated.isCompleted {
                    let scheduleAt: Date = {
                        if updated.dueHasTime { return due }
                        var comps = Calendar.current.dateComponents([.year,.month,.day], from: due)
                        comps.hour = 12
                        comps.minute = 0
                        return Calendar.current.date(from: comps) ?? due
                    }()
                    await NotificationsManager.scheduleDueNotification(taskId: updated.id, title: updated.title, dueAt: scheduleAt, bucketKey: updated.bucketKey.rawValue)
                } else {
                    await NotificationsManager.cancelDueNotification(taskId: updated.id)
                }
                // Persist label selections if available
                if let desired = pendingLabelSelections[updated.id] {
                    _ = try await Logger.shared.time("applyLabelSet", category: .perf) {
                        try await taskUseCases.setLabels(for: updated.id, to: desired, userId: userId)
                    }
                    pendingLabelSelections.removeValue(forKey: updated.id)
                }
                // Apply recurrence if selected
                if let rule = pendingRecurrenceSelections[updated.id], let recUC = recurrenceUseCases {
                    let recurrence = Recurrence(userId: userId, taskTemplateId: updated.id, rule: rule)
                    _ = try? await Logger.shared.time("recurrenceCreate", category: .perf) {
                        try await recUC.create(recurrence)
                    }
                    pendingRecurrenceSelections.removeValue(forKey: updated.id)
                }
            } else {
                var localDraft = draft
                // Client auto-bucketing guard
                if let due = localDraft.dueAt { localDraft.bucket = computeAutoBucket(for: due) }
                let newTask = localDraft.toNewTask()
                try await taskUseCases.createTask(newTask)
                NotificationCenter.default.post(name: Notification.Name("dm.task.created"), object: nil, userInfo: ["taskId": newTask.id])
                lastCreatedTaskId = newTask.id
                if let due = newTask.dueAt {
                    let scheduleAt: Date = {
                        if newTask.dueHasTime { return due }
                        var comps = Calendar.current.dateComponents([.year,.month,.day], from: due)
                        comps.hour = 12
                        comps.minute = 0
                        return Calendar.current.date(from: comps) ?? due
                    }()
                    await NotificationsManager.scheduleDueNotification(taskId: newTask.id, title: newTask.title, dueAt: scheduleAt, bucketKey: newTask.bucketKey.rawValue)
                }
                // For new tasks, selections were posted keyed by draft.id before creation.
                if let desired = pendingLabelSelections[draft.id] {
                    _ = try await Logger.shared.time("applyLabelSet", category: .perf) {
                        try await taskUseCases.setLabels(for: newTask.id, to: desired, userId: userId)
                    }
                    pendingLabelSelections.removeValue(forKey: draft.id)
                }
                if let rule = pendingRecurrenceSelections[draft.id], let recUC = recurrenceUseCases {
                    let recurrence = Recurrence(userId: userId, taskTemplateId: newTask.id, rule: rule)
                    _ = try? await Logger.shared.time("recurrenceCreate", category: .perf) {
                        try await recUC.create(recurrence)
                    }
                    pendingRecurrenceSelections.removeValue(forKey: draft.id)
                }
            }
            await refreshCounts()
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket)
            prefilledDraft = nil
        } catch {
            errorMessage = "Failed to save task: \(error.localizedDescription)"
            Logger.shared.error("Failed to save task", category: .ui, error: error)
        }
    }

    /// Compute the appropriate bucket for a given due date based on current local week rules
    private func computeAutoBucket(for dueAt: Date, now: Date = Date()) -> TimeBucket {
        let cal = Calendar.current
        let startDue = cal.startOfDay(for: dueAt)
        let weekMonday = WeekPlanner.mondayOfCurrentWeek(for: now, calendar: cal)
        let weekFriday = WeekPlanner.fridayOfCurrentWeek(for: now, calendar: cal)
        let weekend = WeekPlanner.saturdayAndSundayOfCurrentWeek(for: now, calendar: cal)
        let nextMon = WeekPlanner.nextMonday(after: now, calendar: cal)
        let nextSun = WeekPlanner.nextSunday(after: now, calendar: cal)
        if startDue >= weekMonday && startDue <= weekFriday { Telemetry.record(.autoBucketAssigned, metadata: ["bucket": TimeBucket.thisWeek.rawValue]); return .thisWeek }
        if startDue == weekend.saturday || startDue == weekend.sunday { Telemetry.record(.autoBucketAssigned, metadata: ["bucket": TimeBucket.weekend.rawValue]); return .weekend }
        if startDue >= nextMon && startDue <= nextSun { Telemetry.record(.autoBucketAssigned, metadata: ["bucket": TimeBucket.nextWeek.rawValue]); return .nextWeek }
        if startDue > nextSun { Telemetry.record(.autoBucketAssigned, metadata: ["bucket": TimeBucket.nextMonth.rawValue]); return .nextMonth }
        // Fallback (should not hit): treat as this week
        return .thisWeek
    }

    private func makeDraftForBucket(_ bucket: TimeBucket) -> TaskDraft {
        var draft = TaskDraft(userId: userId, bucket: bucket)
        let cal = Calendar.current
        switch bucket {
        case .thisWeek:
            draft.dueAt = cal.startOfDay(for: Date())
            draft.dueHasTime = false
        case .nextWeek:
            draft.dueAt = WeekPlanner.nextMonday(after: Date())
            draft.dueHasTime = false
        case .weekend:
            draft.dueAt = WeekPlanner.weekendAnchor(for: Date())
            draft.dueHasTime = false
        case .nextMonth, .routines:
            draft.dueAt = nil
            draft.dueHasTime = false
        }
        return draft
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
        // Respect all-buckets mode when refreshing
        let filter: TimeBucket? = (forceAllBuckets || isBoardModeActive) ? nil : selectedBucket
        await move(taskId: taskId, to: bucket, refreshIn: filter)
    }

    /// Move task and refresh using a specific filter. Pass `nil` to refresh all buckets (board view).
    func move(taskId: UUID, to bucket: TimeBucket, refreshIn filter: TimeBucket?) async {
        do {
            _ = try await Logger.shared.time("reorderCommit_move", category: .perf) {
                try await taskUseCases.moveTask(id: taskId, to: bucket, for: userId)
            }
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
            let filter: TimeBucket? = (forceAllBuckets || isBoardModeActive) ? nil : selectedBucket
            await fetchTasks(in: filter, showLoading: false)
        } catch {
            errorMessage = "Failed to add task: \(error.localizedDescription)"
            Logger.shared.error("Failed to add task", category: .ui, error: error)
        }
    }
    
    func deleteTask(task: Task) async {
        do {
            try await taskUseCases.deleteTask(by: task.id, for: userId)
            await refreshCounts()
            let filter: TimeBucket? = (forceAllBuckets || isBoardModeActive) ? nil : selectedBucket
            await fetchTasks(in: filter)
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
            _ = try await Logger.shared.time("reorderCommit", category: .perf) {
                try await taskUseCases.updateTaskOrderAndBucket(id: taskId, to: bucket, position: newPos, userId: userId)
            }
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
        let filter: TimeBucket? = (forceAllBuckets || isBoardModeActive) ? nil : selectedBucket
        await fetchTasks(in: filter)
    }
    
    func startPeriodicSync() {
        syncService?.startPeriodicSync(for: userId)
    }
    
    func stopPeriodicSync() {
        syncService?.stopPeriodicSync()
    }
    
    func initialSyncIfNeeded() async {
        guard let syncService = syncService else { return }
        await syncService.performInitialSync(for: userId)
    }

    // MARK: - This Week sections & scheduling
    private func deriveThisWeekSectionsAndGroups() {
        guard selectedBucket == .thisWeek else {
            thisWeekSections = []
            tasksByDayKey = [:]
            return
        }
        let now = Date()
        let sections = WeekPlanner.buildSections(for: now)
        thisWeekSections = sections
        var grouped: [String: [(Task,[Label])]] = [:]
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: now)
        let weekMonday = WeekPlanner.mondayOfCurrentWeek(for: now, calendar: cal)
        let weekFriday = WeekPlanner.fridayOfCurrentWeek(for: now, calendar: cal)
        let weekend = WeekPlanner.saturdayAndSundayOfCurrentWeek(for: now, calendar: cal)
        for pair in tasksWithLabels {
            let task = pair.0
            // Only include tasks that actually belong to This Week bucket
            guard task.bucketKey == .thisWeek else { continue }
            guard task.isCompleted == false else { continue }
            guard let due = task.dueAt else { continue }
            let startDue = cal.startOfDay(for: due)
            // Exclude weekend days from This Week sections
            if startDue == weekend.saturday || startDue == weekend.sunday { continue }
            if startDue == startToday || startDue < startToday {
                // Today includes overdue
                let key = WeekPlanner.isoDayKey(for: startToday)
                grouped[key, default: []].append(pair)
            } else if startDue >= weekMonday && startDue <= weekFriday {
                let key = WeekPlanner.isoDayKey(for: startDue)
                grouped[key, default: []].append(pair)
            }
        }
        tasksByDayKey = grouped
    }

    // MARK: - Next Week sections & grouping (Mon–Sun)
    private func deriveNextWeekSectionsAndGroups() {
        guard selectedBucket == .nextWeek else {
            nextWeekSections = []
            tasksByNextWeekDayKey = [:]
            return
        }
        let now = Date()
        let sections = WeekPlanner.buildNextWeekSections(for: now)
        nextWeekSections = sections
        var grouped: [String: [(Task,[Label])]] = [:]
        let cal = Calendar.current
        for pair in tasksWithLabels {
            let task = pair.0
            // Only include tasks that actually belong to Next Week bucket
            guard task.bucketKey == .nextWeek else { continue }
            guard task.isCompleted == false else { continue }
            guard let due = task.dueAt else { continue }
            let startDue = cal.startOfDay(for: due)
            let key = WeekPlanner.isoDayKey(for: startDue)
            if sections.contains(where: { $0.id == key }) {
                grouped[key, default: []].append(pair)
            }
        }
        tasksByNextWeekDayKey = grouped
        Telemetry.record(.nextWeekViewShown)
    }

    func toggleSectionCollapsed(for dayKey: String) {
        var set = collapsedDayKeys
        if set.contains(dayKey) { set.remove(dayKey) } else { set.insert(dayKey) }
        collapsedDayKeys = set
    }

    func isSectionCollapsed(dayKey: String) -> Bool {
        collapsedDayKeys.contains(dayKey)
    }

    func schedule(taskId: UUID, to targetDate: Date) async {
        guard let idx = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) else { return }
        var task = tasksWithLabels[idx].0
        let cal = Calendar.current
        let wasDueTime = task.dueHasTime
        if wasDueTime, let currentDue = task.dueAt {
            // Preserve time component
            var comps = cal.dateComponents([.hour, .minute, .second], from: currentDue)
            let base = cal.startOfDay(for: targetDate)
            comps.year = cal.component(.year, from: base)
            comps.month = cal.component(.month, from: base)
            comps.day = cal.component(.day, from: base)
            task.dueAt = cal.date(from: comps) ?? base
        } else {
            // Set to start of target day
            task.dueAt = cal.startOfDay(for: targetDate)
            task.dueHasTime = false
        }
        // Auto-assign bucket based on new due date so drag-to-schedule also moves buckets
        if let due = task.dueAt {
            let auto = computeAutoBucket(for: due)
            task.bucketKey = auto
        }
        do {
            try await taskUseCases.updateTask(task)
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket, showLoading: false)
        } catch {
            errorMessage = "Failed to reschedule: \(error.localizedDescription)"
        }
    }

    /// Clear the due date for a task (unschedule). Keeps it in the same bucket.
    func unschedule(taskId: UUID) async {
        guard let idx = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) else { return }
        var task = tasksWithLabels[idx].0
        task.dueAt = nil
        task.dueHasTime = false
        do {
            try await taskUseCases.updateTask(task)
            await NotificationsManager.cancelDueNotification(taskId: task.id)
            await fetchTasks(in: isBoardModeActive ? nil : selectedBucket, showLoading: false)
        } catch {
            errorMessage = "Failed to clear due date: \(error.localizedDescription)"
        }
    }
}
