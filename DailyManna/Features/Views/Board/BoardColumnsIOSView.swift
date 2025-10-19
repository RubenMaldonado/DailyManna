#if os(iOS)
import SwiftUI

struct BoardColumnsIOSView: View {
    @ObservedObject var viewModel: TaskListViewModel
    let userId: UUID
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private func columnWidth(_ containerWidth: CGFloat) -> CGFloat {
        let minW: CGFloat = 360
        let maxW: CGFloat = 560
        let targetCols: CGFloat = {
            switch containerWidth {
            case ..<1024: return 3
            case 1024..<1440: return 4
            case 1440..<1920: return 5
            default: return 6
            }
        }()
        let gutter: CGFloat = 16
        let gutters = max(0, targetCols - 1) * gutter
        let ideal = floor((containerWidth - gutters - 32) / targetCols)
        return min(maxW, max(minW, ideal))
    }

    var body: some View {
        if hSizeClass == .regular {
            GeometryReader { geo in
            let colW = columnWidth(geo.size.width)
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
                    .frame(width: colW)
                    .surfaceStyle(.content)
                    .cornerRadius(12)

                    // Weekend
                    StandardBucketColumn(viewModel: viewModel, bucket: .weekend)
                        .frame(width: colW)

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
                    .frame(width: colW)
                    .surfaceStyle(.content)
                    .cornerRadius(12)

                    // Next Month
                    StandardBucketColumn(viewModel: viewModel, bucket: .nextMonth)
                        .frame(width: colW)

                    // Routines
                    StandardBucketColumn(viewModel: viewModel, bucket: .routines)
                        .frame(width: colW)
                }
                .padding()
            }
            .background(Colors.background)
            }
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
            // Hide ROUTINES roots; only show generated child occurrences. Sort by due/occurrence date.
            let pairs = viewModel.tasksWithLabels
                .filter { t, _ in
                    if t.bucketKey != bucket { return false }
                    if t.isCompleted { return false }
                    if bucket == .routines { return t.parentTaskId != nil }
                    return true
                }
                .sorted { a, b in
                    let ta = a.0; let tb = b.0
                    let da = ta.dueAt ?? ta.occurrenceDate ?? ta.createdAt
                    let db = tb.dueAt ?? tb.occurrenceDate ?? tb.createdAt
                    return da < db
                }
            ScrollView {
                TasksListContent(
                    tasksWithLabels: pairs,
                    subtaskProgressByParent: viewModel.subtaskProgressByParent,
                    onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                    onEdit: { task in viewModel.presentEditForm(task: task) },
                    onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                    onReorder: { taskId, beforeId in _Concurrency.Task {
                        await viewModel.reorder(taskId: taskId, to: bucket, insertBeforeId: beforeId)
                    } },
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


