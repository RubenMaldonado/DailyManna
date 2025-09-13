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
    // Chip/sheet states (parity with TaskComposerView)
    @State private var showDatePicker: Bool = false
    @State private var showRepeat: Bool = false
    @State private var showLabels: Bool = false
    @State private var datePart: Date = Date()
    @State private var timePart: Date = Date()
    @State private var includeTime: Bool = false
    @EnvironmentObject private var authService: AuthenticationService
    @State private var selectedLabels: Set<UUID> = []
    @State private var allLabels: [Label] = []
    @State private var isDescriptionPreview: Bool = false
    @State private var subtasks: [Task] = []
    @State private var newSubtaskTitle: String = ""
    @State private var isEditingSubtasks: Bool = false
    @State private var recurrenceRule: RecurrenceRule? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Title
                TextField("Task name", text: $draft.title)
                    .font(.title2)
                    .textFieldStyle(.roundedBorder)
                // Description (native multi-line, 3x taller by default)
                #if os(macOS)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(get: { draft.description ?? "" }, set: { draft.description = $0 }))
                        .font(.body)
                        .frame(minHeight: 130)
                    if (draft.description ?? "").isEmpty {
                        Text("Add details…")
                            .foregroundStyle(Colors.onSurfaceVariant)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                    }
                }
                .background(Colors.surface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Colors.outline))
                #else
                TextField("Add details…", text: Binding(get: { draft.description ?? "" }, set: { draft.description = $0 }), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(5...18)
                    .frame(minHeight: 130)
                #endif
                // Chips area
                ChipsFlow(spacing: 8, lineSpacing: 8) {
                    chipView(icon: "tag", text: labelsChipText(), isActive: !selectedLabels.isEmpty, activeColor: nil, onTap: { showLabels = true }, onClear: { selectedLabels.removeAll() })
                    #if os(macOS)
                    .popover(isPresented: $showLabels) {
                        LabelMultiSelectSheet(userId: authService.currentUser?.id ?? draft.userId, selected: $selectedLabels)
                            .frame(width: 340, height: 420)
                    }
                    #endif

                    chipView(
                        icon: "calendar",
                        text: dateChipText().0,
                        isActive: draft.dueAt != nil,
                        activeColor: dateChipText().1 ? Colors.error : nil,
                        onTap: { showDatePicker = true },
                        onClear: { draft.dueAt = nil }
                    )
                    #if os(macOS)
                    .popover(isPresented: $showDatePicker) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Due Date").font(.headline)
                            DatePicker("", selection: $datePart, displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                            Toggle("Include time", isOn: $includeTime)
                            if includeTime {
                                HStack {
                                    Text("Time")
                                    DatePicker("", selection: $timePart, displayedComponents: [.hourAndMinute])
                                }
                            }
                            HStack {
                                Button("Clear") { draft.dueAt = nil; includeTime = false; showDatePicker = false }
                                    .buttonStyle(SecondaryButtonStyle(size: .small))
                                Spacer()
                                Button("Done") {
                                    let calendar = Calendar.current
                                    var components = calendar.dateComponents([.year, .month, .day], from: datePart)
                                    if includeTime {
                                        let timeComponents = calendar.dateComponents([.hour, .minute], from: timePart)
                                        components.hour = timeComponents.hour
                                        components.minute = timeComponents.minute
                                    } else {
                                        components.hour = 12
                                        components.minute = 0
                                    }
                                    if let combined = calendar.date(from: components) {
                                        draft.dueAt = combined
                                        draft.dueHasTime = includeTime
                                    }
                                    showDatePicker = false
                                }
                                .buttonStyle(PrimaryButtonStyle(size: .small))
                            }
                        }
                        .onAppear {
                            let base = draft.dueAt ?? Date()
                            datePart = base
                            timePart = Date()
                            includeTime = draft.dueHasTime
                        }
                        .padding()
                    }
                    #endif

                    chipView(icon: "repeat", text: recurrenceChipText(), isActive: recurrenceRule != nil, activeColor: nil, onTap: { showRepeat = true }, onClear: { recurrenceRule = nil })
                    #if os(macOS)
                    .popover(isPresented: $showRepeat) {
                        VStack(alignment: .leading, spacing: 12) {
                            RecurrencePicker(rule: $recurrenceRule)
                            HStack {
                                Button("Clear") { recurrenceRule = nil; showRepeat = false }
                                    .buttonStyle(SecondaryButtonStyle(size: .small))
                                Spacer()
                                Button("Done") { showRepeat = false }
                                    .buttonStyle(PrimaryButtonStyle(size: .small))
                            }
                        }
                        .padding()
                    }
                    #endif
                }

                // Subtasks (edit only)
                if isEditing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subtasks").font(.headline)
                        HStack(spacing: 8) {
                            TextField("New subtask…", text: $newSubtaskTitle)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit { addSubtask() }
                            Button(action: addSubtask) { Image(systemName: "plus") }
                                .buttonStyle(PrimaryButtonStyle(size: .small))
                                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
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
                    .padding(.top, 8)
                }

                Spacer(minLength: 0)

                // Bottom action row
                HStack {
                    Menu {
                        ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                            Button(action: { draft.bucket = bucket }) {
                                HStack {
                                    Text(bucket.displayName)
                                    if bucket == draft.bucket { Spacer(); Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        chipLabel(icon: "tray", text: draft.bucket.displayName)
                    }
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
                    Spacer()
                    Button("Cancel") { onCancel(); dismiss() }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                    Button("Save changes") { save() }
                        .buttonStyle(PrimaryButtonStyle(size: .small))
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 8)
            }
            .padding()
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            #if !os(macOS)
            .sheet(isPresented: $showDatePicker) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Due Date").font(.headline)
                    DatePicker(
                        "",
                        selection: $datePart,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    Toggle("Include time", isOn: $includeTime)
                    if includeTime {
                        HStack {
                            Text("Time")
                            DatePicker(
                                "",
                                selection: $timePart,
                                displayedComponents: [.hourAndMinute]
                            )
                            #if os(iOS)
                            .datePickerStyle(.wheel)
                            #endif
                        }
                    }
                    HStack {
                        Button("Clear") {
                            draft.dueAt = nil
                            draft.dueHasTime = true
                            includeTime = false
                            showDatePicker = false
                        }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                        Spacer()
                        Button("Done") {
                            let calendar = Calendar.current
                            var components = calendar.dateComponents([.year, .month, .day], from: datePart)
                            if includeTime {
                                let t = calendar.dateComponents([.hour, .minute], from: timePart)
                                components.hour = t.hour
                                components.minute = t.minute
                            } else {
                                components.hour = 12
                                components.minute = 0
                            }
                            if let combined = calendar.date(from: components) {
                                draft.dueAt = combined
                                draft.dueHasTime = includeTime
                            }
                            showDatePicker = false
                        }
                        .buttonStyle(PrimaryButtonStyle(size: .small))
                    }
                }
                .onAppear {
                    let base = draft.dueAt ?? Date()
                    datePart = base
                    timePart = Date()
                    includeTime = draft.dueHasTime
                    if draft.dueAt == nil { includeTime = false }
                }
                .padding()
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showRepeat) {
                VStack(alignment: .leading, spacing: 12) {
                    RecurrencePicker(rule: $recurrenceRule)
                    HStack {
                        Button("Clear") { recurrenceRule = nil; showRepeat = false }
                            .buttonStyle(SecondaryButtonStyle(size: .small))
                        Spacer()
                        Button("Done") { showRepeat = false }
                            .buttonStyle(PrimaryButtonStyle(size: .small))
                    }
                }
                .padding()
            }
            .sheet(isPresented: $showLabels) {
                LabelMultiSelectSheet(userId: authService.currentUser?.id ?? draft.userId, selected: $selectedLabels)
            }
            #endif
            .onAppear {
                loadAllLabels()
                _Concurrency.Task {
                    let deps = Dependencies.shared
                    if isEditing {
                        if let (task, labels) = try? await TaskUseCases(tasksRepository: try! deps.resolve(type: TasksRepository.self), labelsRepository: try! deps.resolve(type: LabelsRepository.self)).fetchTaskWithLabels(by: draft.id) {
                            _ = task
                            selectedLabels = Set(labels.map { $0.id })
                        }
                        if let recUC: RecurrenceUseCases = try? deps.resolve(type: RecurrenceUseCases.self) {
                            let uid = authService.currentUser?.id ?? draft.userId
                            if let rec = try? await recUC.getByTaskTemplateId(draft.id, userId: uid) {
                                await MainActor.run { self.recurrenceRule = rec.rule }
                            }
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
    func save() {
        NotificationCenter.default.post(name: Notification.Name("dm.taskform.labels.selection"), object: nil, userInfo: [
            "taskId": draft.id,
            "labelIds": Array(selectedLabels)
        ])
        if let rule = recurrenceRule, let data = try? JSONEncoder().encode(rule) {
            NotificationCenter.default.post(name: Notification.Name("dm.taskform.recurrence.selection"), object: nil, userInfo: [
                "taskId": draft.id,
                "ruleJSON": data
            ])
        }
        onSave(draft)
        dismiss()
    }
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
    // MARK: - Shared helpers (chips & labels)
    func loadAllLabels() {
        let deps = Dependencies.shared
        if let useCases: LabelUseCases = try? deps.resolve(type: LabelUseCases.self) {
            let uid = authService.currentUser?.id ?? draft.userId
            _Concurrency.Task {
                allLabels = (try? await useCases.fetchLabels(for: uid)) ?? []
            }
        }
    }
    func labelsChipText() -> String {
        guard let firstId = selectedLabels.first, let label = allLabels.first(where: { $0.id == firstId }) else {
            return "Labels"
        }
        let extra = selectedLabels.count - 1
        return extra > 0 ? "\(label.name) +\(extra)" : label.name
    }
    func dateChipText() -> (String, Bool) {
        guard let due = draft.dueAt else { return ("Date", false) }
        let cal = Calendar.current
        let now = Date()
        let deadline: Date = {
            if draft.dueHasTime { return due }
            let start = cal.startOfDay(for: due)
            return cal.date(byAdding: .day, value: 1, to: start) ?? due
        }()
        let isOverdue = now >= deadline
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        timeFormatter.locale = Locale.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE MMM d"
        if cal.isDateInToday(due) {
            return draft.dueHasTime ? ("Today \(timeFormatter.string(from: due))", isOverdue) : ("Today", isOverdue)
        }
        if cal.isDateInTomorrow(due) { return draft.dueHasTime ? ("Tomorrow \(timeFormatter.string(from: due))", false) : ("Tomorrow", false) }
        if let weekendRange = cal.nextWeekend(startingAfter: now) {
            if cal.isDate(due, inSameDayAs: weekendRange.start) || cal.isDate(due, inSameDayAs: weekendRange.end) {
                return draft.dueHasTime ? ("This weekend \(timeFormatter.string(from: due))", false) : ("This weekend", false)
            }
        }
        let day = dayFormatter.string(from: due)
        return draft.dueHasTime ? ("\(day) \(timeFormatter.string(from: due))", isOverdue) : (day, isOverdue)
    }
    func recurrenceChipText() -> String {
        guard let rule = recurrenceRule else { return "Repeat" }
        switch rule.freq {
        case .daily:
            return rule.interval == 1 ? "Daily" : "Every \(rule.interval) days"
        case .weekly:
            if let days = rule.byWeekday, Set(days) == Set(["MO","TU","WE","TH","FR"]) { return "Weekdays" }
            return rule.interval == 1 ? "Weekly" : "Every \(rule.interval) weeks"
        case .monthly:
            if let day = rule.byMonthDay?.first { return rule.interval == 1 ? "Monthly (day \(day))" : "Every \(rule.interval) months" }
            return rule.interval == 1 ? "Monthly" : "Every \(rule.interval) months"
        case .yearly:
            return "Custom"
        }
    }
    func chipView(icon: String, text: String, isActive: Bool, activeColor: Color?, onTap: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .foregroundStyle(activeColor ?? Colors.onSurface)
            if isActive {
                Button(action: { onClear() }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Colors.surface)
        .cornerRadius(8)
    }
    func chipLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .foregroundStyle(Colors.onSurface)
            Image(systemName: "chevron.down")
                .foregroundStyle(Colors.onSurface)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Colors.surface)
        .cornerRadius(8)
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
