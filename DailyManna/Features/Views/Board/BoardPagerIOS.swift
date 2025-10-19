#if os(iOS)
import SwiftUI

struct BoardPagerIOS: View {
    @ObservedObject var viewModel: TaskListViewModel
    let userId: UUID
    @State private var selection: Int = 0

    private enum Page: Int, CaseIterable { case thisWeek = 0, weekend, nextWeek, nextMonth, routines }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with current page title
            HStack {
                Text(pageTitle(for: selection))
                    .style(Typography.title2)
                    .foregroundColor(Colors.onSurface)
                    .accessibilityLabel("Board column: \(pageTitle(for: selection))")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, Spacing.xSmall)

            TabView(selection: $selection) {
            // This Week (weekday sections)
            ThisWeekSectionsListView(
                viewModel: viewModel,
                onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                onEdit: { task in viewModel.presentEditForm(task: task) },
                onDelete: { task in viewModel.confirmDelete(task) }
            )
            .tag(Page.thisWeek.rawValue)
            .padding(.top, Spacing.xSmall)

            // Weekend (simple bucket)
            StandardBucketPage(viewModel: viewModel, bucket: .weekend)
                .tag(Page.weekend.rawValue)

            // Next Week (weekday sections)
            NextWeekSectionsListView(
                viewModel: viewModel,
                onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                onEdit: { task in viewModel.presentEditForm(task: task) },
                onDelete: { task in viewModel.confirmDelete(task) }
            )
            .tag(Page.nextWeek.rawValue)
            .padding(.top, Spacing.xSmall)

            // Next Month
            StandardBucketPage(viewModel: viewModel, bucket: .nextMonth)
                .tag(Page.nextMonth.rawValue)

            // Routines (new page)
            RoutinesPage(viewModel: viewModel, userId: userId)
                .tag(Page.routines.rawValue)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .animation(.easeInOut, value: selection)
        }
        .background(Colors.background)
    }

    private func pageTitle(for index: Int) -> String {
        switch Page(rawValue: index) ?? .thisWeek {
        case .thisWeek: return "This Week"
        case .weekend: return "Weekend"
        case .nextWeek: return "Next Week"
        case .nextMonth: return "Next Month"
        case .routines: return "Routines"
        }
    }
}

private struct StandardBucketPage: View {
    @ObservedObject var viewModel: TaskListViewModel
    let bucket: TimeBucket
    var body: some View {
        // Hide ROUTINES roots; only show generated child occurrences. Sort by due/occurrence date.
        let pairs = viewModel.tasksWithLabels
            .filter { t, _ in
                if t.bucketKey != bucket { return false }
                if t.isCompleted { return false }
                if bucket == .routines { return t.parentTaskId != nil } // hide roots
                return true
            }
            .sorted { a, b in
                let ta = a.0; let tb = b.0
                let da = ta.dueAt ?? ta.occurrenceDate ?? ta.createdAt
                let db = tb.dueAt ?? tb.occurrenceDate ?? tb.createdAt
                return da < db
            }
        ScrollViewReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
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
                        coordinateSpaceName: "page_\(bucket.rawValue)"
                    )
                    .environmentObject(viewModel)
                    .padding(.horizontal)
                }
            }
        }
        .background(Colors.background)
    }
}
#endif


