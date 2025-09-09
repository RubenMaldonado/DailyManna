import SwiftUI

struct TaskComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: TaskDraft
    let onSubmit: (TaskDraft) -> Void
    let onCancel: () -> Void
    @EnvironmentObject private var authService: AuthenticationService

    // Chip state
    @State private var showDatePicker = false
    @State private var showRepeat = false
    @State private var showLabels = false
    // Date/time selection state for sheet
    @State private var datePart: Date = Date()
    @State private var timePart: Date = Date()
    @State private var includeTime: Bool = false
    // Labels and recurrence state
    @State private var selectedLabelIds: Set<UUID> = []
    @State private var allLabels: [Label] = []
    @State private var recurrenceRule: RecurrenceRule? = nil

    var body: some View {
        VStack(spacing: 12) {
            // Title	
            TextField("Task name", text: $draft.title)
                .font(.title2)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            // Description (auto-growing single-line style)
            TextField("Add details…", text: Binding(get: { draft.description ?? "" }, set: { draft.description = $0 }), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
            // Chips area (wraps to next line when needed)
            ChipsFlow(spacing: 8, lineSpacing: 8) {
                chipView(icon: "tag", text: labelsChipText(), isActive: !selectedLabelIds.isEmpty, activeColor: nil, onTap: { showLabels = true }, onClear: { selectedLabelIds.removeAll() })
                #if os(macOS)
                .popover(isPresented: $showLabels) {
                    LabelMultiSelectSheet(userId: authService.currentUser?.id ?? draft.userId, selected: $selectedLabelIds)
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
                                    // default no-time to noon for internal dueAt storage when needed for notifications display text
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
            // Bucket picker bottom row
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
                Button("Add task") { submit() }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding()
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
        #endif
        #if !os(macOS)
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
            LabelMultiSelectSheet(userId: authService.currentUser?.id ?? draft.userId, selected: $selectedLabelIds)
        }
        #endif
        .onAppear { loadAllLabels() }
    }

    private func chipView(icon: String, text: String, isActive: Bool, activeColor: Color?, onTap: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
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

    private func chipLabel(icon: String, text: String) -> some View {
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

    private func submit() {
        // Post selections to ViewModel listeners similar to TaskFormView
        NotificationCenter.default.post(name: Notification.Name("dm.taskform.labels.selection"), object: nil, userInfo: [
            "taskId": draft.id,
            "labelIds": Array(selectedLabelIds)
        ])
        if let rule = recurrenceRule, let data = try? JSONEncoder().encode(rule) {
            NotificationCenter.default.post(name: Notification.Name("dm.taskform.recurrence.selection"), object: nil, userInfo: [
                "taskId": draft.id,
                "ruleJSON": data
            ])
        }
        onSubmit(draft)
        dismiss()
    }

    // MARK: - Helpers
    private func loadAllLabels() {
        let deps = Dependencies.shared
        if let useCases: LabelUseCases = try? deps.resolve(type: LabelUseCases.self) {
            let uid = authService.currentUser?.id ?? draft.userId
            _Concurrency.Task {
                allLabels = (try? await useCases.fetchLabels(for: uid)) ?? []
            }
        }
    }

    private func labelsChipText() -> String {
        guard let firstId = selectedLabelIds.first, let label = allLabels.first(where: { $0.id == firstId }) else {
            return "Labels"
        }
        let extra = selectedLabelIds.count - 1
        return extra > 0 ? "\(label.name) +\(extra)" : label.name
    }

    private func dateChipText() -> (String, Bool) {
        guard let due = draft.dueAt else { return ("Date", false) }
        let cal = Calendar.current
        let now = Date()
        // compute deadline (end of day if no time)
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

    private func recurrenceChipText() -> String {
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
}
