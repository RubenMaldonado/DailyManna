//
//  TaskListView.swift
//  DailyManna
//
//  Epic 0.1 Infrastructure Demo View
//  Simple UI to demonstrate modular architecture works
//

import SwiftUI
import UniformTypeIdentifiers

/// Simple view to demonstrate Epic 0.1 architecture is working
/// This is a minimal UI focused on proving the infrastructure
struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    private let userId: UUID
    @EnvironmentObject private var authService: AuthenticationService
    @State private var lastSyncText: String = ""
    // Filter / sheet state
    @State private var showFilterSheet: Bool = false
    @State private var allLabels: [Label] = []
    @State private var savedFilters: [SavedFilter] = []
    @State private var viewMode: ViewMode = .list
    enum ViewMode: String, CaseIterable, Identifiable { case list = "List", board = "Board"; var id: String { rawValue } }
    @Environment(\.scenePhase) private var scenePhase
    // Throttle to avoid re-entrant toolbar updates when opening filter
    @State private var lastFilterOpenAt: TimeInterval = 0
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var showBoard: Bool = false
    #endif
    init(viewModel: TaskListViewModel, userId: UUID) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.userId = userId
    }
    
    // MARK: - Derived state
    private var hasActiveFilters: Bool {
        viewModel.availableOnly || viewModel.unlabeledOnly || viewModel.activeFilterLabelIds.isEmpty == false
    }
    private var activeFilterCount: Int {
        (viewModel.availableOnly ? 1 : 0) + (viewModel.unlabeledOnly ? 1 : 0) + viewModel.activeFilterLabelIds.count
    }

    var body: some View {
        NavigationStack {
        VStack(spacing: 16) {
            if let syncError = viewModel.syncErrorMessage {
                Banner(kind: .error, message: syncError)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .overlay(
                        HStack {
                            Spacer()
                            Button("Retry") { _Concurrency.Task { await viewModel.sync() } }
                                .buttonStyle(SecondaryButtonStyle(size: .small))
                        }
                        .padding(.trailing, 24)
                    )
            }
            if let t = viewModel.pendingDelete {
                Banner(kind: .warning, message: "\"\(t.title)\" will be moved to trash.")
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .overlay(
                        HStack(spacing: 8) {
                            Spacer()
                            Button("Cancel") { viewModel.pendingDelete = nil }
                                .buttonStyle(SecondaryButtonStyle(size: .small))
                            Button("Delete", role: .destructive) { _Concurrency.Task { await viewModel.performDelete() } }
                                .buttonStyle(PrimaryButtonStyle(size: .small))
                        }
                        .padding(.trailing, 24)
                    )
            }
            TopBarView(
                onNew: { viewModel.presentCreateForm() },
                onSyncNow: { _Concurrency.Task { await viewModel.sync() } },
                isSyncing: viewModel.isSyncing,
                userId: userId,
                selectedBucket: viewModel.selectedBucket,
                showBucketMenu: {
                    #if os(macOS)
                    return viewMode != .board
                    #else
                    return viewMode != .board
                    #endif
                }(),
                onSelectBucket: { bucket in
                    Logger.shared.info("Toolbar select bucket=\(bucket.rawValue)", category: .ui)
                    Telemetry.record(.bucketChange, metadata: ["bucket": bucket.rawValue])
                    viewModel.select(bucket: bucket)
                },
                onOpenFilter: {
                    Logger.shared.info("Open filter sheet", category: .ui)
                    Telemetry.record(.filterOpen)
                    let now = Date().timeIntervalSince1970
                    if now - lastFilterOpenAt < 0.3 { return }
                    lastFilterOpenAt = now
                    if showFilterSheet == false { DispatchQueue.main.async { showFilterSheet = true } }
                },
                activeFilterCount: activeFilterCount
            )
            // bucket picker moved to toolbar menu
            // Debug settings moved under gear in top bar
            if viewMode != .board {
                BucketHeader(bucket: viewModel.selectedBucket,
                             count: viewModel.bucketCounts[viewModel.selectedBucket] ?? 0)
                .padding(.horizontal)
            }
            // Active filter chips row (shown only when there are active filters)
            if hasActiveFilters {
                ActiveFiltersChips(
                    labels: allLabels,
                    selectedLabelIds: viewModel.activeFilterLabelIds,
                    availableOnly: viewModel.availableOnly,
                    unlabeledOnly: viewModel.unlabeledOnly,
                    onRemoveLabel: { id in viewModel.activeFilterLabelIds.remove(id); _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) } },
                    onClearAll: { viewModel.clearFilters() }
                )
                .padding(.horizontal)
            }
            contentSection
            Spacer(minLength: 0)
        }
        .background(Colors.background)
        .task {
            await viewModel.refreshCounts()
            await viewModel.fetchTasks(in: viewModel.selectedBucket)
            await viewModel.initialSyncIfNeeded()
            viewModel.startPeriodicSync()
            await loadLabels()
            await loadSaved()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                _Concurrency.Task { await viewModel.sync() }
                viewModel.startPeriodicSync()
            } else if phase == .background || phase == .inactive {
                viewModel.stopPeriodicSync()
            }
        }
        .onAppear {
            _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) }
        }
        .onChange(of: viewMode) { _, newMode in
            Logger.shared.info("View mode changed -> \(newMode.rawValue)", category: .ui)
            Telemetry.record(.viewSwitch, metadata: ["mode": newMode.rawValue])
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.filter.unlabeled"))) { _ in
            viewModel.applyUnlabeledFilter()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.filter.available.toggle"))) { note in
            if let enabled = note.userInfo?["enabled"] as? Bool {
                viewModel.setAvailableFilter(enabled)
            }
        }
        #if os(macOS)
        .onChange(of: viewMode) { _, mode in
            _Concurrency.Task {
                if mode == .board {
                    viewModel.isBoardModeActive = true
                    await viewModel.fetchTasks(in: nil)
                } else {
                    viewModel.isBoardModeActive = false
                    await viewModel.fetchTasks(in: viewModel.selectedBucket)
                }
            }
        }
        #endif
        .sheet(isPresented: $viewModel.isPresentingTaskForm) {
            if let editing = viewModel.editingTask {
                let draft = TaskDraft(from: editing)
                TaskFormView(isEditing: true, draft: draft) { draft in
                    _Concurrency.Task { await viewModel.save(draft: draft) }
                } onCancel: {}
            } else {
                let draft = TaskDraft(userId: userId, bucket: viewModel.selectedBucket)
                TaskComposerView(draft: draft) { draft in
                    _Concurrency.Task { await viewModel.save(draft: draft) }
                } onCancel: {}
                .environmentObject(authService)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterPickerSheet(
                userId: userId,
                selected: $viewModel.activeFilterLabelIds,
                availableOnly: $viewModel.availableOnly,
                unlabeledOnly: $viewModel.unlabeledOnly,
                matchAll: $viewModel.matchAll,
                savedFilters: savedFilters,
                onApply: {
                    Telemetry.record(.filterApply)
                    _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) }
                },
                onClear: {
                    viewModel.clearFilters()
                    Telemetry.record(.filterClear)
                }
            )
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "rectangle.grid.2x2").tag(ViewMode.board)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
        #endif
        #if !os(macOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if hSizeClass == .regular {
                    HStack(spacing: 8) {
                        Button { viewMode = .list } label: { Image(systemName: "list.bullet") }
                            .buttonStyle(viewMode == .list ? PrimaryButtonStyle(size: .small) : SecondaryButtonStyle(size: .small))
                            .keyboardShortcut("1", modifiers: .command)
                        Button { viewMode = .board } label: { Image(systemName: "rectangle.grid.2x2") }
                            .buttonStyle(viewMode == .board ? PrimaryButtonStyle(size: .small) : SecondaryButtonStyle(size: .small))
                            .keyboardShortcut("2", modifiers: .command)
                    }
                } else {
                    Menu {
                        Button(action: { viewMode = .list }) { Label("List", systemImage: "list.bullet"); if viewMode == .list { Image(systemName: "checkmark") } }
                        Button(action: { viewMode = .board }) { Label("Board", systemImage: "rectangle.grid.2x2"); if viewMode == .board { Image(systemName: "checkmark") } }
                    } label: {
                        Image(systemName: viewMode == .list ? "list.bullet" : "rectangle.grid.2x2")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.open.task"))) { note in
            if let id = note.userInfo?["taskId"] as? UUID {
                if let bucketStr = note.userInfo?["bucket_key"] as? String, let bucket = TimeBucket(rawValue: bucketStr) {
                    viewModel.selectedBucket = bucket
                }
                _Concurrency.Task {
                    await viewModel.fetchTasks(in: viewModel.selectedBucket)
                    if let task = viewModel.tasksWithLabels.first(where: { $0.0.id == id })?.0 {
                        viewModel.presentEditForm(task: task)
                    }
                }
            }
        }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        #if os(macOS)
        if viewMode == .board {
            if let errorMessage = viewModel.errorMessage {
                Banner(kind: .error, message: errorMessage).padding(.horizontal)
            }
            InlineBoardView(viewModel: viewModel)
        } else {
            if viewModel.isLoading {
                VStack(spacing: 12) { SkeletonTaskCard(); SkeletonTaskCard(); SkeletonTaskCard() }
                    .padding(.horizontal)
            } else if let errorMessage = viewModel.errorMessage {
                Banner(kind: .error, message: errorMessage)
                    .padding(.horizontal)
            } else if viewModel.tasksWithLabels.isEmpty {
                EmptyStateView(bucketName: viewModel.selectedBucket.displayName)
                    .padding(.horizontal)
            } else {
                TasksListView(
                    bucket: viewModel.selectedBucket,
                    tasksWithLabels: viewModel.tasksWithLabels,
                    subtaskProgressByParent: viewModel.subtaskProgressByParent,
                    onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                    onEdit: { task in viewModel.presentEditForm(task: task) },
                    onMove: { taskId, bucket in _Concurrency.Task { await viewModel.move(taskId: taskId, to: bucket) } },
                    onReorder: { taskId, targetIndex in _Concurrency.Task { await viewModel.reorder(taskId: taskId, to: viewModel.selectedBucket, targetIndex: targetIndex) } },
                    onDelete: { task in viewModel.confirmDelete(task) }
                )
                .transaction { $0.disablesAnimations = true }
            }
        }
        #else
        if viewModel.isLoading {
            VStack(spacing: 12) { SkeletonTaskCard(); SkeletonTaskCard(); SkeletonTaskCard() }
                .padding(.horizontal)
        } else if let errorMessage = viewModel.errorMessage {
            Banner(kind: .error, message: errorMessage)
                .padding(.horizontal)
        } else if viewModel.tasksWithLabels.isEmpty {
            EmptyStateView(bucketName: viewModel.selectedBucket.displayName)
                .padding(.horizontal)
        } else {
            TasksListView(
                bucket: viewModel.selectedBucket,
                tasksWithLabels: viewModel.tasksWithLabels,
                subtaskProgressByParent: viewModel.subtaskProgressByParent,
                onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                onEdit: { task in viewModel.presentEditForm(task: task) },
                onMove: { taskId, bucket in _Concurrency.Task { await viewModel.move(taskId: taskId, to: bucket) } },
                onReorder: { taskId, targetIndex in _Concurrency.Task { await viewModel.reorder(taskId: taskId, to: viewModel.selectedBucket, targetIndex: targetIndex) } },
                onDelete: { task in viewModel.confirmDelete(task) }
            )
            .transaction { $0.disablesAnimations = true }
        }
        #endif
    }
}

