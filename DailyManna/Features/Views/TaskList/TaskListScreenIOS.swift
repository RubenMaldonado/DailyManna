#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct TaskListScreenIOS: View {
    @ObservedObject var viewModel: TaskListViewModel
    let userId: UUID
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var showFilterSheet: Bool = false
    @State private var showSettings: Bool = false
    @State private var allLabels: [Label] = []
    @State private var savedFilters: [SavedFilter] = []
    @State private var viewMode: TaskListView.ViewMode = .list
    @State private var lastFilterOpenAt: TimeInterval = 0
    @AppStorage("feature.boardOnly") private var featureBoardOnly: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            if let syncError = viewModel.syncErrorMessage { errorBanner(syncError) }
            if let t = viewModel.pendingDelete { pendingDeleteBanner(t) }
            // Bucket header removed in multi-bucket list mode
            if hasActiveFilters { filtersRow() }
            content()
            Spacer(minLength: 0)
        }
        .background(Colors.background)
        .navigationTitle("Daily Manna")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.prefill.draft"))) { note in
            // no-op: placeholder if later we want to set local state
        }
        .task {
            await viewModel.refreshCounts()
            viewModel.forceAllBuckets = true
            await viewModel.fetchTasks(in: nil)
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
        .onAppear { _Concurrency.Task { viewModel.forceAllBuckets = true; await viewModel.fetchTasks(in: nil) } }
        .onChange(of: viewMode) { _, newMode in
            Logger.shared.info("View mode changed -> \(newMode.rawValue)", category: .ui)
            Telemetry.record(.viewSwitch, metadata: ["mode": newMode.rawValue])
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.filter.unlabeled"))) { _ in viewModel.applyUnlabeledFilter() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.filter.available.toggle"))) { note in
            if let enabled = note.userInfo?["enabled"] as? Bool { viewModel.setAvailableFilter(enabled) }
        }
        .sheet(isPresented: $viewModel.isPresentingTaskForm) { taskFormSheet() }
        .presentationDetents([.medium])
        .sheet(isPresented: $showFilterSheet) { filterSheet() }
        .sheet(isPresented: $showSettings) { settingsSheet() }
        .toolbar { toolbarContent() }
        .toolbarBackground(Materials.glassChrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .overlay(alignment: .top) { GlassEffects.hairlineDivider() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.open.task"))) { note in
            if let id = note.userInfo?["taskId"] as? UUID {
                _Concurrency.Task {
                    await viewModel.fetchTasks(in: nil)
                    if let task = viewModel.tasksWithLabels.first(where: { $0.0.id == id })?.0 { viewModel.presentEditForm(task: task) }
                }
            }
        }
    }

    private var hasActiveFilters: Bool { viewModel.availableOnly || viewModel.unlabeledOnly || viewModel.activeFilterLabelIds.isEmpty == false }

    @ViewBuilder private func errorBanner(_ text: String) -> some View {
        Banner(kind: .error, message: text)
            .padding(.horizontal)
            .padding(.top, 8)
            .overlay(alignment: .trailing) { Button("Retry") { _Concurrency.Task { await viewModel.sync() } }.buttonStyle(SecondaryButtonStyle(size: .small)).padding(.trailing, 24) }
    }

    @ViewBuilder private func pendingDeleteBanner(_ t: Task) -> some View {
        Banner(kind: .warning, message: "\"\(t.title)\" will be moved to trash.")
            .padding(.horizontal)
            .padding(.top, 8)
            .overlay(alignment: .trailing) {
                HStack(spacing: 8) {
                    Button("Cancel") { viewModel.pendingDelete = nil }.buttonStyle(SecondaryButtonStyle(size: .small))
                    Button("Delete", role: .destructive) { _Concurrency.Task { await viewModel.performDelete() } }.buttonStyle(PrimaryButtonStyle(size: .small))
                }.padding(.trailing, 24)
            }
    }

    @ViewBuilder private func headerBar() -> some View { EmptyView() }

    @ViewBuilder private func filtersRow() -> some View {
        ActiveFiltersChipsIOS(
            labels: allLabels,
            selectedLabelIds: viewModel.activeFilterLabelIds,
            availableOnly: viewModel.availableOnly,
            unlabeledOnly: viewModel.unlabeledOnly,
            onRemoveLabel: { id in viewModel.activeFilterLabelIds.remove(id); _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) } },
            onClearAll: { viewModel.clearFilters() }
        )
        .padding(.horizontal)
    }

    @ViewBuilder private func content() -> some View {
        if viewModel.isLoading {
            VStack(spacing: 12) { SkeletonTaskCard(); SkeletonTaskCard(); SkeletonTaskCard() }
                .padding(.horizontal)
        } else if let error = viewModel.errorMessage {
            Banner(kind: .error, message: error)
                .padding(.horizontal)
        } else {
            if featureBoardOnly || viewMode == .board {
                BoardColumnsIOSView(viewModel: viewModel, userId: userId)
            } else {
                AllBucketsListView(viewModel: viewModel, userId: userId)
                    .transaction { $0.disablesAnimations = true }
            }
        }
    }

    @ToolbarContentBuilder private func toolbarContent() -> some ToolbarContent {
        // Leading: compact sync status chip
        ToolbarItem(placement: .topBarLeading) {
            SyncStatusView(isSyncing: viewModel.isSyncing)
        }
        // Trailing: responsive actions
        ToolbarItem(placement: .topBarTrailing) {
            if hSizeClass == .regular {
                HStack(spacing: 8) {
                    // View switcher (List | Board)
                    if featureBoardOnly == false {
                        HStack(spacing: 8) {
                            Button { viewMode = .list } label: { Image(systemName: "list.bullet") }
                                .buttonStyle(viewMode == .list ? AnyButtonStyle(PrimaryButtonStyle(size: .small)) : AnyButtonStyle(SecondaryButtonStyle(size: .small)))
                                .keyboardShortcut("1", modifiers: .command)
                            Button { viewMode = .board } label: { Image(systemName: "rectangle.grid.2x2") }
                                .buttonStyle(viewMode == .board ? AnyButtonStyle(PrimaryButtonStyle(size: .small)) : AnyButtonStyle(SecondaryButtonStyle(size: .small)))
                                .keyboardShortcut("2", modifiers: .command)
                        }
                    }
                    // Filter button with active count
                    Button(action: {
                        Logger.shared.info("Open filter sheet", category: .ui)
                        Telemetry.record(.filterOpen)
                        let now = Date().timeIntervalSince1970
                        if now - lastFilterOpenAt < 0.3 { return }
                        lastFilterOpenAt = now
                        if showFilterSheet == false { DispatchQueue.main.async { showFilterSheet = true } }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            let count = (viewModel.availableOnly ? 1 : 0) + (viewModel.unlabeledOnly ? 1 : 0) + viewModel.activeFilterLabelIds.count
                            if count > 0 { CountBadge(count: count) }
                        }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle(size: .small))
                    // Primary add button
                    Button(action: { viewModel.presentCreateForm() }) {
                        SwiftUI.Label("New Task", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
                    // Overflow menu
                    Menu {
                        // View submenu
                        if featureBoardOnly == false {
                            Menu("View") {
                                Button(action: { viewMode = .list }) { SwiftUI.Label("List", systemImage: "list.bullet"); if viewMode == .list { Image(systemName: "checkmark") } }
                                Button(action: { viewMode = .board }) { SwiftUI.Label("Board", systemImage: "rectangle.grid.2x2"); if viewMode == .board { Image(systemName: "checkmark") } }
                            }
                        }
                        Divider()
                        Button("Sync now") { _Concurrency.Task { await viewModel.sync() } }
                        Button("Settings") { showSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
            } else {
                HStack(spacing: 8) {
                    Button(action: { viewModel.presentCreateForm() }) { Image(systemName: "plus") }
                        .buttonStyle(PrimaryButtonStyle(size: .small))
                    Menu {
                        Button("Filter…") {
                            Logger.shared.info("Open filter sheet", category: .ui)
                            Telemetry.record(.filterOpen)
                            let now = Date().timeIntervalSince1970
                            if now - lastFilterOpenAt < 0.3 { return }
                            lastFilterOpenAt = now
                            if showFilterSheet == false { DispatchQueue.main.async { showFilterSheet = true } }
                        }
                        if featureBoardOnly == false {
                            Menu("View") {
                                Button(action: { viewMode = .list }) { SwiftUI.Label("List", systemImage: "list.bullet"); if viewMode == .list { Image(systemName: "checkmark") } }
                                Button(action: { viewMode = .board }) { SwiftUI.Label("Board", systemImage: "rectangle.grid.2x2"); if viewMode == .board { Image(systemName: "checkmark") } }
                            }
                        }
                        Button(viewModel.showCompleted ? "Hide Completed" : "Show Completed") { viewModel.showCompleted.toggle(); _Concurrency.Task { await viewModel.fetchTasks(in: nil) } }
                        Divider()
                        Button("Sync now") { _Concurrency.Task { await viewModel.sync() } }
                        Button("Settings") { showSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    @ViewBuilder private func taskFormSheet() -> some View {
        if let editing = viewModel.editingTask {
            let draft = TaskDraft(from: editing)
            TaskFormView(isEditing: true, draft: draft) { draft in _Concurrency.Task { await viewModel.save(draft: draft) } } onCancel: {}
        } else {
            let draft = viewModel.prefilledDraft ?? TaskDraft(userId: userId, bucket: viewModel.selectedBucket)
            TaskComposerView(draft: draft) { draft in _Concurrency.Task { await viewModel.save(draft: draft) } } onCancel: {}
                .environmentObject(authService)
        }
    }

    @ViewBuilder private func filterSheet() -> some View {
        FilterSheetView(
            userId: userId,
            selected: $viewModel.activeFilterLabelIds,
            availableOnly: $viewModel.availableOnly,
            unlabeledOnly: $viewModel.unlabeledOnly,
            matchAll: $viewModel.matchAll,
            savedFilters: savedFilters,
            onApply: { Telemetry.record(.filterApply); _Concurrency.Task { await viewModel.fetchTasks(in: nil) } },
            onClear: { viewModel.clearFilters(); Telemetry.record(.filterClear) }
        )
    }

    @ViewBuilder private func settingsSheet() -> some View {
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

    private func loadLabels() async {
        let deps = Dependencies.shared
        if let useCases: LabelUseCases = try? deps.resolve(type: LabelUseCases.self) {
            if let uid = authService.currentUser?.id { allLabels = (try? await useCases.fetchLabels(for: uid)) ?? [] }
        }
    }
    private func loadSaved() async {
        let deps = Dependencies.shared
        if let repo: SavedFiltersRepository = try? deps.resolve(type: SavedFiltersRepository.self) {
            if let uid = authService.currentUser?.id { savedFilters = (try? await repo.list(for: uid)) ?? [] }
        }
    }
}

// MARK: - Local helper views
private struct ActiveFiltersChipsIOS: View {
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
#endif

#if os(iOS)
private struct EmptyStateViewIOS: View {
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
#endif


