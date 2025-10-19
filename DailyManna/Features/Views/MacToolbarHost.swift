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
                // View switcher removed in board-only mode
                // Leading status
                ToolbarItem(placement: .status) {
                    SyncStatusView(isSyncing: viewModel.isSyncing)
                }
                // Primary action cluster (Add + Working Log + Filter) with consistent spacing
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { NotificationCenter.default.post(name: Notification.Name("dm.toolbar.newTask"), object: nil) } label: { SwiftUI.Label("New Task", systemImage: "plus.circle.fill") }
                            .buttonStyle(PrimaryButtonStyle(size: .small))
                            .keyboardShortcut("n", modifiers: .command)
                        Button { workingLogVM.toggleOpen() } label: { SwiftUI.Label("Working Log", systemImage: workingLogVM.isOpen ? "sidebar.right" : "sidebar.right") }
                            .buttonStyle(SecondaryButtonStyle(size: .small))
                            .accessibilityIdentifier("toolbar.workingLogToggle.visible")
                        Button {
                            NotificationCenter.default.post(name: Notification.Name("dm.toolbar.openFilter"), object: nil)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                let count = (viewModel.availableOnly ? 1 : 0) + (viewModel.unlabeledOnly ? 1 : 0) + viewModel.activeFilterLabelIds.count
                                if count > 0 { CountBadge(count: count) }
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                    }
                }
                // Overflow
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Sync now") { _Concurrency.Task { await viewModel.sync() } }
                        Button("Settings") { NotificationCenter.default.post(name: Notification.Name("dm.toolbar.openSettings"), object: nil) }
                        Divider()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .environmentObject(workingLogVM)
            .environmentObject(viewModeStore)
    }
}
#endif