#if os(macOS)
// Inline board content to avoid navigation/title/toolbars from BucketBoardView
private struct InlineBoardView: View {
    @ObservedObject var viewModel: TaskListViewModel
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.medium) {
                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                    InlineBucketColumn(
                        bucket: bucket,
                        tasksWithLabels: viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket },
                        subtaskProgressByParent: viewModel.subtaskProgressByParent,
                        tasksWithRecurrence: viewModel.tasksWithRecurrence,
                        onDropTask: { taskId, targetIndex in
                            _Concurrency.Task {
                                await viewModel.reorder(taskId: taskId, to: bucket, targetIndex: targetIndex)
                            }
                        },
                        onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task, refreshIn: nil) } },
                        onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                        onEdit: { task in viewModel.presentEditForm(task: task) },
                        onDelete: { task in viewModel.confirmDelete(task) },
                        onPauseResume: { id in _Concurrency.Task { await viewModel.pauseResume(taskId: id) } },
                        onSkipNext: { id in _Concurrency.Task { await viewModel.skipNext(taskId: id) } },
                        onGenerateNow: { id in _Concurrency.Task { await viewModel.generateNow(taskId: id) } }
                    )
                }
            }
            .padding()
            .transaction { txn in txn.disablesAnimations = true }
        }
        // Disable implicit animations for data changes to avoid snap-back
    }
}

