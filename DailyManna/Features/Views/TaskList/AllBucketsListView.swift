import SwiftUI
import UniformTypeIdentifiers

struct AllBucketsListView: View {
    @ObservedObject var viewModel: TaskListViewModel
    let userId: UUID

    // Persist collapsed state per bucket locally (not across app sessions for now)
    @State private var collapsedBuckets: Set<TimeBucket> = []

    private var bucketOrder: [TimeBucket] {
        // Match board view ordering: use sorted by sortOrder
        TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.medium, pinnedViews: [.sectionHeaders]) {
                    ForEach(bucketOrder) { bucket in
                        Section(header: header(bucket)) {
                            if collapsedBuckets.contains(bucket) == false {
                                if bucket == .thisWeek && viewModel.featureThisWeekSectionsEnabled {
                                    ThisWeekSectionsListView(
                                        viewModel: viewModel,
                                        onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                                        onEdit: { task in viewModel.presentEditForm(task: task) },
                                        onDelete: { task in viewModel.confirmDelete(task) }
                                    )
                                    .id("section_\(bucket.rawValue)")
                                    // Visually nest tasks under the bucket header
                                    .padding(.leading, Spacing.large)
                                    .padding(.trailing, Spacing.medium)
                                    .overlay(alignment: .leading) {
                                        Rectangle()
                                            .fill(Colors.onSurfaceVariant)
                                            .opacity(0.15)
                                            .frame(width: 2)
                                            .padding(.vertical, Spacing.xSmall)
                                            .offset(x: Spacing.medium)
                                    }
                                } else {
                                    let pairs = viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket }
                                    TasksListContent(
                                        tasksWithLabels: pairs,
                                        subtaskProgressByParent: viewModel.subtaskProgressByParent,
                                        onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                                        onEdit: { task in viewModel.presentEditForm(task: task) },
                                        onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                                        onReorder: { taskId, targetIndex in _Concurrency.Task { await viewModel.reorder(taskId: taskId, to: bucket, targetIndex: targetIndex) } },
                                        onDelete: { task in viewModel.confirmDelete(task) },
                                        coordinateSpaceName: "bucket_\(bucket.rawValue)"
                                    )
                                    // Visually nest tasks under the bucket header
                                    .padding(.leading, Spacing.large)
                                    .padding(.trailing, Spacing.medium)
                                    .overlay(alignment: .leading) {
                                        Rectangle()
                                            .fill(Colors.onSurfaceVariant)
                                            .opacity(0.15)
                                            .frame(width: 2)
                                            .padding(.vertical, Spacing.xSmall)
                                            .offset(x: Spacing.medium)
                                    }
                                    .id("section_\(bucket.rawValue)")
                                    .dropDestination(for: DraggableTaskID.self) { items, _ in
                                        // Drop into empty section: append at end
                                        guard let item = items.first else { return false }
                                        _Concurrency.Task {
                                            await viewModel.reorder(taskId: item.id, to: bucket, targetIndex: Int.max)
                                        }
                                        return true
                                    }
                                }
                            } else {
                                // Collapsed but should still be a drop target for cross-bucket moves
                                Color.clear
                                    .frame(height: 1)
                                    .padding(.leading, Spacing.large)
                                    .padding(.trailing, Spacing.medium)
                                    .dropDestination(for: DraggableTaskID.self) { items, _ in
                                        guard let item = items.first else { return false }
                                        _Concurrency.Task {
                                            await viewModel.reorder(taskId: item.id, to: bucket, targetIndex: Int.max)
                                        }
                                        return true
                                    }
                            }
                        }
                        .id(bucket.rawValue)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.task.created"))) { note in
                    if let id = note.userInfo?["taskId"] as? UUID { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .onAppear { Telemetry.record(.multiBucketListShown) }
            }
        }
    }

    @ViewBuilder
    private func header(_ bucket: TimeBucket) -> some View {
        HStack(spacing: Spacing.small) {
            Button(action: { toggle(bucket) }) {
                Image(systemName: collapsedBuckets.contains(bucket) ? "chevron.right" : "chevron.down")
            }
            .buttonStyle(.plain)
            BucketHeader(bucket: bucket, count: viewModel.bucketCounts[bucket] ?? 0) {
                viewModel.presentCreateForm(bucket: bucket)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Spacing.xSmall)
        .background(Colors.background)
    }

    private func toggle(_ bucket: TimeBucket) {
        if collapsedBuckets.contains(bucket) { collapsedBuckets.remove(bucket) } else { collapsedBuckets.insert(bucket) }
        Telemetry.record(.bucketSectionToggle, metadata: ["bucket": bucket.rawValue, "collapsed": collapsedBuckets.contains(bucket) ? "true" : "false"]) 
    }
}


