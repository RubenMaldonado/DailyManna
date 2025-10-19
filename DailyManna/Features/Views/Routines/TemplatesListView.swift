import SwiftUI

struct TemplatesListView: View {
    @ObservedObject var viewModel: TemplatesListViewModel
    @EnvironmentObject private var taskListVM: TaskListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            if viewModel.templates.isEmpty {
                Text("Create your first routine template")
                    .style(Typography.body)
                    .foregroundColor(Colors.onSurfaceVariant)
            } else {
                ForEach(viewModel.templates, id: \.id) { tpl in
                    TemplateRowView(
                        name: tpl.name,
                        status: viewModel.seriesByTemplateId[tpl.id]?.status ?? tpl.status,
                        nextDate: viewModel.nextRunDate(templateId: tpl.id),
                        remaining: viewModel.remainingByTemplateId[tpl.id],
                        isActive: (viewModel.seriesByTemplateId[tpl.id]?.status ?? tpl.status) == "active",
                        onToggle: { _Concurrency.Task { await viewModel.pauseResume(templateId: tpl.id, userId: taskListVM.userId) } },
                        onSkipNext: { _Concurrency.Task { await viewModel.skipNext(templateId: tpl.id, userId: taskListVM.userId) } },
                        onEdit: { viewModel.editingTemplate = tpl; viewModel.isPresentingEditor = true }
                    )
                    Divider()
                }
            }
        }
        .padding(.top, Spacing.xSmall)
        .surfaceStyle(.content)
        .cornerRadius(12)
    }
}

private extension DateFormatter {
    static let dmShortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
}
