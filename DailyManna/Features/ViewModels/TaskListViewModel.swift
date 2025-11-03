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
    @Published var allLabels: [Label] = []
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
    @Published var pendingCompleteForever: Task? = nil
    // Board-only: always treat fetches as all-buckets (nil filter)
    @Published var isBoardModeActive: Bool = true
    @Published var forceAllBuckets: Bool = true
    @Published var syncErrorMessage: String? = nil
    @Published var prefilledDraft: TaskDraft? = nil
    // Snackbar state for temporary notifications like completion undo
    @Published var snackbarMessage: String? = nil
    @Published var snackbarIsPresented: Bool = false
    private var lastCompletedTaskSnapshot: Task? = nil
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
        NotificationCenter.default.addObserver(forName: Notification.Name("dm.taskform.recurrence.clear"), object: nil, queue: nil) { [weak self] note in
            guard let self else { return }
            guard let taskId = note.userInfo?["taskId"] as? UUID else { return }
            _Concurrency.Task { await self.clearRecurrenceIfExists(taskId: taskId) }
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
                        await self.fetchTasks(in: nil, showLoading: false)
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Labels: Load all, toggle quick, and set full
    func loadAllLabels() async {
        do {
            let labels = try await labelUseCases.fetchLabels(for: userId)
            await MainActor.run { self.allLabels = labels }
        } catch {
            Logger.shared.error("Failed to load labels", category: .ui, error: error)
        }
    }

    /// Optimistically toggle a single label assignment for a task.
    func toggleLabel(taskId: UUID, labelId: UUID) {
        guard let index = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) else { return }
        var pair = tasksWithLabels[index]
        let hasIt = pair.1.contains(where: { $0.id == labelId })
        if hasIt {
            pair.1.removeAll { $0.id == labelId }
        } else if let label = allLabels.first(where: { $0.id == labelId }) {
            pair.1.append(label)
        }
        tasksWithLabels[index] = pair

        _Concurrency.Task {
            do {
                if hasIt {
                    try await labelUseCases.removeLabel(labelId, from: taskId, for: userId)
                } else {
                    try await labelUseCases.addLabel(labelId, to: taskId, for: userId)
                }
                Telemetry.record(.labelQuickToggled)
            } catch {
                await MainActor.run {
                    // Revert on failure
                    if hasIt, let label = allLabels.first(where: { $0.id == labelId }) {
                        if let revertIdx = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) {
                            tasksWithLabels[revertIdx].1.append(label)
                        }
                    } else {
                        if let revertIdx = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) {
                            tasksWithLabels[revertIdx].1.removeAll { $0.id == labelId }
                        }
                    }
                    errorMessage = "Failed to update labels: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Apply a full label set for a task (used by the sheet flow)
    func setLabels(taskId: UUID, to desired: Set<UUID>) async {
        do {
            _ = try await Logger.shared.time("applyLabelSet", category: .perf) {
                try await taskUseCases.setLabels(for: taskId, to: desired, userId: userId)
            }
            // Update local state to reflect final selection
            if let index = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) {
                let newLabels = allLabels.filter { desired.contains($0.id) }
                tasksWithLabels[index].1 = newLabels
            }
        } catch {
            await MainActor.run { self.errorMessage = "Failed to apply labels: \(error.localizedDescription)" }
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
        let effectiveBucket: TimeBucket? = nil
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
            // Board-only: replace in place to minimize flicker
            self.tasksWithLabels = pairs
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
            await fetchTasks(in: nil, showLoading: false)
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
            
            // Include both template tasks and their generated instances
            var recurrenceTaskIds = recurringTemplateIdsCache.intersection(taskIds)
            
            // Also include generated instances that have a parent with an active recurrence
            let deps = Dependencies.shared
            let taskUseCases = try TaskUseCases(
                tasksRepository: deps.resolve(type: TasksRepository.self),
                labelsRepository: deps.resolve(type: LabelsRepository.self)
            )
            
            for taskId in taskIds {
                if let (task, _) = try? await taskUseCases.fetchTaskWithLabels(by: taskId),
                   let parentId = task.parentTaskId,
                   recurringTemplateIdsCache.contains(parentId) {
                    recurrenceTaskIds.insert(taskId)
                }
            }
            
            await MainActor.run { self.tasksWithRecurrence = recurrenceTaskIds }
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
            await self.fetchTasks(in: nil, showLoading: false)
        }
    }

    func applyUnlabeledFilter() {
        self.activeFilterLabelIds.removeAll()
        self.matchAll = false
        self.unlabeledOnly = true
        _Concurrency.Task {
            await self.fetchTasks(in: nil, showLoading: false)
        }
    }

    func setAvailableFilter(_ enabled: Bool) {
        guard self.availableOnly != enabled else { return }
        self.availableOnly = enabled
        _Concurrency.Task {
            await self.fetchTasks(in: nil, showLoading: false)
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
            await self.fetchTasks(in: nil, showLoading: false)
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
        await toggleTaskCompletion(task: task, refreshIn: nil)
    }

    func toggleTaskCompletion(task: Task, refreshIn filter: TimeBucket?) async {
        do {
            let wasCompleted = task.isCompleted
            // Optimistic UI update: reflect new completed state immediately
            if let idx = tasksWithLabels.firstIndex(where: { $0.0.id == task.id }) {
                var pair = tasksWithLabels[idx]
                pair.0.isCompleted.toggle()
                pair.0.completedAt = pair.0.isCompleted ? Date() : nil
                tasksWithLabels[idx] = pair
            }
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
            // Dwell to allow completion feedback to register before removal
            try? await _Concurrency.Task.sleep(nanoseconds: 700_000_000) // 0.7s
            await fetchTasks(in: filter, showLoading: false)
            // Notify working log to refresh if open
            NotificationCenter.default.post(name: Notification.Name("dm.task.completed.changed"), object: nil, userInfo: ["taskId": task.id])
            // If this task just became completed and has a recurrence, generate the next instance
            if wasCompleted == false {
                await generateNextInstanceIfRecurring(templateTaskId: task.id)
            }
            // Present snackbar with Undo when marking complete
            if wasCompleted == false {
                await MainActor.run {
                    self.snackbarMessage = "Task completed"
                    self.snackbarIsPresented = true
                    self.lastCompletedTaskSnapshot = task
                }
            }
        } catch {
            errorMessage = "Failed to toggle task completion: \(error.localizedDescription)"
            Logger.shared.error("Failed to toggle task completion", category: .ui, error: error)
        }
    }

    func undoLastCompletion() async {
        guard let snapshot = lastCompletedTaskSnapshot else { return }
        do {
            _ = try await Logger.shared.time("undoTaskCompletion", category: .perf) {
                try await taskUseCases.toggleTaskCompletion(id: snapshot.id, userId: userId)
            }
            await refreshCounts()
            await fetchTasks(in: nil, showLoading: false)
            await MainActor.run {
                snackbarIsPresented = false
                lastCompletedTaskSnapshot = nil
            }
        } catch {
            await MainActor.run { errorMessage = "Failed to undo: \(error.localizedDescription)" }
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
                await fetchTasks(in: nil)
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

    func completeForever(taskId: UUID) async {
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
            var recurrenceIdToDelete: UUID? = nil
            if let rec = try? await recUC.getByTaskTemplateId(taskId, userId: userId) {
                effectiveTemplateId = taskId
                recurrenceIdToDelete = rec.id
            } else if let (candidate, _) = try? await taskUseCases.fetchTaskWithLabels(by: taskId), let parent = candidate.parentTaskId,
                      let rec = try? await recUC.getByTaskTemplateId(parent, userId: userId) {
                effectiveTemplateId = parent
                recurrenceIdToDelete = rec.id
            } else {
                // No Recurrence row found – fall back to legacy behavior:
                // 1) clear any inline recurrence_rule on the template (or the task itself if it is the template)
                // 2) complete the current task
                if let (candidate, _) = try? await taskUseCases.fetchTaskWithLabels(by: taskId) {
                    // If this is an instance with a parent, attempt to clear recurrence on parent template
                    if let parent = candidate.parentTaskId, var parentTask = try? await taskUseCases.fetchTaskWithLabels(by: parent)?.0 {
                        if parentTask.recurrenceRule != nil {
                            parentTask.recurrenceRule = nil
                            try? await taskUseCases.updateTask(parentTask)
                            Logger.shared.info("Cleared legacy recurrence_rule on parent template=\(parent)", category: .ui)
                        }
                    } else {
                        // Otherwise clear on this task if present
                        var mutable = candidate
                        if mutable.recurrenceRule != nil {
                            mutable.recurrenceRule = nil
                            try? await taskUseCases.updateTask(mutable)
                            Logger.shared.info("Cleared legacy recurrence_rule on template=\(mutable.id)", category: .ui)
                        }
                    }
                }
                // Complete the selected task
                try await taskUseCases.toggleTaskCompletion(id: taskId, userId: userId)
                await refreshCounts()
                await fetchTasks(in: nil, showLoading: false)
                return
            }

            // Delete the recurrence permanently using the recurrence row id
            if let rid = recurrenceIdToDelete {
                try await recUC.delete(id: rid)
                Logger.shared.info("Deleted recurrence for template=\(effectiveTemplateId)", category: .ui)
            }
            
            // Complete the current task
            try await taskUseCases.toggleTaskCompletion(id: taskId, userId: userId)
            Logger.shared.info("Completed task=\(taskId) after stopping recurrence", category: .ui)
            
            await refreshCounts()
            await fetchTasks(in: nil, showLoading: false)
            
            // Show success message
            await MainActor.run {
                self.snackbarMessage = "Recurrence stopped and task completed"
                self.snackbarIsPresented = true
            }
        } catch {
            Logger.shared.error("Failed to complete forever", category: .ui, error: error)
            await MainActor.run {
                self.errorMessage = "Failed to complete forever: \(error.localizedDescription)"
            }
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
            // Duplicate guard: if instance already exists for this parent+due, do not create again; just advance recurrence
            if let children = try? await taskUseCases.fetchSubTasks(for: effectiveTemplateId),
               children.contains(where: { $0.deletedAt == nil && $0.dueAt == next }) {
                var updatedRec = rec
                updatedRec.lastGeneratedAt = Date()
                if let upcoming = recUC.nextOccurrence(from: next, rule: rec.rule) {
                    updatedRec.nextScheduledAt = upcoming
                } else {
                    updatedRec.status = "paused"
                }
                try? await recUC.update(updatedRec)
                await refreshCounts()
                await fetchTasks(in: nil, showLoading: false)
                return
            }

            // Important: link new instance to template via parentTaskId and route to time bucket by due date
            let bucketForInstance = computeAutoBucket(for: next)
            let newTask = Task(userId: template.userId, bucketKey: bucketForInstance, parentTaskId: effectiveTemplateId, title: template.title, description: template.description, dueAt: next)
            try await taskUseCases.createTask(newTask)
            // Persist next scheduled to the next-after-created to align with catch-up logic
            var updatedRec = rec
            updatedRec.lastGeneratedAt = Date()
            if let upcoming = recUC.nextOccurrence(from: next, rule: rec.rule) {
                updatedRec.nextScheduledAt = upcoming
            } else {
                updatedRec.status = "paused"
            }
            try? await recUC.update(updatedRec)
            if let due = newTask.dueAt {
                await NotificationsManager.scheduleDueNotification(taskId: newTask.id, title: newTask.title, dueAt: due, bucketKey: newTask.bucketKey.rawValue)
            }
            // copy labels from template
            let ids = Set(labels.map { $0.id })
            try await taskUseCases.setLabels(for: newTask.id, to: ids, userId: userId)
            await refreshCounts()
            await fetchTasks(in: nil, showLoading: false)
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
                // Respect explicit bucket selection from the form; do not auto-bucket here
                let updated = draft.applying(to: editing)
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
                // Respect explicit bucket selection from the form; do not auto-bucket here
                let newTask = draft.toNewTask()
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
            await fetchTasks(in: nil)
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
            await fetchTasks(in: nil)
        } catch {
            errorMessage = "Failed to delete task: \(error.localizedDescription)"
            Logger.shared.error("Failed to delete task", category: .ui, error: error)
        }
    }

    func confirmCompleteForever(_ task: Task) {
        pendingCompleteForever = task
    }
    
    func performCompleteForever() async {
        guard let task = pendingCompleteForever else { return }
        pendingCompleteForever = nil
        await completeForever(taskId: task.id)
    }
    
    func move(taskId: UUID, to bucket: TimeBucket) async {
        // Respect all-buckets mode when refreshing
        await move(taskId: taskId, to: bucket, refreshIn: nil)
    }

    /// Move task and refresh using a specific filter. Pass `nil` to refresh all buckets (board view).
    func move(taskId: UUID, to bucket: TimeBucket, refreshIn filter: TimeBucket?) async {
        if let idx = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) {
            let task = tasksWithLabels[idx].0
            if task.templateId != nil, task.parentTaskId != nil, bucket != task.bucketKey {
                errorMessage = "Template tasks move automatically. Edit the template to change its schedule."
                return
            }
        }
        do {
            _ = try await Logger.shared.time("reorderCommit_move", category: .perf) {
                try await taskUseCases.moveTask(id: taskId, to: bucket, for: userId)
            }
            // If task is part of a series, mark bucket as an exception using current in-memory copy
            if let idx = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) {
                var task = tasksWithLabels[idx].0
                if task.seriesId != nil {
                    var mask = task.exceptionMask ?? []
                    mask.insert("bucket")
                    task.exceptionMask = mask
                    try? await taskUseCases.updateTask(task)
                }
            }
            await refreshCounts()
            await fetchTasks(in: nil)
        } catch {
            if let domainError = error as? DomainError {
                errorMessage = domainError.errorDescription
            } else {
                errorMessage = "Failed to move task: \(error.localizedDescription)"
            }
            Logger.shared.error("Failed to move task", category: .ui, error: error)
        }
    }

    func addTask(title: String, description: String?, bucket: TimeBucket) async {
        let newTask = Task(userId: userId, bucketKey: bucket, title: title, description: description)
        do {
            try await taskUseCases.createTask(newTask)
            await refreshCounts()
            await fetchTasks(in: nil, showLoading: false)
        } catch {
            errorMessage = "Failed to add task: \(error.localizedDescription)"
            Logger.shared.error("Failed to add task", category: .ui, error: error)
        }
    }
    
    func deleteTask(task: Task) async {
        do {
            try await taskUseCases.deleteTask(by: task.id, for: userId)
            await refreshCounts()
            await fetchTasks(in: nil)
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

    /// Reorder within a bucket or across buckets using canonical position order (ignoring visual sort).
    func reorder(taskId: UUID, to bucket: TimeBucket, insertBeforeId: UUID?) async {
        // Build destination list of incomplete tasks in canonical order (position ASC, createdAt ASC, id ASC)
        // Exclude the moving task from neighbor consideration first
        let stride: Double = 1024
        func canonicalSorted(_ pairs: [(Task, [Label])]) -> [(Task, [Label])] {
            return pairs.sorted { lhs, rhs in
                let lt = lhs.0, rt = rhs.0
                if lt.position != rt.position { return lt.position < rt.position }
                if lt.createdAt != rt.createdAt { return lt.createdAt < rt.createdAt }
                return lt.id.uuidString < rt.id.uuidString
            }
        }

        let current = tasksWithLabels
        guard let movingGlobalIdx = current.firstIndex(where: { $0.0.id == taskId }) else { return }
        let movingPair = current[movingGlobalIdx]
        // movingTask reference not needed; we use movingPair directly
        if movingPair.0.templateId != nil, movingPair.0.parentTaskId != nil, bucket != movingPair.0.bucketKey {
            errorMessage = "Template tasks move automatically. Edit the template to change its schedule."
            return
        }

        let destCandidates = current.filter { $0.0.bucketKey == bucket && $0.0.isCompleted == false && $0.0.id != taskId }
        let destArr = canonicalSorted(destCandidates)

        // Find neighbor positions based on insertBeforeId
        let newPos: Double = {
            if let before = insertBeforeId, let idx = destArr.firstIndex(where: { $0.0.id == before }) {
                // Previous neighbor is the item before idx (if any); next is at idx
                if idx == 0 {
                    // insert at head
                    let nextPos = destArr.first?.0.position ?? 0
                    return nextPos - stride
                } else {
                    let prevPos = destArr[idx - 1].0.position
                    let nextPos = destArr[idx].0.position
                    return (prevPos + nextPos) / 2.0
                }
            } else {
                // Append to end
                let tailPos = destArr.last?.0.position ?? 0
                return tailPos + stride
            }
        }()

        // Optimistic local update: remove from current location and insert near the beforeId in global list for better UX
        var updated = tasksWithLabels
        _ = updated.remove(at: movingGlobalIdx)
        var updatedMoving = movingPair
        updatedMoving.0.bucketKey = bucket
        updatedMoving.0.position = newPos

        // Compute global insertion index using beforeId among incomplete items in destination bucket
        let destIncompleteEnumerated = updated
            .enumerated()
            .filter { $0.element.0.bucketKey == bucket && $0.element.0.isCompleted == false }
            .map { (idx: $0.offset, id: $0.element.0.id) }

        let globalInsertIdx: Int = {
            if let before = insertBeforeId, let found = destIncompleteEnumerated.first(where: { $0.id == before }) {
                return found.idx
            }
            return (destIncompleteEnumerated.last?.idx ?? (updated.endIndex - 1)) + 1
        }()

        updated.insert(updatedMoving, at: min(max(0, globalInsertIdx), updated.count))
        tasksWithLabels = updated
        // Recompute weekday groupings so section UIs reflect new order immediately
        if featureThisWeekSectionsEnabled { deriveThisWeekSectionsAndGroups() }
        if featureNextWeekSectionsEnabled { deriveNextWeekSectionsAndGroups() }

        // Persist remotely
        do {
            _ = try await Logger.shared.time("reorderCommit", category: .perf) {
                try await taskUseCases.updateTaskOrderAndBucket(id: taskId, to: bucket, position: newPos, userId: userId)
            }
        } catch {
            if let domainError = error as? DomainError {
                errorMessage = domainError.errorDescription
            } else {
                errorMessage = "Failed to reorder: \(error.localizedDescription)"
            }
            Logger.shared.error("Failed to reorder task", category: .ui, error: error)
        }
    }
    
    func sync() async {
        guard let syncService = syncService else {
            Logger.shared.info("No sync service available", category: .ui)
            return
        }
        // Client safety net: on Mondays flip NEXT_WEEK → THIS_WEEK for tasks due this week
        if Calendar.current.component(.weekday, from: Date()) == 2 {
            await clientMondayFlipIfNeeded()
        }
        
        await syncService.sync(for: userId)
        // Refresh tasks after sync
        await refreshCounts()
        await fetchTasks(in: nil)
    }
    
    func startPeriodicSync() {
        syncService?.startPeriodicSync(for: userId)
        // Also run client flip guard when timer ticks on Monday
        if Calendar.current.component(.weekday, from: Date()) == 2 {
            _Concurrency.Task { await self.clientMondayFlipIfNeeded() }
        }
    }
    
    func stopPeriodicSync() {
        syncService?.stopPeriodicSync()
    }
    
    func initialSyncIfNeeded() async {
        guard let syncService = syncService else { return }
        await syncService.performInitialSync(for: userId)
    }

    /// Client-side Monday flip: locally move NEXT_WEEK tasks whose due date falls within current Mon..Sun into THIS_WEEK.
    private func clientMondayFlipIfNeeded() async {
        let cal = Calendar.current
        let now = Date()
        let weekMon = WeekPlanner.mondayOfCurrentWeek(for: now, calendar: cal)
        let weekSun = cal.date(byAdding: .day, value: 6, to: weekMon) ?? now
        var changed = false
        for i in tasksWithLabels.indices {
            let t = tasksWithLabels[i].0
            guard t.isCompleted == false, t.bucketKey == .nextWeek else { continue }
            if let due = t.dueAt {
                let start = cal.startOfDay(for: due)
                if start >= weekMon && start <= weekSun {
                    // Persist move so counts and future fetches are correct
                    do {
                        try await taskUseCases.moveTask(id: t.id, to: .thisWeek, for: userId, allowTemplateBucketMutation: true)
                    } catch { }
                    var updated = t; updated.bucketKey = .thisWeek
                    tasksWithLabels[i].0 = updated
                    changed = true
                }
            }
        }
        if changed { await refreshCounts() }
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
        if task.templateId != nil, task.parentTaskId != nil {
            errorMessage = "Template tasks move automatically. Edit the template to change its schedule."
            return
        }
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
            await fetchTasks(in: nil, showLoading: false)
        } catch {
            errorMessage = "Failed to reschedule: \(error.localizedDescription)"
        }
    }

    /// Clear the due date for a task (unschedule). Keeps it in the same bucket.
    func unschedule(taskId: UUID) async {
        guard let idx = tasksWithLabels.firstIndex(where: { $0.0.id == taskId }) else { return }
        var task = tasksWithLabels[idx].0
        if task.templateId != nil, task.parentTaskId != nil {
            errorMessage = "Template tasks move automatically. Edit the template to change its schedule."
            return
        }
        task.dueAt = nil
        task.dueHasTime = false
        do {
            try await taskUseCases.updateTask(task)
            await NotificationsManager.cancelDueNotification(taskId: task.id)
            await fetchTasks(in: nil, showLoading: false)
        } catch {
            errorMessage = "Failed to clear due date: \(error.localizedDescription)"
        }
    }

    /// Deletes recurrence row if it exists for a given template (or parent template if id is an instance)
    private func clearRecurrenceIfExists(taskId: UUID) async {
        guard let recUC = recurrenceUseCases else { return }
        do {
            let deps = Dependencies.shared
            let taskUseCases = try TaskUseCases(
                tasksRepository: deps.resolve(type: TasksRepository.self),
                labelsRepository: deps.resolve(type: LabelsRepository.self)
            )
            // Determine template id
            let effectiveTemplateId: UUID
            if let _ = try? await recUC.getByTaskTemplateId(taskId, userId: userId) {
                effectiveTemplateId = taskId
            } else if let (candidate, _) = try? await taskUseCases.fetchTaskWithLabels(by: taskId), let parent = candidate.parentTaskId,
                      let _ = try? await recUC.getByTaskTemplateId(parent, userId: userId) {
                effectiveTemplateId = parent
            } else {
                return
            }
            // Delete recurrence
            try await recUC.delete(id: effectiveTemplateId)
            Logger.shared.info("Cleared recurrence for template=\(effectiveTemplateId)", category: .ui)
            // Refresh flags and tasks
            await MainActor.run { self.recurrenceCacheDirty = true }
            await refreshCounts()
            await fetchTasks(in: nil, showLoading: false)
        } catch {
            Logger.shared.error("Failed to clear recurrence", category: .ui, error: error)
        }
    }

    // MARK: - Template Exceptions
    func makeException(taskId: UUID, field: String) async {
        do {
            let repo = try Dependencies.shared.resolve(type: TasksRepository.self)
            guard var task = try await repo.fetchTask(by: taskId) else { return }
            var mask = task.exceptionMask ?? []
            mask.insert(field)
            task.exceptionMask = mask
            try await taskUseCases.updateTask(task)
            await fetchTasks(in: nil, showLoading: false)
        } catch {
            Logger.shared.error("Failed to make exception field=\(field)", category: .ui, error: error)
        }
    }
    func reapplyTemplate(taskId: UUID, field: String) async {
        do {
            let repo = try Dependencies.shared.resolve(type: TasksRepository.self)
            guard var task = try await repo.fetchTask(by: taskId) else { return }
            var mask = task.exceptionMask ?? []
            mask.remove(field)
            task.exceptionMask = mask
            // Reapply only allowed for fields we know: title/description/priority/labels/bucket
            if let seriesId = task.seriesId, let tplId = task.templateId {
                // Fetch template to restore defaults
                let deps = Dependencies.shared
                let tplUC = try deps.resolve(type: TemplatesUseCases.self)
                if let tpl = try await tplUC.get(id: tplId, ownerId: userId) {
                    switch field {
                    case "title": task.title = tpl.name
                    case "description": task.description = tpl.description
                    case "priority": task.priority = tpl.priority
                    case "bucket": task.bucketKey = TimeBucket.routines
                    case "labels":
                        let labelIds = Set(tpl.labelsDefault)
                        try? await taskUseCases.setLabels(for: task.id, to: labelIds, userId: userId)
                    default: break
                    }
                }
                _ = seriesId // reserved for future per-series behavior
            }
            try await taskUseCases.updateTask(task)
            await fetchTasks(in: nil, showLoading: false)
        } catch {
            Logger.shared.error("Failed to reapply template field=\(field)", category: .ui, error: error)
        }
    }
}