private struct InlineBucketColumn: View {
    let bucket: TimeBucket
    let tasksWithLabels: [(Task, [Label])]
    let subtaskProgressByParent: [UUID: (completed: Int, total: Int)]
    let tasksWithRecurrence: Set<UUID>
    let onDropTask: (UUID, Int) -> Void
    let onToggle: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void
    let onPauseResume: (UUID) -> Void
    let onSkipNext: (UUID) -> Void
    let onGenerateNow: (UUID) -> Void
    @State private var rowFrames: [UUID: CGRect] = [:]
    // drag indicator state
    @State private var isDragActive: Bool = false
    @State private var insertBeforeId: UUID? = nil
    @State private var showEndIndicator: Bool = false
    // cached frames snapshot for a drag session to avoid layout churn
    @State private var dragFrames: [UUID: CGRect] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: bucket, count: tasksWithLabels.count)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(tasksWithLabels, id: \.0.id) { pair in
                        if isDragActive && insertBeforeId == pair.0.id {
                            Rectangle()
                                .fill(Colors.primary)
                                .frame(height: 2)
                                .padding(.vertical, 2)
                        }
                        TaskCard(
                            task: pair.0,
                            labels: pair.1,
                            onToggleCompletion: { onToggle(pair.0) },
                            subtaskProgress: subtaskProgressByParent[pair.0.id],
                            showsRecursIcon: tasksWithRecurrence.contains(pair.0.id),
                            onPauseResume: { onPauseResume(pair.0.id) },
                            onSkipNext: { onSkipNext(pair.0.id) },
                            onGenerateNow: { onGenerateNow(pair.0.id) }
                        )
                            .contextMenu {
                                Menu("Move to") {
                                    ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { dest in
                                        Button(dest.displayName) { onMove(pair.0.id, dest) }
                                    }
                                }
                                Button("Edit") { onEdit(pair.0) }
                                Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                            }
                            .onTapGesture(count: 2) { onEdit(pair.0) }
                            .draggable(DraggableTaskID(id: pair.0.id))
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: RowFramePreferenceKey.self, value: [pair.0.id: proxy.frame(in: .named("columnDrop"))])
                            })
                    }
                    if isDragActive && showEndIndicator {
                        Rectangle()
                            .fill(Colors.primary)
                            .frame(height: 2)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, Spacing.xSmall)
                .transaction { $0.disablesAnimations = true }
                .onPreferenceChange(RowFramePreferenceKey.self) { value in
                    let merged = rowFrames.merging(value) { _, new in new }
                    if merged != rowFrames {
                        rowFrames = merged
                    }
                }
            }
        }
        .frame(width: 320)
        .padding(.vertical, Spacing.small)
        .surfaceStyle(.content)
        .cornerRadius(12)
        .coordinateSpace(name: "columnDrop")
        #if os(macOS)
        .onDrop(of: [UTType.plainText], delegate: InlineColumnDropDelegate(
            tasksWithLabels: tasksWithLabels,
            rowFramesProvider: { rowFrames },
            snapshotFramesProvider: { dragFrames.isEmpty ? rowFrames : dragFrames },
            insertBeforeId: $insertBeforeId,
            showEndIndicator: $showEndIndicator,
            isDragActive: $isDragActive,
            onDropTask: onDropTask,
            onBegin: { dragFrames = rowFrames },
            onEnd: { dragFrames = [:] }
        ))
        #else
        .dropDestination(for: DraggableTaskID.self) { items, location in
            guard let item = items.first else { return false }
            let incomplete = tasksWithLabels.filter { !$0.0.isCompleted }
            let orderedIds = incomplete.map { $0.0.id }
            let frames = dragFrames.isEmpty ? rowFrames : dragFrames
            let sortedRects: [(Int, CGRect)] = orderedIds.enumerated().compactMap { idx, id in
                if let rect = frames[id] { return (idx, rect) } else { return nil }
            }.sorted { $0.1.minY < $1.1.minY }
            var targetIndex = sortedRects.endIndex
            for (idx, rect) in sortedRects {
                if location.y < rect.midY { targetIndex = idx; break }
            }
            insertBeforeId = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
            showEndIndicator = targetIndex >= orderedIds.count
            onDropTask(item.id, targetIndex)
            return true
        } isTargeted: { inside in
            isDragActive = inside
            if inside {
                if dragFrames.isEmpty { dragFrames = rowFrames }
            } else { insertBeforeId = nil; showEndIndicator = false; dragFrames = [:] }
        }
        #endif
    }
}

