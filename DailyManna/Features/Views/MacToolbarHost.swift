import SwiftUI

#if os(macOS)
struct MacToolbarHost: View {
    @ObservedObject var viewModel: TaskListViewModel
    let userId: UUID
    @EnvironmentObject private var viewModeStore: ViewModeStore
    @EnvironmentObject private var workingLogVM: WorkingLogPanelViewModel
    @AppStorage("feature.boardOnly") private var featureBoardOnly: Bool = false

    var body: some View {
        TaskListView(viewModel: viewModel, userId: userId)
            .toolbar {
                // View switcher removed in board-only mode
                // Leading status
                ToolbarItem(placement: .status) {
                    SyncStatusView(isSyncing: viewModel.isSyncing)
                }
                // Primary add
                ToolbarItem(placement: .primaryAction) {
                    Button { NotificationCenter.default.post(name: Notification.Name("dm.toolbar.newTask"), object: nil) } label: { SwiftUI.Label("New Task", systemImage: "plus.circle.fill") }
                        .buttonStyle(PrimaryButtonStyle(size: .small))
                        .keyboardShortcut("n", modifiers: .command)
                }
                // Filter button with count
                ToolbarItem(placement: .automatic) {
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
                // Overflow
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Sync now") { _Concurrency.Task { await viewModel.sync() } }
                        Button("Settings") { NotificationCenter.default.post(name: Notification.Name("dm.toolbar.openSettings"), object: nil) }
                        Divider()
                        Button { workingLogVM.toggleOpen() } label: { SwiftUI.Label("Working Log", systemImage: workingLogVM.isOpen ? "sidebar.right" : "sidebar.right") }
                            .accessibilityIdentifier("toolbar.workingLogToggle")
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


