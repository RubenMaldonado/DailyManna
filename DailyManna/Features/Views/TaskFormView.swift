//
//  TaskFormView.swift
//  DailyManna
//
//  Created for Epic 1.2
//

import SwiftUI

struct TaskFormView: View {
    @Environment(\.dismiss) private var dismiss
    let isEditing: Bool
    @State var draft: TaskDraft
    let onSave: (TaskDraft) -> Void
    let onCancel: () -> Void
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @EnvironmentObject private var authService: AuthenticationService
    @State private var selectedLabels: Set<UUID> = []
    @State private var isDescriptionPreview: Bool = false
    @State private var subtasks: [Task] = []
    @State private var newSubtaskTitle: String = ""
    @State private var isEditingSubtasks: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $draft.title)
                    TextEditor(text: Binding(get: { draft.description ?? "" }, set: { draft.description = $0 }))
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Colors.outline))
                }
                Section("Scheduling") {
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, Locale.current)
                    }
                    Picker("Bucket", selection: $draft.bucket) {
                        ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                            Text(bucket.displayName).tag(bucket)
                        }
                    }
                }
                // Subtasks
                if isEditing {
                    Section("Subtasks") {
                        HStack(spacing: 8) {
                            TextField("New subtask…", text: $newSubtaskTitle)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit { addSubtask() }
                            Button(action: addSubtask) { Image(systemName: "plus") }
                                .buttonStyle(PrimaryButtonStyle(size: .small))
                                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        // Simple reorderable list (EditButton toggles)
                        #if os(iOS)
                        List {
                            ForEach(subtasks, id: \.id) { sub in
                                SubtaskRow(task: sub,
                                           onToggle: { toggleSubtask(sub) },
                                           onTitleChange: { newTitle in updateSubtaskTitle(sub, newTitle: newTitle) },
                                           onDelete: { deleteSubtask(sub) })
                            }
                            .onMove(perform: reorderSubtasks)
                            .onDelete { offsets in
                                let toDelete = offsets.map { subtasks[$0] }
                                for sub in toDelete { deleteSubtask(sub) }
                            }
                        }
                        .frame(minHeight: 120)
                        #else
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(subtasks, id: \.id) { sub in
                                SubtaskRow(task: sub,
                                           onToggle: { toggleSubtask(sub) },
                                           onTitleChange: { newTitle in updateSubtaskTitle(sub, newTitle: newTitle) },
                                           onDelete: { deleteSubtask(sub) })
                            }
                        }
                        #endif
                    }
                }
                Section("Labels") {
                    InlineTaskLabelSelector(userId: authService.currentUser?.id ?? draft.userId, selected: $selectedLabels)
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.dueAt = hasDueDate ? dueDate : nil
                        // Post selected label IDs so the view model can persist them
                        NotificationCenter.default.post(name: Notification.Name("dm.taskform.labels.selection"), object: nil, userInfo: [
                            "taskId": draft.id,
                            "labelIds": Array(selectedLabels)
                        ])
                        onSave(draft)
                        dismiss()
                    }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
            }
            .onAppear {
                hasDueDate = draft.dueAt != nil
                dueDate = draft.dueAt ?? Date()
                _Concurrency.Task {
                    let deps = Dependencies.shared
                    if isEditing {
                        if let (task, labels) = try? await TaskUseCases(tasksRepository: try! deps.resolve(type: TasksRepository.self), labelsRepository: try! deps.resolve(type: LabelsRepository.self)).fetchTaskWithLabels(by: draft.id) {
                            _ = task
                            selectedLabels = Set(labels.map { $0.id })
                        }
                        await loadSubtasks()
                    }
                }
            }
        }
    }
}

// MARK: - Subtask helpers and row
private extension TaskFormView {
    func insertMarkdown(_ snippet: String) { draft.description = (draft.description ?? "") + (draft.description?.isEmpty == false ? "\n" : "") + snippet }
    func loadSubtasks() async {
        let deps = Dependencies.shared
        let useCases = TaskUseCases(tasksRepository: try! deps.resolve(type: TasksRepository.self), labelsRepository: try! deps.resolve(type: LabelsRepository.self))
        subtasks = (try? await useCases.fetchSubTasks(for: draft.id)) ?? []
    }
    func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let deps = Dependencies.shared
        let useCases = TaskUseCases(tasksRepository: try! deps.resolve(type: TasksRepository.self), labelsRepository: try! deps.resolve(type: LabelsRepository.self))
        _Concurrency.Task {
            if let uid = authService.currentUser?.id ?? Optional(draft.userId) {
                _ = try? await useCases.createSubtask(parentId: draft.id, userId: uid, title: title)
                newSubtaskTitle = ""
                await loadSubtasks()
            }
        }
    }
    func toggleSubtask(_ sub: Task) {
        let deps = Dependencies.shared
        let useCases = TaskUseCases(tasksRepository: try! deps.resolve(type: TasksRepository.self), labelsRepository: try! deps.resolve(type: LabelsRepository.self))
        _Concurrency.Task { _ = try? await useCases.toggleSubtaskCompletion(id: sub.id); await loadSubtasks() }
    }
    func updateSubtaskTitle(_ sub: Task, newTitle: String) {
        let deps = Dependencies.shared
        let useCases = TaskUseCases(tasksRepository: try! deps.resolve(type: TasksRepository.self), labelsRepository: try! deps.resolve(type: LabelsRepository.self))
        _Concurrency.Task {
            var updated = sub
            updated.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            try? await useCases.updateTask(updated)
            await loadSubtasks()
        }
    }
    func deleteSubtask(_ sub: Task) {
        let deps = Dependencies.shared
        let useCases = TaskUseCases(tasksRepository: try! deps.resolve(type: TasksRepository.self), labelsRepository: try! deps.resolve(type: LabelsRepository.self))
        _Concurrency.Task { try? await useCases.deleteTask(by: sub.id, for: sub.userId); await loadSubtasks() }
    }
    func reorderSubtasks(from offsets: IndexSet, to destination: Int) {
        var arr = subtasks
        arr.move(fromOffsets: offsets, toOffset: destination)
        subtasks = arr
        let orderedIncomplete = arr.filter { !$0.isCompleted }.map { $0.id }
        let deps = Dependencies.shared
        let useCases = TaskUseCases(tasksRepository: try! deps.resolve(type: TasksRepository.self), labelsRepository: try! deps.resolve(type: LabelsRepository.self))
        _Concurrency.Task { try? await useCases.reorderSubtasks(parentId: draft.id, orderedIds: orderedIncomplete); await loadSubtasks() }
    }
}

private struct SubtaskRow: View {
    let task: Task
    let onToggle: () -> Void
    let onTitleChange: (String) -> Void
    let onDelete: () -> Void
    @State private var title: String = ""
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) { Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle") }
                .buttonStyle(.plain)
                .foregroundColor(task.isCompleted ? Colors.primary : Colors.onSurfaceVariant)
            TextField("Subtask title", text: Binding(get: { title }, set: { title = $0 }))
                .onAppear { title = task.title }
                .onSubmit { onTitleChange(title) }
                .textFieldStyle(.roundedBorder)
            Spacer()
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(task.title))
        .accessibilityHint(Text(task.isCompleted ? "Completed subtask" : "Incomplete subtask"))
    }
}