#if os(macOS)
private struct InlineColumnDropDelegate: DropDelegate {
    let tasksWithLabels: [(Task, [Label])]
    let rowFramesProvider: () -> [UUID: CGRect]
    let snapshotFramesProvider: () -> [UUID: CGRect]
    @Binding var insertBeforeId: UUID?
    @Binding var showEndIndicator: Bool
    @Binding var isDragActive: Bool
    let onDropTask: (UUID, Int) -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isDragActive = true
        onBegin()
        return info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        isDragActive = true
        onBegin()
        updateIndicator(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator(info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { reset(); return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            guard let data = data, let str = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: str) else { DispatchQueue.main.async { reset() }; return }
            DispatchQueue.main.async {
                let (targetIndex, _) = computeTargetIndex(for: info.location)
                onDropTask(uuid, targetIndex)
                reset()
            }
        }
        return true
    }

    func dropExited(info: DropInfo) { reset() }

    private func reset() { insertBeforeId = nil; showEndIndicator = false; isDragActive = false; onEnd() }

    private func updateIndicator(_ info: DropInfo) {
        let (targetIndex, orderedIds) = computeTargetIndex(for: info.location)
        insertBeforeId = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
        showEndIndicator = targetIndex >= orderedIds.count
    }

    private func computeTargetIndex(for location: CGPoint) -> (Int, [UUID]) {
        let incomplete = tasksWithLabels.filter { !$0.0.isCompleted }
        let orderedIds = incomplete.map { $0.0.id }
        let liveFrames = rowFramesProvider()
        let snap = snapshotFramesProvider()
        let frames = snap.isEmpty ? liveFrames : snap
        let sortedRects: [(Int, CGRect)] = orderedIds.enumerated().compactMap { idx, id in
            if let rect = frames[id] { return (idx, rect) } else { return nil }
        }.sorted { $0.1.minY < $1.1.minY }
        var targetIndex = sortedRects.endIndex
        for (idx, rect) in sortedRects { if location.y < rect.midY { targetIndex = idx; break } }
        return (targetIndex, orderedIds)
    }
}
#endif

