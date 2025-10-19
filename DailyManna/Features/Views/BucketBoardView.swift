//
//  BucketBoardView.swift
//  DailyManna
//
//  Optional board view with drag-and-drop across buckets (Epic 1.2)
//

import SwiftUI
import UniformTypeIdentifiers

struct BucketBoardView: View {
    @ObservedObject var viewModel: TaskListViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var workingLogVM: WorkingLogPanelViewModel

    init(viewModel: TaskListViewModel) {
        self.viewModel = viewModel
        _workingLogVM = StateObject(wrappedValue: WorkingLogPanelViewModel(userId: viewModel.userId))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.medium) {
                if let t = viewModel.pendingDelete {
                    Banner(kind: .warning, message: "\"\(t.title)\" will be moved to trash.")
                        .frame(maxWidth: .infinity)
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
                        .padding(.bottom, Spacing.small)
                }
                if let t = viewModel.pendingCompleteForever {
                    Banner(kind: .warning, message: "Complete Forever - \"\(t.title)\" will stop recurring and be marked complete. This action cannot be undone.")
                        .frame(maxWidth: .infinity)
                        .overlay(
                            HStack(spacing: 8) {
                                Spacer()
                                Button("Cancel") { viewModel.pendingCompleteForever = nil }
                                    .buttonStyle(SecondaryButtonStyle(size: .small))
                                Button("Complete Forever", role: .destructive) { _Concurrency.Task { await viewModel.performCompleteForever() } }
                                    .buttonStyle(PrimaryButtonStyle(size: .small))
                            }
                            .padding(.trailing, 24)
                        )
                        .padding(.bottom, Spacing.small)
                }
                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                    BucketColumn(
                        bucket: bucket,
                        tasksWithLabels: viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket },
                        onDropTask: { taskId, targetIndex in
                            withTransaction(Transaction(animation: .none)) {
                                // We'll call reorder to compute exact position
                            }
                            _Concurrency.Task {
                                // Compute insertBeforeId from current visible order for incomplete tasks
                                let ids = viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket && $0.0.isCompleted == false }.map { $0.0.id }
                                let beforeId: UUID? = (targetIndex < ids.count) ? ids[targetIndex] : nil
                                await viewModel.reorder(taskId: taskId, to: bucket, insertBeforeId: beforeId)
                            }
                        },
                        onToggle: { task in
                            _Concurrency.Task {
                                await viewModel.toggleTaskCompletion(task: task)
                                await viewModel.fetchTasks(in: nil)
                            }
                        },
                        onEdit: { task in viewModel.presentEditForm(task: task) },
                        onDelete: { task in viewModel.confirmDelete(task) }
                    )
                }
                }
                .padding()
            }
            if workingLogVM.isOpen {
                Divider()
                WorkingLogPanelView(viewModel: workingLogVM)
                    .frame(width: 360)
            }
        }
        .navigationTitle("Board")
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) }
                    dismiss()
                }) { SwiftUI.Label("Back", systemImage: "chevron.left") }
                .buttonStyle(SecondaryButtonStyle(size: .small))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { workingLogVM.toggleOpen() } label: { SwiftUI.Label("Working Log", systemImage: workingLogVM.isOpen ? "sidebar.right" : "sidebar.right") }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
            }
        }
        #endif
        // Board-only: no need to toggle isBoardModeActive
        .sheet(isPresented: Binding(get: { viewModel.isPresentingTaskForm }, set: { if !$0 { viewModel.isPresentingTaskForm = false } })) {
            if let editing = viewModel.editingTask {
                TaskFormView(isEditing: true, draft: TaskDraft(from: editing)) { draft in
                    _Concurrency.Task { await viewModel.save(draft: draft) }
                } onCancel: {}
            } else {
                // Safety: board view opens the form only for edit; show a lightweight fallback
                Text("No task selected").padding()
            }
        }
        .presentationBackground(Materials.glassOverlay)
        .task {
            await viewModel.refreshCounts()
            // Fetch all for the board so every column has data
            await viewModel.fetchTasks(in: nil)
        }
        .onChange(of: viewModel.isPresentingTaskForm) { _, now in
            if now == false { _Concurrency.Task { await viewModel.fetchTasks(in: nil) } }
        }
    }
}

private struct BucketColumn: View {
    let bucket: TimeBucket
    let tasksWithLabels: [(Task, [Label])]
    let onDropTask: (UUID, Int) -> Void
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var insertBeforeId: UUID? = nil
    @State private var showEndIndicator: Bool = false
    @State private var isDragActive: Bool = false
    
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
                        TaskCard(task: pair.0, labels: pair.1, layout: .board, onToggleCompletion: { onToggle(pair.0) })
                            .contextMenu {
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
        .dropDestination(for: DraggableTaskID.self) { items, location in
            guard let item = items.first else { return false }
            // Compute precise index using current frames for incomplete tasks only
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
    }
}

private struct RowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}


