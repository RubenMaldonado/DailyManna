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
        TaskCard(task: task, labels: labels, onToggleCompletion: { onToggle(task) }, subtaskProgress: subtaskProgress)
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


