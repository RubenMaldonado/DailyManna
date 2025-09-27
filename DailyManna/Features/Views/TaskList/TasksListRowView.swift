import SwiftUI

struct TasksListRowView: View {
    let task: Task
    let labels: [Label]
    let subtaskProgress: (completed: Int, total: Int)?
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onDelete: (Task) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.small) {
            CompletionCheck(isCompleted: task.isCompleted) {
                onToggle(task)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                    AnimatedStrikeText(text: task.title, isStruck: task.isCompleted, lineHeight: 2, lineColor: Colors.onSurfaceVariant)
                        .foregroundColor(task.isCompleted ? Colors.onSurfaceVariant : Colors.onSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let dueAt = task.dueAt {
                        let now = Date()
                        let cal = Calendar.current
                        let deadline: Date = {
                            if task.dueHasTime { return dueAt }
                            let start = cal.startOfDay(for: dueAt)
                            return cal.date(byAdding: .day, value: 1, to: start) ?? dueAt
                        }()
                        let isOverdue = !task.isCompleted && now >= deadline
                        let soonThreshold = cal.date(byAdding: .day, value: 1, to: now) ?? now
                        let isSoon = !isOverdue && (dueAt <= soonThreshold)
                        CompactDuePill(date: dueAt, showsTime: task.dueHasTime, isOverdue: isOverdue, isSoon: isSoon)
                    }
                }
                HStack(spacing: Spacing.xxSmall) {
                    if !labels.isEmpty {
                        let first = labels.first!
                        let remaining = max(0, labels.count - 1)
                        LabelChip(label: first)
                        if remaining > 0 {
                            Text("+\(remaining)")
                                .style(Typography.caption)
                                .padding(.horizontal, Spacing.xxSmall)
                                .padding(.vertical, 2)
                                .background(Colors.surface.opacity(0.06))
                                .cornerRadius(6)
                                .foregroundColor(Colors.onSurfaceVariant)
                        }
                    }
                    if let progress = subtaskProgress, progress.total > 0 {
                        Text("\(progress.completed)/\(progress.total)")
                            .style(Typography.caption)
                            .foregroundColor(Colors.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit(task) }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.xSmall)
        .background(Colors.surface.opacity(0.02))
        .overlay(Rectangle().fill(Colors.onSurfaceVariant.opacity(0.06)).frame(height: 1), alignment: .bottom)
        .contextMenu {
            Button("Edit") { onEdit(task) }
            Menu("Move to") {
                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                    Button(bucket.displayName) { onMove(task.id, bucket) }
                }
            }
            Button(role: .destructive) { onDelete(task) } label: { Text("Delete") }
        }
        .accessibilityActions {
            Button(task.isCompleted ? "Mark incomplete" : "Mark complete") { onToggle(task) }
            Button("Delete") { onDelete(task) }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete(task) } label: { SwiftUI.Label("Delete", systemImage: "trash") }
            Button { onEdit(task) } label: { SwiftUI.Label("Edit", systemImage: "pencil") }
        }
        #endif
    }
}

private struct CompactDuePill: View {
    let date: Date
    var showsTime: Bool
    var isOverdue: Bool
    var isSoon: Bool
    var body: some View {
        let bg: Color = isOverdue ? Color.red : (isSoon ? Colors.warning.opacity(0.25) : Colors.surface.opacity(0.06))
        let fg: Color = isOverdue ? .white : Colors.onSurface
        HStack(spacing: 4) {
            Image(systemName: "clock")
            Text(showsTime ? DateFormatter.shortDateTime.string(from: date) : DateFormatter.shortDate.string(from: date))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundColor(fg)
        .background(bg)
        .clipShape(Capsule())
    }
}

// Local date formatters for compact due pill
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


