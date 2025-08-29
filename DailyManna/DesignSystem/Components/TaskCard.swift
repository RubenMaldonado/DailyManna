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
                #if os(iOS)
                Haptics.lightTap()
                #endif
                onToggleCompletion?()
            } label: {
                ZStack {
                    Circle().fill(Color.clear)
                        .frame(width: 32, height: 32)
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(task.isCompleted ? Colors.primary : Colors.onSurface.opacity(0.6))
                }
            }
            .buttonStyle(.plain) // To remove default button styling
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")
            .accessibilityHint("Toggles completion for \(task.title)")
            
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxSmall) {
                    Text(task.title)
                        .style(Typography.headline)
                        .strikethrough(task.isCompleted)
                        .foregroundColor(task.isCompleted ? Colors.onSurfaceVariant : Colors.onSurface)
                        .lineLimit(2)
                    if let dueAt = task.dueAt {
                        DueChip(date: dueAt)
                    }
                }
                
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .style(Typography.body)
                        .foregroundColor(Colors.onSurfaceVariant)
                        .lineLimit(2)
                }
                
                if !labels.isEmpty {
                    FlowingChipsView(labels: labels)
                }
            }
            Spacer()
        }
        .cardPadding()
        .surfaceStyle(.content)
        .cornerRadius(Spacing.small)
    }
}

private struct FlowingChipsView: View {
    let labels: [Label]
    @State private var availableWidth: CGFloat = 0
    private let rowHeight: CGFloat = 28
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            buildRows(in: width)
        }
        .frame(minHeight: rowHeight)
    }
    private func buildRows(in width: CGFloat) -> some View {
        var rows: [[Label]] = [[]]
        var currentRowWidth: CGFloat = 0
        for label in labels {
            let chipWidth = estimatedChipWidth(for: label)
            if currentRowWidth + chipWidth > width {
                rows.append([label])
                currentRowWidth = chipWidth
            } else {
                rows[rows.count - 1].append(label)
                currentRowWidth += chipWidth
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { idx in
                HStack(spacing: Spacing.xxSmall) {
                    ForEach(rows[idx]) { label in LabelChip(label: label) }
                }
            }
        }
    }
    private func estimatedChipWidth(for label: Label) -> CGFloat {
        // Rough estimate: character count * 7 + paddings ~ 24
        CGFloat(max(60, min(180, Double(label.name.count) * 7.0 + 24.0)))
    }
}

private struct DueChip: View {
    let date: Date
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            Text(DateFormatter.shortDate.string(from: date))
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundColor(Colors.onSurface)
        .background(Colors.surfaceVariant)
        .clipShape(Capsule())
        .accessibilityLabel("Due \(DateFormatter.shortDate.string(from: date))")
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
