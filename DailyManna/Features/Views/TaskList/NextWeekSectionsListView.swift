import SwiftUI
import UniformTypeIdentifiers

struct NextWeekSectionsListView: View {
    @ObservedObject var viewModel: TaskListViewModel
    let onToggle: (Task) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void

    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var isDragActive: Bool = false
    @State private var insertBeforeIdByDay: [String: UUID?] = [:]
    @State private var showEndIndicatorByDay: [String: Bool] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xSmall, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.nextWeekSections, id: \.id) { section in
                    Section(header: header(for: section)) {
                        let items = viewModel.tasksByNextWeekDayKey[section.id] ?? []
                        if items.isEmpty {
                            Text("No tasks scheduled")
                                .style(Typography.body)
                                .foregroundColor(Colors.onSurfaceVariant)
                                .padding(.horizontal)
                                .padding(.vertical, Spacing.small)
                        } else {
                            ForEach(items, id: \.0.id) { pair in
                                let livePair = viewModel.tasksWithLabels.first(where: { $0.0.id == pair.0.id }) ?? pair
                                if isDragActive, let insertId = insertBeforeIdByDay[section.id] ?? nil, insertId == pair.0.id { Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2) }
                                TaskCard(task: livePair.0, labels: livePair.1, highlighted: livePair.0.bucketKey != .nextWeek, onToggleCompletion: { onToggle(livePair.0) }, onOpenEdit: { onEdit(livePair.0) })
                                    .contextMenu {
                                        Menu("Schedule") {
                                            ForEach(viewModel.nextWeekSections, id: \.id) { sec in
                                                Button(sec.title) { _Concurrency.Task { await viewModel.schedule(taskId: pair.0.id, to: sec.date) } }
                                            }
                                        }
                                        Button("Clear Due Date") { _Concurrency.Task { await viewModel.unschedule(taskId: pair.0.id) } }
                                        Button("Edit") { onEdit(pair.0) }
                                        Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                                    }
                                    // Single-tap edit handled in TaskCard via onOpenEdit
                                    .draggable(DraggableTaskID(id: pair.0.id))
                                    .background(GeometryReader { proxy in
                                        Color.clear.preference(key: NextWeekRowFramePreferenceKey.self, value: [pair.0.id: proxy.frame(in: .named(section.id))])
                                    })
                            }
                            if isDragActive && (showEndIndicatorByDay[section.id] ?? false) { Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2) }
                        }
                    }
                    .coordinateSpace(name: section.id)
                    .dropDestination(for: DraggableTaskID.self) { items, location in
                        guard let item = items.first else { return false }
                        let items = viewModel.tasksByNextWeekDayKey[section.id]?.filter { !$0.0.isCompleted } ?? []
                        let orderedIds = items.map { $0.0.id }
                        let sortedRects: [(Int, CGRect)] = orderedIds.enumerated().compactMap { idx, id in
                            if let rect = rowFrames[id] { return (idx, rect) } else { return nil }
                        }.sorted { $0.1.minY < $1.1.minY }
                        var targetIndex = sortedRects.endIndex
                        for (idx, rect) in sortedRects { if location.y < rect.midY { targetIndex = idx; break } }
                        insertBeforeIdByDay[section.id] = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
                        showEndIndicatorByDay[section.id] = targetIndex >= orderedIds.count
                        Telemetry.record(.taskRescheduledDrag, metadata: ["to_day": section.title])
                        _Concurrency.Task { await viewModel.schedule(taskId: item.id, to: section.date) }
                        return true
                    } isTargeted: { inside in
                        isDragActive = inside
                        if inside == false { insertBeforeIdByDay[section.id] = nil; showEndIndicatorByDay[section.id] = false }
                    }
                }
                // Unplanned Section (Next Week)
                Section(header: unplannedHeader) {
                    let items = unplannedItems()
                    if items.isEmpty {
                        Text("No unplanned tasks")
                            .style(Typography.body)
                            .foregroundColor(Colors.onSurfaceVariant)
                            .padding(.horizontal)
                            .padding(.vertical, Spacing.small)
                    } else {
                        ForEach(items, id: \.0.id) { pair in
                            let livePair = viewModel.tasksWithLabels.first(where: { $0.0.id == pair.0.id }) ?? pair
                            TaskCard(task: livePair.0, labels: livePair.1, highlighted: livePair.0.bucketKey != .nextWeek, onToggleCompletion: { onToggle(livePair.0) }, onOpenEdit: { onEdit(livePair.0) })
                                .contextMenu {
                                    Menu("Schedule") {
                                        ForEach(viewModel.nextWeekSections, id: \.id) { sec in
                                            Button(sec.title) { _Concurrency.Task { await viewModel.schedule(taskId: pair.0.id, to: sec.date) } }
                                        }
                                    }
                                    Button("Clear Due Date") { _Concurrency.Task { await viewModel.unschedule(taskId: pair.0.id) } }
                                    Button("Edit") { onEdit(pair.0) }
                                    Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                                }
                                // Single-tap edit handled in TaskCard via onOpenEdit
                        }
                    }
                }
                .coordinateSpace(name: "unplanned_next_week")
                .dropDestination(for: DraggableTaskID.self) { items, _ in
                    guard let item = items.first else { return false }
                    _Concurrency.Task { await viewModel.unschedule(taskId: item.id) }
                    return true
                } isTargeted: { inside in
                    isDragActive = inside
                }
            }
            .onPreferenceChange(NextWeekRowFramePreferenceKey.self) { value in
                rowFrames.merge(value, uniquingKeysWith: { _, new in new })
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func header(for section: WeekdaySection) -> some View {
        HStack {
            Text(section.title).style(Typography.title3).foregroundColor(Colors.onSurface)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Colors.background)
    }

    @ViewBuilder
    private var unplannedHeader: some View {
        HStack {
            Image(systemName: "tray").foregroundColor(Colors.onSurface)
            Text("Unplanned").style(Typography.title3).foregroundColor(Colors.onSurface)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Colors.background)
    }

    private func unplannedItems() -> [(Task, [Label])] {
        viewModel.tasksWithLabels.filter { pair in
            let t = pair.0
            return t.bucketKey == .nextWeek && t.isCompleted == false && t.dueAt == nil
        }
    }
}

struct NextWeekRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}


