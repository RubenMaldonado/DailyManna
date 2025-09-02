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
    @State private var newTaskTitle: String = ""
    @State private var lastSyncText: String = ""
    #if os(macOS)
    @State private var viewMode: ViewMode = .list
    enum ViewMode: String, CaseIterable, Identifiable { case list = "List", board = "Board"; var id: String { rawValue } }
    #endif
    @Environment(\.scenePhase) private var scenePhase
    init(viewModel: TaskListViewModel, userId: UUID) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.userId = userId
    }
    
    var body: some View {
        NavigationStack {
        VStack(spacing: 16) {
            TopBarView(onNew: { viewModel.presentCreateForm() }, onSyncNow: { _Concurrency.Task { await viewModel.sync() } }, isSyncing: viewModel.isSyncing, userId: userId)
            #if os(macOS)
            if viewMode == .list {
                BucketPickerView(selected: $viewModel.selectedBucket) { bucket in
                    viewModel.select(bucket: bucket)
                }
            }
            ViewModePicker(viewMode: $viewMode)
            #else
            BucketPickerView(selected: $viewModel.selectedBucket) { bucket in
                viewModel.select(bucket: bucket)
            }
            #endif
            // Debug settings moved under gear in top bar
            BucketHeader(bucket: viewModel.selectedBucket,
                         count: viewModel.bucketCounts[viewModel.selectedBucket] ?? 0)
            .padding(.horizontal)
            // New inline filter components
            InlineFilterSection(userId: userId, viewModel: viewModel)
            QuickAddComposer(newTaskTitle: $newTaskTitle, onAdd: addCurrentTask)
            contentSection
            Spacer(minLength: 0)
        }
        .background(Colors.background)
        .task {
            await viewModel.refreshCounts()
            await viewModel.fetchTasks(in: viewModel.selectedBucket)
            await viewModel.initialSyncIfNeeded()
            viewModel.startPeriodicSync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                _Concurrency.Task { await viewModel.sync() }
            }
        }
        .onAppear {
            _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.filter.unlabeled"))) { _ in
            viewModel.applyUnlabeledFilter()
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
            let draft = viewModel.editingTask.map(TaskDraft.init(from:)) ?? TaskDraft(userId: userId, bucket: viewModel.selectedBucket)
            TaskFormView(isEditing: viewModel.editingTask != nil, draft: draft) { draft in
                _Concurrency.Task { await viewModel.save(draft: draft) }
            } onCancel: {}
        }
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
        .alert("Delete Task?", isPresented: Binding(get: { viewModel.pendingDelete != nil }, set: { if !$0 { viewModel.pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { _Concurrency.Task { await viewModel.performDelete() } }
        } message: {
            if let t = viewModel.pendingDelete { Text("\"\(t.title)\" will be moved to trash.") }
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
                        onDropTask: { taskId, targetIndex in
                            _Concurrency.Task {
                                await viewModel.reorder(taskId: taskId, to: bucket, targetIndex: targetIndex)
                            }
                        },
                        onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task, refreshIn: nil) } },
                        onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                        onEdit: { task in viewModel.presentEditForm(task: task) },
                        onDelete: { task in viewModel.confirmDelete(task) }
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
    let onDropTask: (UUID, Int) -> Void
    let onToggle: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void
    @State private var rowFrames: [UUID: CGRect] = [:]
    // drag indicator state
    @State private var isDragActive: Bool = false
    @State private var insertBeforeId: UUID? = nil
    @State private var showEndIndicator: Bool = false
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
                            showsRecursIcon: viewModel.tasksWithRecurrence.contains(pair.0.id),
                            onPauseResume: { _Concurrency.Task { await viewModel.pauseResume(taskId: pair.0.id) } },
                            onSkipNext: { _Concurrency.Task { await viewModel.skipNext(taskId: pair.0.id) } },
                            onGenerateNow: { _Concurrency.Task { await viewModel.generateNow(taskId: pair.0.id) } }
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
                    rowFrames.merge(value) { _, new in new }
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
            insertBeforeId: $insertBeforeId,
            showEndIndicator: $showEndIndicator,
            isDragActive: $isDragActive,
            onDropTask: onDropTask
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
            onDropTask(item.id, targetIndex)
            return true
        } isTargeted: { inside in
            isDragActive = inside
            if inside == false { insertBeforeId = nil; showEndIndicator = false }
        }
        #endif
    }
}