private struct RowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
#endif
private extension TaskListView {}

// MARK: - Data loaders for filters
private extension TaskListView {
    func loadLabels() async {
        let deps = Dependencies.shared
        if let useCases: LabelUseCases = try? deps.resolve(type: LabelUseCases.self) {
            if let uid = authService.currentUser?.id {
                allLabels = (try? await useCases.fetchLabels(for: uid)) ?? []
            }
        }
    }
    func loadSaved() async {
        let deps = Dependencies.shared
        if let repo: SavedFiltersRepository = try? deps.resolve(type: SavedFiltersRepository.self) {
            if let uid = authService.currentUser?.id {
                savedFilters = (try? await repo.list(for: uid)) ?? []
            }
        }
    }
}

// MARK: - Extracted Subviews

private struct TopBarView: View {
    let onNew: () -> Void
    let onSyncNow: () -> Void
    let isSyncing: Bool
    let userId: UUID
    let selectedBucket: TimeBucket
    let showBucketMenu: Bool
    let onSelectBucket: (TimeBucket) -> Void
    let onOpenFilter: () -> Void
    let activeFilterCount: Int
    @State private var showSettings = false
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Daily Manna").style(Typography.title2).foregroundColor(Colors.onSurface)
                SyncStatusView(isSyncing: isSyncing)
            }
            Spacer()
            // Bucket menu
            if showBucketMenu {
                Menu {
                    ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                        Button(action: { onSelectBucket(bucket) }) {
                            HStack { Text(bucket.displayName); if bucket == selectedBucket { Spacer(); Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    HStack(spacing: 6) { Image(systemName: "tray" ); Text(selectedBucket.displayName).fixedSize(horizontal: true, vertical: false) }
                }
                .menuStyle(.borderlessButton)
            }
            // Filter button
            Button(action: onOpenFilter) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    if activeFilterCount > 0 { CountBadge(count: activeFilterCount) }
                }
            }
            .buttonStyle(SecondaryButtonStyle(size: .small))
            .accessibilityLabel(activeFilterCount > 0 ? "Filters, \(activeFilterCount) active" : "Filters")
            Button(action: onSyncNow) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(SecondaryButtonStyle(size: .small))
            Button(action: onNew) { SwiftUI.Label("New", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle(size: .small))
            Button(action: { showSettings = true }) { Image(systemName: "gearshape") }
                .buttonStyle(SecondaryButtonStyle(size: .small))
                .sheet(isPresented: $showSettings) {
                    let deps = Dependencies.shared
                    let vm = SettingsViewModel(
                        tasksRepository: try! deps.resolve(type: TasksRepository.self),
                        labelsRepository: try! deps.resolve(type: LabelsRepository.self),
                        remoteTasksRepository: try! deps.resolve(type: RemoteTasksRepository.self),
                        remoteLabelsRepository: try! deps.resolve(type: RemoteLabelsRepository.self),
                        syncService: try! deps.resolve(type: SyncService.self),
                        userId: userId
                    )
                    SettingsView(viewModel: vm)
                }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
        .overlay(
            // Hidden keyboard shortcuts for power users (iOS/iPad/macOS where applicable)
            HStack(spacing: 0) {
                Button("") { onOpenFilter() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0.0)
                Button("") { onNew() }
                    .keyboardShortcut("n", modifiers: .command)
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0.0)
            }
        )
    }
}

