import SwiftUI

#if os(macOS)
final class ViewModeStore: ObservableObject {
    // Board-only: minimal stub for compatibility; always board
    @Published var mode: TaskListView.ViewMode = .board
}
#endif


