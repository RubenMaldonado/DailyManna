//
//  TaskCard.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import SwiftUI

struct TaskCard: View {
    let task: Task
    let labels: [Label]
    var onToggleCompletion: (() -> Void)?
    
    init(task: Task, labels: [Label], onToggleCompletion: (() -> Void)? = nil) {
        self.task = task
        self.labels = labels
        self.onToggleCompletion = onToggleCompletion
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            Button {
                onToggleCompletion?()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(task.isCompleted ? Colors.primary : Colors.onSurface.opacity(0.6))
            }
            .buttonStyle(.plain) // To remove default button styling
            
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(task.title)
                    .style(Typography.headline)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? Colors.onSurfaceVariant : Colors.onSurface)
                
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .style(Typography.body)
                        .foregroundColor(Colors.onSurfaceVariant)
                        .lineLimit(2)
                }
                
                if !labels.isEmpty {
                    HStack(spacing: Spacing.xxSmall) {
                        ForEach(labels) { label in
                            LabelChip(label: label)
                        }
                    }
                }
                
                if let dueAt = task.dueAt {
                    Text("Due: \(dueAt, formatter: DateFormatter.shortDate)")
                        .style(Typography.caption)
                        .foregroundColor(Colors.onSurfaceVariant)
                }
            }
            Spacer()
        }
        .cardPadding()
        .background(Colors.surface)
        .cornerRadius(Spacing.small)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    TaskCard(
        task: Task(
            userId: UUID(),
            bucketKey: .thisWeek,
            title: "Buy groceries",
            description: "Milk, eggs, bread, butter",
            dueAt: Date().addingTimeInterval(3600 * 24),
            isCompleted: false
        ),
        labels: [
            Label(userId: UUID(), name: "Personal", color: "#FF0000"),
            Label(userId: UUID(), name: "Urgent", color: "#0000FF")
        ]
    )
    .padding()
}