// Compact, non-reflowing sync status indicator
private struct SyncStatusView: View {
    let isSyncing: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isSyncing ? Colors.onSurfaceVariant : Colors.success)
                .frame(width: 8, height: 8)
            // Reserve width to avoid layout shifts when caption changes
            Text(isSyncing ? "Syncing…" : "Up to date")
                .style(Typography.caption)
                .foregroundColor(isSyncing ? Colors.onSurfaceVariant : Colors.success)
                .frame(width: 80, alignment: .leading)
                .accessibilityLabel(isSyncing ? "Sync in progress" : "Up to date")
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FilterPickerSheet: View {
    let userId: UUID
    @Binding var selected: Set<UUID>
    @Binding var availableOnly: Bool
    @Binding var unlabeledOnly: Bool
    @Binding var matchAll: Bool
    let savedFilters: [SavedFilter]
    let onApply: () -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var labels: [Label] = []
    // Local working copy to avoid parent updates during layout
    @State private var localSelected: Set<UUID>
    @State private var localAvailableOnly: Bool
    @State private var localUnlabeledOnly: Bool
    @State private var localMatchAll: Bool
    // Save dialog
    @State private var showSaveDialog: Bool = false
    @State private var saveName: String = ""

    init(userId: UUID,
         selected: Binding<Set<UUID>>,
         availableOnly: Binding<Bool>,
         unlabeledOnly: Binding<Bool>,
         matchAll: Binding<Bool>,
         savedFilters: [SavedFilter],
         onApply: @escaping () -> Void,
         onClear: @escaping () -> Void) {
        self.userId = userId
        _selected = selected
        _availableOnly = availableOnly
        _unlabeledOnly = unlabeledOnly
        _matchAll = matchAll
        self.savedFilters = savedFilters
        self.onApply = onApply
        self.onClear = onClear
        _localSelected = State(initialValue: selected.wrappedValue)
        _localAvailableOnly = State(initialValue: availableOnly.wrappedValue)
        _localUnlabeledOnly = State(initialValue: unlabeledOnly.wrappedValue)
        _localMatchAll = State(initialValue: matchAll.wrappedValue)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Built-ins
                    Text("Built-in").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Available", isOn: $localAvailableOnly)
                        Toggle("Unlabeled only", isOn: $localUnlabeledOnly)
                        Toggle("Match all labels", isOn: $localMatchAll)
                    }
                    .padding(.bottom, 8)

                    // Presets
                    Text("Presets").font(.headline)
                    if savedFilters.isEmpty {
                        Text("No saved filters").foregroundStyle(Colors.onSurfaceVariant)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(savedFilters) { filter in
                                Button(filter.name) {
                                    localSelected = Set(filter.labelIds)
                                    localMatchAll = filter.matchAll
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    Button("Save Current…") { showSaveDialog = true }
                        .buttonStyle(SecondaryButtonStyle(size: .small))

                    // Labels
                    Text("Labels").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { label in
                            HStack {
                                Image(systemName: localSelected.contains(label.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(localSelected.contains(label.id) ? Colors.primary : Colors.onSurfaceVariant)
                                Circle().fill(label.uiColor).frame(width: 14, height: 14)
                                Text(label.name)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(label.id) }
                        }
                    }

                    // Bottom actions
                    HStack {
                        Button("Clear All") {
                            dismiss()
                            DispatchQueue.main.async { onClear() }
                        }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                        Spacer()
                        Button("Apply") {
                            selected = localSelected
                            availableOnly = localAvailableOnly
                            unlabeledOnly = localUnlabeledOnly
                            matchAll = localMatchAll
                            dismiss()
                            DispatchQueue.main.async { onApply() }
                        }
                        .buttonStyle(PrimaryButtonStyle(size: .small))
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Filters")
            .searchable(text: $search)
            .task { await load() }
            .sheet(isPresented: $showSaveDialog) { saveSheet }
        }
    }
    private func load() async {
        let deps = Dependencies.shared
        if let useCases: LabelUseCases = try? deps.resolve(type: LabelUseCases.self) {
            labels = (try? await useCases.fetchLabels(for: userId)) ?? []
        }
    }
    private var filtered: [Label] { let q = search.trimmingCharacters(in: .whitespacesAndNewlines); return q.isEmpty ? labels : labels.filter { $0.name.localizedCaseInsensitiveContains(q) } }
    private func toggle(_ id: UUID) { if localSelected.contains(id) { localSelected.remove(id) } else { localSelected.insert(id) } }

    @ViewBuilder
    private var saveSheet: some View {
        VStack(spacing: 12) {
            Text("Save Filter").font(.headline)
            TextField("Name", text: $saveName).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showSaveDialog = false }
                Spacer()
                Button("Save") {
                    let deps = Dependencies.shared
                    if let repo: SavedFiltersRepository = try? deps.resolve(type: SavedFiltersRepository.self) {
                        _Concurrency.Task {
                            try? await repo.create(name: saveName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   labelIds: Array(localSelected),
                                                   matchAll: localMatchAll,
                                                   userId: userId)
                            saveName = ""
                            showSaveDialog = false
                        }
                    }
                }.disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(minWidth: 320)
    }
}

private struct ActiveFiltersChips: View {
    let labels: [Label]
    let selectedLabelIds: Set<UUID>
    let availableOnly: Bool
    let unlabeledOnly: Bool
    let onRemoveLabel: (UUID) -> Void
    let onClearAll: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            if availableOnly { Pill(text: "Available", onClear: {}) }
            if unlabeledOnly { Pill(text: "Unlabeled", onClear: {}) }
            ForEach(Array(selectedLabelIds), id: \.self) { id in
                if let label = labels.first(where: { $0.id == id }) {
                    HStack(spacing: 4) {
                        LabelChip(label: label)
                        Button(role: .destructive) { onRemoveLabel(id) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            Button("Clear") { onClearAll() }
                .buttonStyle(SecondaryButtonStyle(size: .small))
        }
    }
}

// SyncStatusRow removed; status moved into the top bar

private struct BucketPickerView: View {
    @Binding var selected: TimeBucket
    let onChange: (TimeBucket) -> Void
    
    var body: some View {
        Picker("Bucket", selection: $selected) {
            ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                Text(bucket.displayName).tag(bucket)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: selected) { _, newValue in onChange(newValue) }
    }
}

#if os(macOS)
// Removed standalone in-content ViewModePicker; toolbar picker is used instead.
#endif

// QuickAddComposer removed by request

private struct EmptyStateView: View {
    let bucketName: String
    var body: some View {
        VStack(spacing: 8) {
            Text("No tasks in \(bucketName)").style(Typography.body)
            Text("Add a task to get started").style(Typography.caption).foregroundColor(Colors.onSurfaceVariant)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .surfaceStyle(.content)
        .cornerRadius(12)
    }
}

// MARK: - Debug Settings
#if DEBUG
private struct DebugSettingsButton: View {
    let userId: UUID
    @State private var showSettings = false
    
    var body: some View {
        Button("Settings") { showSettings = true }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showSettings) {
                let deps = Dependencies.shared
                let vm = SettingsViewModel(
                    tasksRepository: try! deps.resolve(type: TasksRepository.self),
                    labelsRepository: try! deps.resolve(type: LabelsRepository.self),
                    remoteTasksRepository: try! deps.resolve(type: RemoteTasksRepository.self),
                    remoteLabelsRepository: try! deps.resolve(type: RemoteLabelsRepository.self),
                    syncService: try! deps.resolve(type: SyncService.self),
                    userId: userId
                )
                SettingsView(viewModel: vm)
            }
    }
}
#endif

private struct Deprecated_TasksListView: View { // kept temporarily if referenced elsewhere
    let bucket: TimeBucket
    let tasksWithLabels: [(Task, [Label])]
    let subtaskProgressByParent: [UUID: (completed: Int, total: Int)]
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onReorder: (UUID, Int) -> Void
    let onDelete: (Task) -> Void
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var insertBeforeId: UUID? = nil
    @State private var showEndIndicator: Bool = false
    @State private var isDragActive: Bool = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(tasksWithLabels, id: \.0.id) { pair in
                    if isDragActive && insertBeforeId == pair.0.id {
                        Rectangle()
                            .fill(Colors.primary)
                            .frame(height: 2)
                            .padding(.vertical, 2)
                    }
                    TaskRowView(task: pair.0, labels: pair.1, subtaskProgress: subtaskProgressByParent[pair.0.id], onToggle: onToggle, onEdit: onEdit, onMove: onMove, onDelete: onDelete)
                        .draggable(DraggableTaskID(id: pair.0.id))
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ListRowFramePreferenceKey.self, value: [pair.0.id: proxy.frame(in: .named("listDrop"))])
                        })
                }
                if isDragActive && showEndIndicator {
                    Rectangle()
                        .fill(Colors.primary)
                        .frame(height: 2)
                        .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, Spacing.medium)
            .onPreferenceChange(ListRowFramePreferenceKey.self) { value in
                rowFrames.merge(value) { _, new in new }
            }
        }
        .coordinateSpace(name: "listDrop")
        #if os(macOS)
        .onDrop(of: [UTType.plainText], delegate: InlineColumnDropDelegate(
            tasksWithLabels: tasksWithLabels,
            rowFramesProvider: { rowFrames },
            snapshotFramesProvider: { rowFrames },
            insertBeforeId: $insertBeforeId,
            showEndIndicator: $showEndIndicator,
            isDragActive: $isDragActive,
            onDropTask: { taskId, targetIndex in onReorder(taskId, targetIndex) },
            onBegin: {},
            onEnd: {}
        ))
        #else
        .dropDestination(for: DraggableTaskID.self) { items, location in
            guard let item = items.first else { return false }
            let incomplete = tasksWithLabels.filter { !$0.0.isCompleted }
            let orderedIds = incomplete.map { $0.0.id }
            let sortedRects: [(Int, CGRect)] = orderedIds.enumerated().compactMap { idx, id in
                if let rect = rowFrames[id] { return (idx, rect) } else { return nil }
            }.sorted { $0.1.minY < $1.1.minY }
            var targetIndex = sortedRects.endIndex
            for (idx, rect) in sortedRects {
                if location.y < rect.midY { targetIndex = idx; break }
            }
            insertBeforeId = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
            showEndIndicator = targetIndex >= orderedIds.count
            onReorder(item.id, targetIndex)
            return true
        } isTargeted: { inside in
            isDragActive = inside
            if inside == false { insertBeforeId = nil; showEndIndicator = false }
        }
        #endif
    }
}

