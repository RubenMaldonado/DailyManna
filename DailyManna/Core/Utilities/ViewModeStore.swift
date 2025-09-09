import SwiftUI

#if os(macOS)
final class ViewModeStore: ObservableObject {
    @Published var mode: TaskListView.ViewMode = .list
}
#endif


