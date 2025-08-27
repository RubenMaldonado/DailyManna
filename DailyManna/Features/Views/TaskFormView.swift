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
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $draft.title)
                    TextEditor(text: Binding(get: { draft.description ?? "" }, set: { draft.description = $0 }))
                        .frame(minHeight: 100)
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
            }
        }
    }
}