private struct ListRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TaskRowView: View {
    let task: Task
    let labels: [Label]
    let subtaskProgress: (completed: Int, total: Int)?
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onDelete: (Task) -> Void
    @EnvironmentObject private var viewModel: TaskListViewModel
    
    var body: some View {
        TaskCard(task: task, labels: labels, onToggleCompletion: { onToggle(task) }, subtaskProgress: subtaskProgress, showsRecursIcon: viewModel.tasksWithRecurrence.contains(task.id), onPauseResume: { _Concurrency.Task { await viewModel.pauseResume(taskId: task.id) } }, onSkipNext: { _Concurrency.Task { await viewModel.skipNext(taskId: task.id) } }, onGenerateNow: { _Concurrency.Task { await viewModel.generateNow(taskId: task.id) } })
            .contextMenu {
                Button("Edit") { onEdit(task) }
                    #if os(macOS)
                    .keyboardShortcut(.return)
                    #endif
                Menu("Move to") {
                    ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                        Button(bucket.displayName) { onMove(task.id, bucket) }
                    }
                }
                Button(role: .destructive) { onDelete(task) } label: { Text("Delete") }
                    #if os(macOS)
                    .keyboardShortcut(.delete, modifiers: [])
                    #endif
            }
            .accessibilityActions {
                Button(task.isCompleted ? "Mark incomplete" : "Mark complete") { onToggle(task) }
                Button("Delete") { onDelete(task) }
            }
            #if os(iOS)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { onDelete(task) } label: { SwiftUI.Label("Delete", systemImage: "trash") }
                Button { onEdit(task) } label: { SwiftUI.Label("Edit", systemImage: "pencil") }
            }
            #endif
            #if os(macOS)
            // Hidden keyboard shortcuts for quick actions
            .overlay(
                HStack(spacing: 0) {
                    Button("") { onEdit(task) }
                        .keyboardShortcut(.return)
                        .buttonStyle(.plain)
                        .frame(width: 0, height: 0)
                        .opacity(0.0)
                    Button("") { onDelete(task) }
                        .keyboardShortcut(.delete, modifiers: [])
                        .buttonStyle(.plain)
                        .frame(width: 0, height: 0)
                        .opacity(0.0)
                    Button("") { onToggle(task) }
                        .keyboardShortcut(.space, modifiers: [])
                        .buttonStyle(.plain)
                        .frame(width: 0, height: 0)
                        .opacity(0.0)
                }
            )
            #endif
    }
}

// MARK: - Architecture Status Component
private struct ArchitectureStatusRow: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Colors.onSurface)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Colors.onSurfaceVariant)
            }
            Spacer()
        }
    }
}

#Preview {
    Text("Epic 0.1 Architecture Demo")
        .font(.title)
        .foregroundColor(Colors.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Colors.background)
}
