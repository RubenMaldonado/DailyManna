import SwiftUI

#if os(macOS)
struct MacToolbarHost: View {
    @ObservedObject var viewModel: TaskListViewModel
    let userId: UUID
    @EnvironmentObject private var viewModeStore: ViewModeStore
    @EnvironmentObject private var workingLogVM: WorkingLogPanelViewModel

    var body: some View {
        TaskListView(viewModel: viewModel, userId: userId)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker("View", selection: $viewModeStore.mode) {
                        Image(systemName: "list.bullet").tag(TaskListView.ViewMode.list)
                        Image(systemName: "rectangle.grid.2x2").tag(TaskListView.ViewMode.board)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .accessibilityIdentifier("toolbar.viewMode")
                }
                ToolbarItem(placement: .automatic) {
                    Button { workingLogVM.toggleOpen() } label: { SwiftUI.Label("Working Log", systemImage: workingLogVM.isOpen ? "sidebar.right" : "sidebar.right") }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                        .accessibilityIdentifier("toolbar.workingLogToggle")
                }
            }
            .environmentObject(workingLogVM)
            .environmentObject(viewModeStore)
    }
}
#endif


