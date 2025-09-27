import SwiftUI

// Wrapper to ensure rows reflect optimistic updates from viewModel.tasksWithLabels
struct TasksListOptimisticRow: View {
    @ObservedObject var viewModel: TaskListViewModel
    let pair: (Task, [Label])
    let subtaskProgress: (completed: Int, total: Int)?
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onDelete: (Task) -> Void

    var body: some View {
        let livePair = viewModel.tasksWithLabels.first(where: { $0.0.id == pair.0.id }) ?? pair
        TasksListRowView(
            task: livePair.0,
            labels: livePair.1,
            subtaskProgress: subtaskProgress,
            onToggle: onToggle,
            onEdit: onEdit,
            onMove: onMove,
            onDelete: onDelete
        )
        .id(livePair.0.id)
    }
}


