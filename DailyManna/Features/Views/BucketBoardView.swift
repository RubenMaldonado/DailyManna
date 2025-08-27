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
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.medium) {
                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                    BucketColumn(
                        bucket: bucket,
                        tasksWithLabels: viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket },
                        onDropTask: { taskId in
                            _Concurrency.Task {
                                await viewModel.move(taskId: taskId, to: bucket)
                                await viewModel.fetchTasks(in: nil)
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
        .navigationTitle("Board")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    // Ensure list view shows the current bucket-filtered data when returning
                    _Concurrency.Task { await viewModel.fetchTasks(in: viewModel.selectedBucket) }
                    dismiss()
                }
            }
        }
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
        .alert("Delete Task?", isPresented: Binding(get: { viewModel.pendingDelete != nil }, set: { if !$0 { viewModel.pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { _Concurrency.Task { await viewModel.performDelete() } }
        } message: {
            if let t = viewModel.pendingDelete { Text("\"\(t.title)\" will be moved to trash.") }
        }
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
    let onDropTask: (UUID) -> Void
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: bucket, count: tasksWithLabels.count)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(tasksWithLabels, id: \.0.id) { pair in
                        TaskCard(task: pair.0, labels: pair.1) { onToggle(pair.0) }
                            .contextMenu {
                                Button("Edit") { onEdit(pair.0) }
                                Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                            }
                            .onTapGesture(count: 2) { onEdit(pair.0) }
                            .onDrag { NSItemProvider(object: pair.0.id.uuidString as NSString) }
                    }
                }
                .padding(.horizontal, Spacing.xSmall)
            }
        }
        .frame(width: 320)
        .padding(.vertical, Spacing.small)
        .background(Colors.surface)
        .cornerRadius(12)
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            var handled = false
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                if let str = object as? NSString, let uuid = UUID(uuidString: str as String) {
                    handled = true
                    onDropTask(uuid)
                }
            }
            return handled
        }
    }
}


