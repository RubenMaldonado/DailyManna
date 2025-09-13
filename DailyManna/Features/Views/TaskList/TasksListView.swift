import SwiftUI
import UniformTypeIdentifiers

struct TasksListView: View {
    let bucket: TimeBucket
    let tasksWithLabels: [(Task, [Label])]
    let subtaskProgressByParent: [UUID: (completed: Int, total: Int)]
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onReorder: (UUID, Int) -> Void
    let onDelete: (Task) -> Void
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var insertBeforeId: UUID? = nil
    @State private var showEndIndicator: Bool = false
    @State private var isDragActive: Bool = false
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { LazyVStack(spacing: 12) { content } }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(name: "listDrop")
            #if os(macOS)
            // macOS path uses dropDestination for simplicity to avoid cross-file delegate type dependency
            .dropDestination(for: DraggableTaskID.self) { items, location in
                guard let item = items.first else { return false }
                computeDrop(location: location, moving: item.id)
                return true
            } isTargeted: { inside in
                isDragActive = inside
                if inside == false { insertBeforeId = nil; showEndIndicator = false }
            }
            #else
            .dropDestination(for: DraggableTaskID.self) { items, location in
                guard let item = items.first else { return false }
                computeDrop(location: location, moving: item.id)
                return true
            } isTargeted: { inside in
                isDragActive = inside
                if inside == false { insertBeforeId = nil; showEndIndicator = false }
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dm.task.created"))) { note in
                if let id = note.userInfo?["taskId"] as? UUID {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }
    private func computeDrop(location: CGPoint, moving id: UUID) {
        let incomplete = tasksWithLabels.filter { !$0.0.isCompleted }
        let orderedIds = incomplete.map { $0.0.id }
        let sortedRects: [(Int, CGRect)] = orderedIds.enumerated().compactMap { idx, id in
            if let rect = rowFrames[id] { return (idx, rect) } else { return nil }
        }.sorted { $0.1.minY < $1.1.minY }
        var targetIndex = sortedRects.endIndex
        for (idx, rect) in sortedRects { if location.y < rect.midY { targetIndex = idx; break } }
        insertBeforeId = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
        showEndIndicator = targetIndex >= orderedIds.count
        onReorder(id, targetIndex)
    }
    @ViewBuilder private var content: some View {
        ForEach(tasksWithLabels, id: \.0.id) { pair in
            if isDragActive && insertBeforeId == pair.0.id { indicator }
            TasksListRowView(task: pair.0, labels: pair.1, subtaskProgress: subtaskProgressByParent[pair.0.id], onToggle: onToggle, onEdit: onEdit, onMove: onMove, onDelete: onDelete)
                .id(pair.0.id)
                .draggable(DraggableTaskID(id: pair.0.id))
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ListRowFramePreferenceKey.self, value: [pair.0.id: proxy.frame(in: .named("listDrop"))])
                })
        }
        if isDragActive && showEndIndicator { indicator }
    }
    private var indicator: some View { Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2) }
}

private struct ListRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

// MARK: - Non-scrolling content for embedding inside sections (no nested scroll views)
struct TasksListContent: View {
    let tasksWithLabels: [(Task, [Label])]
    let subtaskProgressByParent: [UUID: (completed: Int, total: Int)]
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onReorder: (UUID, Int) -> Void
    let onDelete: (Task) -> Void
    let coordinateSpaceName: String

    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var insertBeforeId: UUID? = nil
    @State private var showEndIndicator: Bool = false
    @State private var isDragActive: Bool = false

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(tasksWithLabels, id: \.0.id) { pair in
                if isDragActive && insertBeforeId == pair.0.id { Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2) }
                TasksListRowView(task: pair.0, labels: pair.1, subtaskProgress: subtaskProgressByParent[pair.0.id], onToggle: onToggle, onEdit: onEdit, onMove: onMove, onDelete: onDelete)
                    .id(pair.0.id)
                    .draggable(DraggableTaskID(id: pair.0.id))
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ListRowFramePreferenceKey.self, value: [pair.0.id: proxy.frame(in: .named(coordinateSpaceName))])
                    })
            }
            if isDragActive && showEndIndicator { Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2) }
        }
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(ListRowFramePreferenceKey.self) { value in
            rowFrames.merge(value) { _, new in new }
        }
        .dropDestination(for: DraggableTaskID.self) { items, location in
            guard let item = items.first else { return false }
            computeDrop(location: location, moving: item.id)
            return true
        } isTargeted: { inside in
            isDragActive = inside
            if inside == false { insertBeforeId = nil; showEndIndicator = false }
        }
    }

    private func computeDrop(location: CGPoint, moving id: UUID) {
        let incomplete = tasksWithLabels.filter { !$0.0.isCompleted }
        let orderedIds = incomplete.map { $0.0.id }
        let sortedRects: [(Int, CGRect)] = orderedIds.enumerated().compactMap { idx, id in
            if let rect = rowFrames[id] { return (idx, rect) } else { return nil }
        }.sorted { $0.1.minY < $1.1.minY }
        var targetIndex = sortedRects.endIndex
        for (idx, rect) in sortedRects { if location.y < rect.midY { targetIndex = idx; break } }
        insertBeforeId = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
        showEndIndicator = targetIndex >= orderedIds.count
        onReorder(id, targetIndex)
    }
}

