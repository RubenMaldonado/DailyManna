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
                    .onDrop(of: [UTType.plainText], delegate: NextWeekDayDropDelegate(
                        sectionId: section.id,
                        sectionDate: section.date,
                        rowFramesProvider: { rowFrames },
                        itemsProvider: { viewModel.tasksByNextWeekDayKey[section.id]?.filter { !$0.0.isCompleted } ?? [] },
                        insertBeforeIdByDay: $insertBeforeIdByDay,
                        showEndIndicatorByDay: $showEndIndicatorByDay,
                        isDragActive: $isDragActive,
                        onPerform: { taskId, beforeId in
                            Telemetry.record(.taskRescheduledDrag, metadata: ["to_day": section.title])
                            let cal = Calendar.current
                            if let current = viewModel.tasksWithLabels.first(where: { $0.0.id == taskId })?.0,
                               let due = current.dueAt,
                               cal.startOfDay(for: due) == section.date {
                                await viewModel.reorder(taskId: taskId, to: .nextWeek, insertBeforeId: beforeId)
                            } else {
                                await viewModel.schedule(taskId: taskId, to: section.date)
                                await viewModel.reorder(taskId: taskId, to: .nextWeek, insertBeforeId: beforeId)
                            }
                        }
                    ))
                }
                // Unplanned Section (Next Week)
                Section(header: unplannedHeader) {
                    // Sort unplanned by date ascending (nil last)
                    let items = unplannedItems().sorted { lhs, rhs in
                        let ld = lhs.0.dueAt
                        let rd = rhs.0.dueAt
                        switch (ld, rd) {
                        case let (l?, r?): return l < r
                        case (nil, _?): return false
                        case (_?, nil): return true
                        default: return false
                        }
                    }
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
                                .overlay(alignment: .topTrailing) {
                                    if let tag = unplannedBadge(for: livePair.0) {
                                        Text(tag)
                                            .style(Typography.caption)
                                            .foregroundColor(Colors.onSurfaceVariant)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Colors.surface)
                                            .cornerRadius(6)
                                            .padding(.top, 6)
                                            .padding(.trailing, 6)
                                    }
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
        let sections = Set(viewModel.nextWeekSections.map { $0.id })
        let cal = Calendar.current
        return viewModel.tasksWithLabels.filter { pair in
            let t = pair.0
            guard t.bucketKey == .nextWeek, t.isCompleted == false else { return false }
            guard let due = t.dueAt else { return true }
            let key = WeekPlanner.isoDayKey(for: cal.startOfDay(for: due))
            return sections.contains(key) == false
        }
    }

    private func unplannedBadge(for task: Task) -> String? {
        let cal = Calendar.current
        guard let due = task.dueAt else { return "No date" }
        // Next week window
        let nextWeekDates = WeekPlanner.datesOfNextWeek(from: Date(), calendar: cal)
        guard let first = nextWeekDates.first, let last = nextWeekDates.last else { return nil }
        let d = cal.startOfDay(for: due)
        if d < cal.startOfDay(for: first) { return "Past" }
        if d > cal.startOfDay(for: last) { return "Future" }
        return nil
    }
}

struct NextWeekRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

// MARK: - Drop delegate for intra-day reordering with live indicator
struct NextWeekDayDropDelegate: DropDelegate {
    let sectionId: String
    let sectionDate: Date
    let rowFramesProvider: () -> [UUID: CGRect]
    let itemsProvider: () -> [(Task, [Label])]
    @Binding var insertBeforeIdByDay: [String: UUID?]
    @Binding var showEndIndicatorByDay: [String: Bool]
    @Binding var isDragActive: Bool
    let onPerform: (UUID, UUID?) async -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isDragActive = true
        return info.hasItemsConforming(to: [UTType.plainText])
    }
    func dropEntered(info: DropInfo) { isDragActive = true; updateIndicator(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { updateIndicator(info); return DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { reset(); return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            guard let data = data, let str = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: str) else { DispatchQueue.main.async { reset() }; return }
            let beforeId = insertBeforeIdByDay[sectionId] ?? nil
            DispatchQueue.main.async {
                _Concurrency.Task { await onPerform(uuid, beforeId) }
                reset()
            }
        }
        return true
    }
    func dropExited(info: DropInfo) { reset() }
    private func reset() { insertBeforeIdByDay[sectionId] = nil; showEndIndicatorByDay[sectionId] = false; isDragActive = false }
    private func updateIndicator(_ info: DropInfo) {
        let items = itemsProvider().filter { !$0.0.isCompleted }
        let orderedIds = items.map { $0.0.id }
        let frames = rowFramesProvider()
        let sortedRects: [(Int, CGRect)] = orderedIds.enumerated().compactMap { idx, id in
            if let rect = frames[id] { return (idx, rect) } else { return nil }
        }.sorted { $0.1.minY < $1.1.minY }
        var targetIndex = sortedRects.endIndex
        for (idx, rect) in sortedRects { if info.location.y < rect.midY { targetIndex = idx; break } }
        insertBeforeIdByDay[sectionId] = targetIndex < orderedIds.count ? orderedIds[targetIndex] : nil
        showEndIndicatorByDay[sectionId] = targetIndex >= orderedIds.count
    }
}



