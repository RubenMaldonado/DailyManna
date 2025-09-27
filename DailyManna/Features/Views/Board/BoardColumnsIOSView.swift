#if os(iOS)
import SwiftUI

struct BoardColumnsIOSView: View {
    @ObservedObject var viewModel: TaskListViewModel
    let userId: UUID
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private let columnWidth: CGFloat = 480

    var body: some View {
        if hSizeClass == .regular {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.medium) {
                    // This Week
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        BucketHeader(bucket: .thisWeek, count: count(for: .thisWeek)) { viewModel.presentCreateForm(bucket: .thisWeek) }
                        ThisWeekSectionsListView(
                            viewModel: viewModel,
                            onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                            onEdit: { task in viewModel.presentEditForm(task: task) },
                            onDelete: { task in viewModel.confirmDelete(task) }
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: columnWidth)
                    .surfaceStyle(.content)
                    .cornerRadius(12)

                    // Weekend
                    StandardBucketColumn(viewModel: viewModel, bucket: .weekend)
                        .frame(width: columnWidth)

                    // Next Week
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        BucketHeader(bucket: .nextWeek, count: count(for: .nextWeek)) { viewModel.presentCreateForm(bucket: .nextWeek) }
                        NextWeekSectionsListView(
                            viewModel: viewModel,
                            onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                            onEdit: { task in viewModel.presentEditForm(task: task) },
                            onDelete: { task in viewModel.confirmDelete(task) }
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: columnWidth)
                    .surfaceStyle(.content)
                    .cornerRadius(12)

                    // Next Month
                    StandardBucketColumn(viewModel: viewModel, bucket: .nextMonth)
                        .frame(width: columnWidth)

                    // Routines
                    StandardBucketColumn(viewModel: viewModel, bucket: .routines)
                        .frame(width: columnWidth)
                }
                .padding()
            }
            .background(Colors.background)
        } else {
            BoardPagerIOS(viewModel: viewModel, userId: userId)
        }
    }

    private func count(for bucket: TimeBucket) -> Int { viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket && $0.0.isCompleted == false }.count }
}

private struct StandardBucketColumn: View {
    @ObservedObject var viewModel: TaskListViewModel
    let bucket: TimeBucket
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: bucket, count: viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket && !$0.0.isCompleted }.count) {
                viewModel.presentCreateForm(bucket: bucket)
            }
            let pairs = viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket && $0.0.isCompleted == false }
            ScrollView {
                TasksListContent(
                    tasksWithLabels: pairs,
                    subtaskProgressByParent: viewModel.subtaskProgressByParent,
                    onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                    onEdit: { task in viewModel.presentEditForm(task: task) },
                    onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                    onReorder: { taskId, targetIndex in _Concurrency.Task { await viewModel.reorder(taskId: taskId, to: bucket, targetIndex: targetIndex) } },
                    onDelete: { task in viewModel.confirmDelete(task) },
                    coordinateSpaceName: "col_\(bucket.rawValue)"
                )
                .environmentObject(viewModel)
                .padding(.horizontal)
            }
        }
        .surfaceStyle(.content)
        .cornerRadius(12)
    }
}
#endif