#if os(macOS)
private struct InlineColumnDropDelegate: DropDelegate {
    let tasksWithLabels: [(Task, [Label])]
    let rowFramesProvider: () -> [UUID: CGRect]
    @Binding var insertBeforeId: UUID?
    @Binding var showEndIndicator: Bool
    @Binding var isDragActive: Bool
    let onDropTask: (UUID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isDragActive = true
        return info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        isDragActive = true
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

    private func reset() { insertBeforeId = nil; showEndIndicator = false; isDragActive = false }

    private func updateIndicator(_ info: DropInfo) {
        let (targetIndex, orderedIds) = computeTargetIndex(for: info.location)
        insertBeforeId = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
        showEndIndicator = targetIndex >= orderedIds.count
    }

    private func computeTargetIndex(for location: CGPoint) -> (Int, [UUID]) {
        let incomplete = tasksWithLabels.filter { !$0.0.isCompleted }
        let orderedIds = incomplete.map { $0.0.id }
        let frames = rowFramesProvider()
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
private extension TaskListView {
    func addCurrentTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _Concurrency.Task {
            await viewModel.addTask(title: title, description: nil, bucket: viewModel.selectedBucket)
            await viewModel.refreshCounts()
        }
        newTaskTitle = ""
    }
}

// MARK: - Extracted Subviews

private struct TopBarView: View {
    let onNew: () -> Void
    let onSyncNow: () -> Void
    let isSyncing: Bool
    let userId: UUID
    @State private var showSettings = false
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Manna").style(Typography.title2).foregroundColor(Colors.onSurface)
                HStack(spacing: 6) {
                    if isSyncing { ProgressView().scaleEffect(0.7) }
                    Text(isSyncing ? "Syncing…" : "Up to date").style(Typography.caption).foregroundColor(isSyncing ? Colors.onSurfaceVariant : Colors.success)
                }
            }
            Spacer()
            Button(action: onSyncNow) { SwiftUI.Label("Sync", systemImage: "arrow.clockwise") }
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
        .padding(.horizontal)
    }
}

// MARK: - Filter Bar
private struct FilterBar: View {
    @ObservedObject var viewModel: TaskListViewModel
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showPicker = false
    @State private var allLabels: [Label] = []
    @State private var savedFilters: [SavedFilter] = []
    @State private var showSavedMenu = false
    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if viewModel.activeFilterLabelIds.isEmpty {
                        Text("No label filters").style(Typography.caption).foregroundColor(Colors.onSurfaceVariant)
                    } else {
                        ForEach(Array(viewModel.activeFilterLabelIds), id: \.self) { id in
                            if let label = allLabels.first(where: { $0.id == id }) {
                                HStack(spacing: 4) {
                                    LabelChip(label: label)
                                    Button(role: .destructive) { viewModel.activeFilterLabelIds.remove(label.id); _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) } } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            Button {
                _Concurrency.Task { await loadLabels(); showPicker = true }
            } label: {
                SwiftUI.Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(SecondaryButtonStyle(size: .small))
            Menu("Saved") {
                if savedFilters.isEmpty { Text("No saved filters") }
                ForEach(savedFilters) { filter in
                    Button(filter.name) {
                        viewModel.activeFilterLabelIds = Set(filter.labelIds)
                        viewModel.matchAll = filter.matchAll
                        _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) }
                    }
                }
                Divider()
                Button("Save Current…") { saveCurrent() }
            }
            .menuStyle(.borderlessButton)
            if viewModel.activeFilterLabelIds.isEmpty == false {
                Button("Clear") { viewModel.clearFilters() }.buttonStyle(SecondaryButtonStyle(size: .small))
            }
        }
        .onAppear { _Concurrency.Task { await loadLabels(); await loadSaved() } }
        .onChange(of: viewModel.isSyncing) { _, syncing in
            if syncing == false {
                _Concurrency.Task { await loadLabels(); await loadSaved() }
            }
        }
        .sheet(isPresented: $showPicker) {
            FilterPickerSheet(
                userId: viewModel.userId,
                selected: $viewModel.activeFilterLabelIds,
                onDone: {
                    _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) }
                }
            )
        }
    }
    private func loadLabels() async {
        let deps = Dependencies.shared
        if let useCases: LabelUseCases = try? deps.resolve(type: LabelUseCases.self) {
            let uid = authService.currentUser?.id
            if let uid { allLabels = (try? await useCases.fetchLabels(for: uid)) ?? [] }
        }
    }
    private func loadSaved() async {
        let deps = Dependencies.shared
        if let repo: SavedFiltersRepository = try? deps.resolve(type: SavedFiltersRepository.self) {
            if let uid = authService.currentUser?.id { savedFilters = (try? await repo.list(for: uid)) ?? [] }
        }
    }
    private func saveCurrent() {
        let deps = Dependencies.shared
        if let repo: SavedFiltersRepository = try? deps.resolve(type: SavedFiltersRepository.self) {
            if let uid = authService.currentUser?.id {
                _Concurrency.Task {
                    let name = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
                    try? await repo.create(name: "Filter @ \(name)", labelIds: Array(viewModel.activeFilterLabelIds), matchAll: viewModel.matchAll, userId: uid)
                    await loadSaved()
                }
            }
        }
    }
}

