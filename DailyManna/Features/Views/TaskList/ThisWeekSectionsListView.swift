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
            LazyVStack(alignment: .leading, spacing: Spacing.small, pinnedViews: [.sectionHeaders]) {
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
                                    if isDragActive, let insertId = insertBeforeIdByDay[section.id] ?? nil, insertId == pair.0.id {
                                        Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2)
                                    }
                                    TaskCard(task: pair.0, labels: pair.1, onToggleCompletion: { onToggle(pair.0) })
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
                                        .onTapGesture(count: 2) { onEdit(pair.0) }
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
                    .dropDestination(for: DraggableTaskID.self) { items, location in
                        guard let item = items.first else { return false }
                        let items = viewModel.tasksByDayKey[section.id]?.filter { !$0.0.isCompleted } ?? []
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
}

struct ThisWeekRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}


