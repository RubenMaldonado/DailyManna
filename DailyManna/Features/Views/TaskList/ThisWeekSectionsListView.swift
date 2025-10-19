//
//  ThisWeekSectionsListView.swift
//  DailyManna
//

import SwiftUI
import UniformTypeIdentifiers

struct ThisWeekSectionsListView: View {
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
                ForEach(viewModel.thisWeekSections, id: \.id) { section in
                    Section(header: header(for: section)) {
                        if viewModel.isSectionCollapsed(dayKey: section.id) == false {
                            let items = viewModel.tasksByDayKey[section.id] ?? []
                            if items.isEmpty {
                                Text("No tasks scheduled")
                                    .style(Typography.body)
                                    .foregroundColor(Colors.onSurfaceVariant)
                                    .padding(.horizontal)
                                    .padding(.vertical, Spacing.small)
                            } else {
                                ForEach(items, id: \.0.id) { pair in
                                    let livePair = viewModel.tasksWithLabels.first(where: { $0.0.id == pair.0.id }) ?? pair
                                    if isDragActive, let insertId = insertBeforeIdByDay[section.id] ?? nil, insertId == pair.0.id {
                                        Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2)
                                    }
                                    TaskCard(task: livePair.0, labels: livePair.1, highlighted: livePair.0.bucketKey != .thisWeek, onToggleCompletion: { onToggle(livePair.0) }, onOpenEdit: { onEdit(livePair.0) })
                                        .contextMenu {
                                            if viewModel.thisWeekSections.firstIndex(where: { $0.id == section.id }) != nil {
                                                let remaining = Array(viewModel.thisWeekSections.dropFirst())
                                                if section.isToday == false {
                                                    Button("Schedule Today") {
                                                        Telemetry.record(.taskRescheduledQuickAction, metadata: ["to_day": "Today"]) ; _Concurrency.Task { await viewModel.schedule(taskId: pair.0.id, to: Date()) }
                                                    }
                                                }
                                                ForEach(remaining, id: \.id) { sec in
                                                    Button("Schedule \(sec.isToday ? "Today" : sec.title)") {
                                                        Telemetry.record(.taskRescheduledQuickAction, metadata: ["to_day": sec.title]) ; _Concurrency.Task { await viewModel.schedule(taskId: pair.0.id, to: sec.date) }
                                                    }
                                                }
                                            }
                                            Button("Edit") { onEdit(pair.0) }
                                            Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                                        }
                                        // Single-tap edit handled in TaskCard via onOpenEdit
                                        .draggable(DraggableTaskID(id: pair.0.id))
                                        .background(GeometryReader { proxy in
                                            Color.clear.preference(key: ThisWeekRowFramePreferenceKey.self, value: [pair.0.id: proxy.frame(in: .named(section.id))])
                                        })
                                }
                                if isDragActive && (showEndIndicatorByDay[section.id] ?? false) {
                                    Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: section.id)
                    .onDrop(of: [UTType.plainText], delegate: ThisWeekDayDropDelegate(
                        sectionId: section.id,
                        sectionDate: section.date,
                        rowFramesProvider: { rowFrames },
                        itemsProvider: { viewModel.tasksByDayKey[section.id]?.filter { !$0.0.isCompleted } ?? [] },
                        insertBeforeIdByDay: $insertBeforeIdByDay,
                        showEndIndicatorByDay: $showEndIndicatorByDay,
                        isDragActive: $isDragActive,
                        onPerform: { taskId, beforeId in
                            Telemetry.record(.taskRescheduledDrag, metadata: ["to_day": section.title])
                            let cal = Calendar.current
                            if let current = viewModel.tasksWithLabels.first(where: { $0.0.id == taskId })?.0,
                               let due = current.dueAt,
                               cal.startOfDay(for: due) == section.date {
                                await viewModel.reorder(taskId: taskId, to: .thisWeek, insertBeforeId: beforeId)
                            } else {
                                await viewModel.schedule(taskId: taskId, to: section.date)
                                await viewModel.reorder(taskId: taskId, to: .thisWeek, insertBeforeId: beforeId)
                            }
                        }
                    ))
                }
                // Unplanned Section
                Section(header: unplannedHeader) {
                    if viewModel.isSectionCollapsed(dayKey: "unplanned") == false {
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
                        TaskCard(task: livePair.0, labels: livePair.1, highlighted: livePair.0.bucketKey != .thisWeek, onToggleCompletion: { onToggle(livePair.0) }, onOpenEdit: { onEdit(livePair.0) })
                                    .contextMenu {
                                        Menu("Schedule") {
                                            ForEach(viewModel.thisWeekSections, id: \.id) { sec in
                                                Button(sec.isToday ? "Today" : sec.title) { _Concurrency.Task { await viewModel.schedule(taskId: pair.0.id, to: sec.date) } }
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
                }
                .coordinateSpace(name: "unplanned")
                .dropDestination(for: DraggableTaskID.self) { items, _ in
                    guard let item = items.first else { return false }
                    _Concurrency.Task { await viewModel.unschedule(taskId: item.id) }
                    return true
                } isTargeted: { inside in
                    isDragActive = inside
                }
            }
            .onPreferenceChange(ThisWeekRowFramePreferenceKey.self) { value in
                rowFrames.merge(value, uniquingKeysWith: { _, new in new })
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func header(for section: WeekdaySection) -> some View {
        HStack {
            Button(action: { viewModel.toggleSectionCollapsed(for: section.id) }) {
                Image(systemName: viewModel.isSectionCollapsed(dayKey: section.id) ? "chevron.right" : "chevron.down")
            }
            .buttonStyle(.plain)
            Text(section.isToday ? "Today" : section.title)
                .style(Typography.title3)
                .foregroundColor(section.isToday ? Colors.primary : Colors.onSurface)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Colors.background)
    }

    @ViewBuilder
    private var unplannedHeader: some View {
        HStack {
            Button(action: { viewModel.toggleSectionCollapsed(for: "unplanned") }) {
                Image(systemName: viewModel.isSectionCollapsed(dayKey: "unplanned") ? "chevron.right" : "chevron.down")
            }
            .buttonStyle(.plain)
            Image(systemName: "tray")
                .foregroundColor(Colors.onSurface)
            Text("Unplanned")
                .style(Typography.title3)
                .foregroundColor(Colors.onSurface)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Colors.background)
    }

    private func unplannedItems() -> [(Task, [Label])] {
        let cal = Calendar.current
        let now = Date()
        let monday = WeekPlanner.mondayOfCurrentWeek(for: now, calendar: cal)
        let friday = WeekPlanner.fridayOfCurrentWeek(for: now, calendar: cal)
        return viewModel.tasksWithLabels.filter { pair in
            let t = pair.0
            guard t.bucketKey == .thisWeek, t.isCompleted == false else { return false }
            guard let due = t.dueAt else { return true }
            let startDue = cal.startOfDay(for: due)
            return !(startDue >= monday && startDue <= friday)
        }
    }
}

struct ThisWeekRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

// MARK: - Drop delegate for intra-day reordering with live indicator
struct ThisWeekDayDropDelegate: DropDelegate {
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



