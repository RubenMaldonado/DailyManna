//
//  TaskListView.swift
//  DailyManna
//
//  Epic 0.1 Infrastructure Demo View
//  Simple UI to demonstrate modular architecture works
//

import SwiftUI

/// Simple view to demonstrate Epic 0.1 architecture is working
/// This is a minimal UI focused on proving the infrastructure
struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    private let userId: UUID
    @EnvironmentObject private var authService: AuthenticationService
    @State private var newTaskTitle: String = ""
    @State private var lastSyncText: String = ""
    @Environment(\.scenePhase) private var scenePhase
    init(viewModel: TaskListViewModel, userId: UUID) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.userId = userId
    }
    
    var body: some View {
        NavigationStack {
        VStack(spacing: 16) {
            TopBarView(onNew: { viewModel.presentCreateForm() }, onSignOut: { _Concurrency.Task { try? await authService.signOut() } })
            SyncStatusRow(isSyncing: viewModel.isSyncing, onSyncNow: { _Concurrency.Task { await viewModel.sync() } })
            BucketPickerView(selected: $viewModel.selectedBucket) { bucket in
                viewModel.select(bucket: bucket)
            }
            #if os(macOS)
            BoardLinkView(viewModel: viewModel)
            #endif
            #if DEBUG
            HStack { Spacer(); DebugSettingsButton(userId: userId) }
                .padding(.horizontal)
            #endif
            BucketHeader(bucket: viewModel.selectedBucket,
                         count: viewModel.bucketCounts[viewModel.selectedBucket] ?? 0)
            .padding(.horizontal)
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
        .sheet(isPresented: $viewModel.isPresentingTaskForm) {
            let draft = viewModel.editingTask.map(TaskDraft.init(from:)) ?? TaskDraft(userId: userId, bucket: viewModel.selectedBucket)
            TaskFormView(isEditing: viewModel.editingTask != nil, draft: draft) { draft in
                _Concurrency.Task { await viewModel.save(draft: draft) }
            } onCancel: {}
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
        if viewModel.isLoading {
            ProgressView("Loading...")
                .foregroundColor(Colors.primary)
                .padding()
        } else if let errorMessage = viewModel.errorMessage {
            Text("❌ Error: \(errorMessage)")
                .foregroundColor(Colors.error)
                .multilineTextAlignment(.center)
                .padding()
        } else if viewModel.tasksWithLabels.isEmpty {
            EmptyStateView(bucketName: viewModel.selectedBucket.displayName)
                .padding(.horizontal)
        } else {
            TasksListView(
                tasksWithLabels: viewModel.tasksWithLabels,
                onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                onEdit: { task in viewModel.presentEditForm(task: task) },
                onMove: { taskId, bucket in _Concurrency.Task { await viewModel.move(taskId: taskId, to: bucket) } },
                onDelete: { task in viewModel.confirmDelete(task) }
            )
        }
    }
}

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
    let onSignOut: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Manna").style(Typography.title2).foregroundColor(Colors.onSurface)
                Text("Signed in").style(Typography.caption).foregroundColor(Colors.success)
            }
            Spacer()
            Button(action: onNew) { SwiftUI.Label("New", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
            Button("Sign out", action: onSignOut)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }
}

private struct SyncStatusRow: View {
    let isSyncing: Bool
    let onSyncNow: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            if isSyncing {
                ProgressView().scaleEffect(0.8)
                Text("Syncing…").style(Typography.caption).foregroundColor(Colors.onSurfaceVariant)
            } else {
                Text("Up to date").style(Typography.caption).foregroundColor(Colors.success)
            }
            Spacer()
            Button(action: onSyncNow) { SwiftUI.Label("Sync now", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }
}

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
private struct BoardLinkView: View {
    let viewModel: TaskListViewModel
    var body: some View {
        HStack { Spacer(); NavigationLink("Open Board View") { BucketBoardView(viewModel: viewModel) }.buttonStyle(.bordered) }
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
                .buttonStyle(.borderedProminent)
                .tint(Colors.primary)
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
        .background(Colors.surface)
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

private struct TasksListView: View {
    let tasksWithLabels: [(Task, [Label])]
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onDelete: (Task) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(tasksWithLabels, id: \.0.id) { pair in
                    TaskRowView(task: pair.0, labels: pair.1, onToggle: onToggle, onEdit: onEdit, onMove: onMove, onDelete: onDelete)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct TaskRowView: View {
    let task: Task
    let labels: [Label]
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onDelete: (Task) -> Void
    
    var body: some View {
        TaskCard(task: task, labels: labels) { onToggle(task) }
            .contextMenu {
                Button("Edit") { onEdit(task) }
                Menu("Move to") {
                    ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                        Button(bucket.displayName) { onMove(task.id, bucket) }
                    }
                }
                Button(role: .destructive) { onDelete(task) } label: { Text("Delete") }
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
