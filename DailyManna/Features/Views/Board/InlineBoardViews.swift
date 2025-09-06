import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
struct InlineBoardView: View {
    @ObservedObject var viewModel: TaskListViewModel
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.medium) {
                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                    InlineBucketColumn(
                        bucket: bucket,
                        tasksWithLabels: viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket },
                        subtaskProgressByParent: viewModel.subtaskProgressByParent,
                        tasksWithRecurrence: viewModel.tasksWithRecurrence,
                        onDropTask: { taskId, targetIndex in
                            _Concurrency.Task { await viewModel.reorder(taskId: taskId, to: bucket, targetIndex: targetIndex) }
                        },
                        onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task, refreshIn: nil) } },
                        onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                        onEdit: { task in viewModel.presentEditForm(task: task) },
                        onDelete: { task in viewModel.confirmDelete(task) },
                        onPauseResume: { id in _Concurrency.Task { await viewModel.pauseResume(taskId: id) } },
                        onSkipNext: { id in _Concurrency.Task { await viewModel.skipNext(taskId: id) } },
                        onGenerateNow: { id in _Concurrency.Task { await viewModel.generateNow(taskId: id) } }
                    )
                }
            }
            .padding()
            .transaction { txn in txn.disablesAnimations = true }
        }
    }
}

struct InlineBucketColumn: View {
    let bucket: TimeBucket
    let tasksWithLabels: [(Task, [Label])]
    let subtaskProgressByParent: [UUID: (completed: Int, total: Int)]
    let tasksWithRecurrence: Set<UUID>
    let onDropTask: (UUID, Int) -> Void
    let onToggle: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void
    let onPauseResume: (UUID) -> Void
    let onSkipNext: (UUID) -> Void
    let onGenerateNow: (UUID) -> Void
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var isDragActive: Bool = false
    @State private var insertBeforeId: UUID? = nil
    @State private var showEndIndicator: Bool = false
    @State private var dragFrames: [UUID: CGRect] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: bucket, count: tasksWithLabels.count)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(tasksWithLabels, id: \.0.id) { pair in
                        if isDragActive && insertBeforeId == pair.0.id {
                            Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2)
                        }
                        TaskCard(
                            task: pair.0,
                            labels: pair.1,
                            onToggleCompletion: { onToggle(pair.0) },
                            subtaskProgress: subtaskProgressByParent[pair.0.id],
                            showsRecursIcon: tasksWithRecurrence.contains(pair.0.id),
                            onPauseResume: { onPauseResume(pair.0.id) },
                            onSkipNext: { onSkipNext(pair.0.id) },
                            onGenerateNow: { onGenerateNow(pair.0.id) }
                        )
                        .contextMenu {
                            Menu("Move to") {
                                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { dest in
                                    Button(dest.displayName) { onMove(pair.0.id, dest) }
                                }
                            }
                            Button("Edit") { onEdit(pair.0) }
                            Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                        }
                        .onTapGesture(count: 2) { onEdit(pair.0) }
                        .draggable(DraggableTaskID(id: pair.0.id))
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: RowFramePreferenceKey.self, value: [pair.0.id: proxy.frame(in: .named("columnDrop"))])
                        })
                    }
                    if isDragActive && showEndIndicator {
                        Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, Spacing.xSmall)
                .transaction { $0.disablesAnimations = true }
                .onPreferenceChange(RowFramePreferenceKey.self) { value in
                    let merged = rowFrames.merging(value) { _, new in new }
                    if merged != rowFrames { rowFrames = merged }
                }
            }
        }
        .frame(width: 320)
        .padding(.vertical, Spacing.small)
        .surfaceStyle(.content)
        .cornerRadius(12)
        .coordinateSpace(name: "columnDrop")
        .onDrop(of: [UTType.plainText], delegate: InlineColumnDropDelegate(
            tasksWithLabels: tasksWithLabels,
            rowFramesProvider: { rowFrames },
            snapshotFramesProvider: { dragFrames.isEmpty ? rowFrames : dragFrames },
            insertBeforeId: $insertBeforeId,
            showEndIndicator: $showEndIndicator,
            isDragActive: $isDragActive,
            onDropTask: onDropTask,
            onBegin: { dragFrames = rowFrames },
            onEnd: { dragFrames = [:] }
        ))
    }
}

struct InlineColumnDropDelegate: DropDelegate {
    let tasksWithLabels: [(Task, [Label])]
    let rowFramesProvider: () -> [UUID: CGRect]
    let snapshotFramesProvider: () -> [UUID: CGRect]
    @Binding var insertBeforeId: UUID?
    @Binding var showEndIndicator: Bool
    @Binding var isDragActive: Bool
    let onDropTask: (UUID, Int) -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isDragActive = true
        onBegin()
        return info.hasItemsConforming(to: [UTType.plainText])
    }
    func dropEntered(info: DropInfo) { isDragActive = true; onBegin(); updateIndicator(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { updateIndicator(info); return DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { reset(); return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            guard let data = data, let str = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: str) else { DispatchQueue.main.async { reset() }; return }
            DispatchQueue.main.async {
                let (targetIndex, _) = computeTargetIndex(for: info.location)
                onDropTask(uuid, targetIndex)
                reset()
            }
        }
        return true
    }
    func dropExited(info: DropInfo) { reset() }
    private func reset() { insertBeforeId = nil; showEndIndicator = false; isDragActive = false; onEnd() }
    private func updateIndicator(_ info: DropInfo) {
        let (targetIndex, orderedIds) = computeTargetIndex(for: info.location)
        insertBeforeId = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
        showEndIndicator = targetIndex >= orderedIds.count
    }
    private func computeTargetIndex(for location: CGPoint) -> (Int, [UUID]) {
        let incomplete = tasksWithLabels.filter { !$0.0.isCompleted }
        let orderedIds = incomplete.map { $0.0.id }
        let live = rowFramesProvider(); let snap = snapshotFramesProvider()
        let frames = snap.isEmpty ? live : snap
        let sortedRects: [(Int, CGRect)] = orderedIds.enumerated().compactMap { idx, id in
            if let rect = frames[id] { return (idx, rect) } else { return nil }
        }.sorted { $0.1.minY < $1.1.minY }
        var targetIndex = sortedRects.endIndex
        for (idx, rect) in sortedRects { if location.y < rect.midY { targetIndex = idx; break } }
        return (targetIndex, orderedIds)
    }
}

struct RowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
#endif