// MARK: - New Inline Filter Section (bar + drawer)
private struct InlineFilterSection: View {
    let userId: UUID
    @ObservedObject var viewModel: TaskListViewModel
    @StateObject private var vm: LabelsFilterViewModel
    init(userId: UUID, viewModel: TaskListViewModel) {
        self.userId = userId
        self.viewModel = viewModel
        let deps = Dependencies.shared
        let useCases: LabelUseCases = try! deps.resolve(type: LabelUseCases.self)
        _vm = StateObject(wrappedValue: LabelsFilterViewModel(userId: userId, labelUseCases: useCases))
    }
    var body: some View {
        FilterBarView(
            vm: vm,
            onSelectionChanged: { ids, matchAll in
                viewModel.applyLabelFilter(selected: ids, matchAll: matchAll)
            },
            onSelectUnlabeled: {
                viewModel.applyUnlabeledFilter()
            },
            onClearAll: {
                viewModel.clearFilters()
            },
            unlabeledActive: viewModel.unlabeledOnly
        )
    }
}
private struct FilterPickerSheet: View {
    let userId: UUID
    @Binding var selected: Set<UUID>
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var labels: [Label] = []
    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { label in
                    HStack {
                        Image(systemName: selected.contains(label.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selected.contains(label.id) ? Colors.primary : Colors.onSurfaceVariant)
                        Circle().fill(label.uiColor).frame(width: 14, height: 14)
                        Text(label.name)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(label.id) }
                }
            }
            .navigationTitle("Filter by Labels")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { onDone(); dismiss() } }
            }
            .searchable(text: $search)
            .task { await load() }
        }
    }
    private func load() async {
        let deps = Dependencies.shared
        if let useCases: LabelUseCases = try? deps.resolve(type: LabelUseCases.self) {
            labels = (try? await useCases.fetchLabels(for: userId)) ?? []
        }
    }
    private var filtered: [Label] { let q = search.trimmingCharacters(in: .whitespacesAndNewlines); return q.isEmpty ? labels : labels.filter { $0.name.localizedCaseInsensitiveContains(q) } }
    private func toggle(_ id: UUID) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
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
private struct ViewModePicker: View {
    @Binding var viewMode: TaskListView.ViewMode
    var body: some View {
        Picker("View", selection: $viewMode) {
            ForEach(TaskListView.ViewMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}
#endif

private struct QuickAddComposer: View {
    @Binding var newTaskTitle: String
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            TextField("Add a task…", text: $newTaskTitle)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { onAdd() }
            Button(action: onAdd) { Text("Add") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
    }
}

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
            .padding(.horizontal)
            .onPreferenceChange(ListRowFramePreferenceKey.self) { value in
                rowFrames.merge(value) { _, new in new }
            }
        }
        .coordinateSpace(name: "listDrop")
        #if os(macOS)
        .onDrop(of: [UTType.plainText], delegate: InlineColumnDropDelegate(
            tasksWithLabels: tasksWithLabels,
            rowFramesProvider: { rowFrames },
            insertBeforeId: $insertBeforeId,
            showEndIndicator: $showEndIndicator,
            isDragActive: $isDragActive,
            onDropTask: { taskId, targetIndex in onReorder(taskId, targetIndex) }
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
    
    var body: some View {
        TaskCard(task: task, labels: labels, onToggleCompletion: { onToggle(task) }, subtaskProgress: subtaskProgress, showsRecursIcon: viewModel.tasksWithRecurrence.contains(task.id), onPauseResume: { _Concurrency.Task { await viewModel.pauseResume(taskId: task.id) } }, onSkipNext: { _Concurrency.Task { await viewModel.skipNext(taskId: task.id) } }, onGenerateNow: { _Concurrency.Task { await viewModel.generateNow(taskId: task.id) } })
            .contextMenu {
                Button("Edit") { onEdit(task) }
                Menu("Move to") {
                    ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                        Button(bucket.displayName) { onMove(task.id, bucket) }
                    }
                }
                Button(role: .destructive) { onDelete(task) } label: { Text("Delete") }
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
