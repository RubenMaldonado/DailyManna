import SwiftUI

struct RoutinesPage: View {
    @ObservedObject var viewModel: TaskListViewModel
    @StateObject private var templatesVM = TemplatesListViewModel()
    let userId: UUID
    @State private var templatesCollapsed: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.small) {
                // Templates Section
                VStack(alignment: .leading, spacing: Spacing.small) {
                    HStack(spacing: Spacing.small) {
                        Button(action: { templatesCollapsed.toggle() }) {
                            HStack(spacing: 8) {
                                Image(systemName: templatesCollapsed ? "chevron.right" : "chevron.down")
                                Text("Templates")
                                    .style(Typography.headline)
                                    .foregroundColor(Colors.onSurface)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        #if os(iOS)
                        Button(action: { templatesVM.presentNewTemplate() }) {
                            HStack(spacing: 6) { Image(systemName: "plus"); Text("New Template") }
                        }
                        .buttonStyle(PrimaryButtonStyle(size: .small))
                        #endif
                    }

                    if templatesCollapsed == false {
                        TemplatesListView(viewModel: templatesVM)
                    }
                }
                .padding(Spacing.small)
                .surfaceStyle(.content)
                .cornerRadius(12)

                // Upcoming Routines (existing tasks in Routines bucket)
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text("Upcoming")
                        .style(Typography.headline)
                        .foregroundColor(Colors.onSurface)
                        .padding(.horizontal)

                    // Only show generated occurrences (children); hide root template items
                    let pairs = viewModel.tasksWithLabels
                        .filter { t, _ in t.bucketKey == .routines && t.parentTaskId != nil && t.isCompleted == false }
                        .sorted { a, b in
                            let ta = a.0; let tb = b.0
                            let da = ta.dueAt ?? ta.occurrenceDate ?? ta.createdAt
                            let db = tb.dueAt ?? tb.occurrenceDate ?? tb.createdAt
                            return da < db
                        }
                    TasksListContent(
                        tasksWithLabels: pairs,
                        subtaskProgressByParent: viewModel.subtaskProgressByParent,
                        onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task) } },
                        onEdit: { task in viewModel.presentEditForm(task: task) },
                        onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                        onReorder: { taskId, beforeId in _Concurrency.Task { await viewModel.reorder(taskId: taskId, to: .routines, insertBeforeId: beforeId) } },
                        onDelete: { task in viewModel.confirmDelete(task) },
                        coordinateSpaceName: "page_ROUTINES"
                    )
                    .environmentObject(viewModel)
                    .padding(.horizontal)
                }
            }
        }
        .background(Colors.background)
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { templatesVM.presentNewTemplate() }) { Image(systemName: "plus") }
                    .help("New Template")
                    .buttonStyle(.plain)
            }
        }
        #endif
        .onAppear { _Concurrency.Task { await templatesVM.load(userId: userId) } }
        .sheet(isPresented: $templatesVM.isPresentingEditor) {
            let tpl = templatesVM.editingTemplate
            let series = tpl.flatMap { templatesVM.seriesByTemplateId[$0.id] }
            NewTemplateView(userId: userId, editing: tpl, series: series)
        }
    }
}
