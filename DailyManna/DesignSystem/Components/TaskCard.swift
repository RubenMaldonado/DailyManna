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
    enum LayoutMode { case list, board }
    var layout: LayoutMode = .list
    var onToggleCompletion: (() -> Void)?
    var onPauseResume: (() -> Void)? = nil
    var onSkipNext: (() -> Void)? = nil
    var onGenerateNow: (() -> Void)? = nil
    var showsRecursIcon: Bool = false
    var subtaskProgress: (completed: Int, total: Int)? = nil
    
    init(task: Task, labels: [Label], layout: LayoutMode = .list, onToggleCompletion: (() -> Void)? = nil, subtaskProgress: (completed: Int, total: Int)? = nil, showsRecursIcon: Bool = false, onPauseResume: (() -> Void)? = nil, onSkipNext: (() -> Void)? = nil, onGenerateNow: (() -> Void)? = nil) {
        self.task = task
        self.labels = labels
        self.layout = layout
        self.onToggleCompletion = onToggleCompletion
        self.subtaskProgress = subtaskProgress
        self.showsRecursIcon = showsRecursIcon
        self.onPauseResume = onPauseResume
        self.onSkipNext = onSkipNext
        self.onGenerateNow = onGenerateNow
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
                // Title row (wrap fully, no ellipsis)
                HStack(spacing: 6) {
                    Text(task.title)
                        .style(Typography.headline)
                        .strikethrough(task.isCompleted)
                        .foregroundColor(task.isCompleted ? Colors.onSurfaceVariant : Colors.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsRecursIcon {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundColor(Colors.onSurfaceVariant)
                            .accessibilityLabel("Repeats")
                    }
                }
                // Secondary rows depend on layout
                if layout == .board {
                    if !labels.isEmpty { FlowingChipsView(labels: labels) }
                    if let dueAt = task.dueAt {
                        let now = Date()
                        let cal = Calendar.current
                        let deadline: Date = {
                            if task.dueHasTime { return dueAt }
                            let start = cal.startOfDay(for: dueAt)
                            return cal.date(byAdding: .day, value: 1, to: start) ?? dueAt
                        }()
                        DueChip(date: dueAt, showsTime: task.dueHasTime, isOverdue: !task.isCompleted && now >= deadline)
                    }
                } else {
                    HStack(alignment: .center, spacing: Spacing.small) {
                        if !labels.isEmpty {
                            // Show the first chip and collapse the rest as "+N" to reduce clutter
                            let first = labels.first!
                            let remaining = max(0, labels.count - 1)
                            HStack(spacing: Spacing.xxSmall) {
                                LabelChip(label: first)
                                if remaining > 0 {
                                    Text("+\(remaining)")
                                        .style(Typography.caption)
                                        .padding(.horizontal, Spacing.xxSmall)
                                        .padding(.vertical, 2)
                                        .background(Colors.surfaceVariant.opacity(0.08))
                                        .cornerRadius(6)
                                        .foregroundColor(Colors.onSurfaceVariant)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        if let dueAt = task.dueAt {
                            let now = Date()
                            let cal = Calendar.current
                            let deadline: Date = {
                                if task.dueHasTime { return dueAt }
                                let start = cal.startOfDay(for: dueAt)
                                return cal.date(byAdding: .day, value: 1, to: start) ?? dueAt
                            }()
                            DueChip(date: dueAt, showsTime: task.dueHasTime, isOverdue: !task.isCompleted && now >= deadline)
                                .layoutPriority(2)
                        }
                    }
                }
                // Optional: keep subtask progress at the end
                if let progress = subtaskProgress, progress.total > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(progress.completed), total: Double(progress.total))
                            .progressViewStyle(.linear)
                            .tint(Colors.primary)
                        Text("\(progress.completed)/\(progress.total)")
                            .style(Typography.caption)
                            .foregroundColor(Colors.onSurfaceVariant)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Subtasks completed")
                    .accessibilityValue("\(progress.completed) of \(progress.total)")
                }
            }
            Spacer()
        }
        // Compact list rows should look lighter than board cards
        .padding(Spacing.cardPadding - 6)
        .background(layout == .list ? Colors.surface.opacity(0.02) : Colors.surface)
        .cornerRadius(layout == .list ? Spacing.xSmall : Spacing.small)
        .contextMenu {
            if showsRecursIcon {
                Button("Pause/Resume") { onPauseResume?() }
                Button("Skip next") { onSkipNext?() }
                Button("Generate now") { onGenerateNow?() }
            }
        }
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
    var showsTime: Bool = true
    var isOverdue: Bool = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            Text(showsTime ? DateFormatter.shortDateTime.string(from: date) : DateFormatter.shortDate.string(from: date))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundColor(isOverdue ? .white : Colors.onSurface)
        .background(isOverdue ? Color.red : Colors.surfaceVariant)
        .clipShape(Capsule())
        .accessibilityLabel(isOverdue ? "Overdue, was due \(showsTime ? DateFormatter.shortDateTime.string(from: date) : DateFormatter.shortDate.string(from: date))" : "Due \(showsTime ? DateFormatter.shortDateTime.string(from: date) : DateFormatter.shortDate.string(from: date))")
    }
}

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    static let shortDateTime: DateFormatter = {
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
