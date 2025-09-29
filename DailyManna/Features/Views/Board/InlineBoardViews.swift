import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
private enum BoardMetrics {
    static func columnWidth(for containerWidth: CGFloat) -> CGFloat {
        let minW: CGFloat = 360
        let maxW: CGFloat = 560
        let targetCols: CGFloat = {
            switch containerWidth {
            case ..<1024: return 3
            case 1024..<1440: return 4
            case 1440..<1920: return 5
            default: return 6
            }
        }()
        let gutter: CGFloat = 16
        let gutters = max(0, targetCols - 1) * gutter
        let ideal = floor((containerWidth - gutters - 32) / targetCols)
        return min(maxW, max(minW, ideal))
    }
}
struct InlineBoardView: View {
    @ObservedObject var viewModel: TaskListViewModel
    private var buckets: [TimeBucket] { TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder } }
    var body: some View {
        GeometryReader { geo in
        let colWidth = BoardMetrics.columnWidth(for: geo.size.width)
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.medium) {
                ForEach(buckets, id: \.rawValue) { (bucket: TimeBucket) in
                    if bucket == .thisWeek && viewModel.featureThisWeekSectionsEnabled {
                        InlineThisWeekColumn(
                            tasksWithLabels: viewModel.tasksWithLabels.filter { $0.0.bucketKey == .thisWeek },
                            subtaskProgressByParent: viewModel.subtaskProgressByParent,
                            tasksWithRecurrence: viewModel.tasksWithRecurrence,
                            isSectionCollapsed: { key in viewModel.isSectionCollapsed(dayKey: key) },
                            toggleSectionCollapsed: { key in viewModel.toggleSectionCollapsed(for: key) },
                            schedule: { id, date in _Concurrency.Task { await viewModel.schedule(taskId: id, to: date) } },
                            unschedule: { id in _Concurrency.Task { await viewModel.unschedule(taskId: id) } },
                            onMoveBucket: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                            onEdit: { task in viewModel.presentEditForm(task: task) },
                            onDelete: { task in viewModel.confirmDelete(task) },
                            onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task, refreshIn: nil) } },
                            onPauseResume: { id in _Concurrency.Task { await viewModel.pauseResume(taskId: id) } },
                            onSkipNext: { id in _Concurrency.Task { await viewModel.skipNext(taskId: id) } },
                            onGenerateNow: { id in _Concurrency.Task { await viewModel.generateNow(taskId: id) } },
                            onCompleteForever: { task in viewModel.confirmCompleteForever(task) },
                            onAdd: {
                                viewModel.presentCreateForm(bucket: .thisWeek)
                            },
                            columnWidth: colWidth
                        )
                        .id(bucket.rawValue)
                    } else if bucket == .nextWeek && viewModel.featureNextWeekSectionsEnabled {
                        InlineNextWeekColumn(
                            tasksWithLabels: viewModel.tasksWithLabels.filter { $0.0.bucketKey == .nextWeek },
                            subtaskProgressByParent: viewModel.subtaskProgressByParent,
                            tasksWithRecurrence: viewModel.tasksWithRecurrence,
                            isSectionCollapsed: { key in viewModel.isSectionCollapsed(dayKey: key) },
                            toggleSectionCollapsed: { key in viewModel.toggleSectionCollapsed(for: key) },
                            schedule: { id, date in _Concurrency.Task { await viewModel.schedule(taskId: id, to: date) } },
                            unschedule: { id in _Concurrency.Task { await viewModel.unschedule(taskId: id) } },
                            onMoveBucket: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                            onEdit: { task in viewModel.presentEditForm(task: task) },
                            onDelete: { task in viewModel.confirmDelete(task) },
                            onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task, refreshIn: nil) } },
                            onPauseResume: { id in _Concurrency.Task { await viewModel.pauseResume(taskId: id) } },
                            onSkipNext: { id in _Concurrency.Task { await viewModel.skipNext(taskId: id) } },
                            onGenerateNow: { id in _Concurrency.Task { await viewModel.generateNow(taskId: id) } },
                            onCompleteForever: { task in viewModel.confirmCompleteForever(task) },
                            onAdd: {
                                viewModel.presentCreateForm(bucket: .nextWeek)
                            },
                            columnWidth: colWidth
                        )
                        .id(bucket.rawValue)
                    } else {
                        InlineStandardBucketColumn(
                            bucket: bucket,
                            tasksWithLabels: viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket },
                            subtaskProgressByParent: viewModel.subtaskProgressByParent,
                            tasksWithRecurrence: viewModel.tasksWithRecurrence,
                            onDropTask: { taskId, targetIndex in _Concurrency.Task { await viewModel.reorder(taskId: taskId, to: bucket, targetIndex: targetIndex) } },
                            onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task, refreshIn: nil) } },
                            onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                            onEdit: { task in viewModel.presentEditForm(task: task) },
                            onDelete: { task in viewModel.confirmDelete(task) },
                            onAdd: {
                                var draft = TaskDraft(userId: viewModel.userId, bucket: bucket)
                                let cal = Calendar.current
                                switch bucket {
                                case .thisWeek:
                                    draft.dueAt = cal.startOfDay(for: Date())
                                    draft.dueHasTime = false
                                case .nextWeek:
                                    draft.dueAt = WeekPlanner.nextMonday(after: Date())
                                    draft.dueHasTime = false
                                case .weekend:
                                    draft.dueAt = WeekPlanner.weekendAnchor(for: Date())
                                    draft.dueHasTime = false
                                case .nextMonth, .routines:
                                    draft.dueAt = nil
                                    draft.dueHasTime = false
                                }
                                // selectedBucket no longer drives fetches; keep for draft prefills only if needed
                                viewModel.selectedBucket = bucket
                                viewModel.editingTask = nil
                                viewModel.isPresentingTaskForm = true
                                NotificationCenter.default.post(name: Notification.Name("dm.prefill.draft"), object: nil, userInfo: ["draftId": draft.id])
                            },
                            onPauseResume: { id in _Concurrency.Task { await viewModel.pauseResume(taskId: id) } },
                            onSkipNext: { id in _Concurrency.Task { await viewModel.skipNext(taskId: id) } },
                            onGenerateNow: { id in _Concurrency.Task { await viewModel.generateNow(taskId: id) } },
                            onToggleLabel: { taskId, labelId in viewModel.toggleLabel(taskId: taskId, labelId: labelId) },
                            onSetLabels: { taskId, desired in _Concurrency.Task { await viewModel.setLabels(taskId: taskId, to: desired) } },
                            columnWidth: colWidth
                        )
                        .id(bucket.rawValue)
                    }
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .transaction { txn in txn.disablesAnimations = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct InlineStandardBucketColumn: View {
    let bucket: TimeBucket
    let tasksWithLabels: [(Task, [Label])]
    let subtaskProgressByParent: [UUID: (completed: Int, total: Int)]
    let tasksWithRecurrence: Set<UUID>
    let onDropTask: (UUID, Int) -> Void
    let onToggle: (Task) -> Void
    let onMove: (UUID, TimeBucket) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void
    let onAdd: () -> Void
    let onPauseResume: (UUID) -> Void
    let onSkipNext: (UUID) -> Void
    let onGenerateNow: (UUID) -> Void
    let onToggleLabel: (UUID, UUID) -> Void
    let onSetLabels: (UUID, Set<UUID>) -> Void
    let columnWidth: CGFloat
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var isDragActive: Bool = false
    @State private var insertBeforeId: UUID? = nil
    @State private var showEndIndicator: Bool = false
    @State private var dragFrames: [UUID: CGRect] = [:]
    @State private var showingLabelsSheet: Bool = false
    @State private var editingLabelsTaskId: UUID? = nil
    @State private var selectedLabelIdsForSheet: Set<UUID> = []
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: bucket, count: tasksWithLabels.count, onAdd: onAdd)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(tasksWithLabels, id: \.0.id) { pair in
                        if isDragActive && insertBeforeId == pair.0.id { Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2) }
                        TaskCard(
                            task: pair.0,
                            labels: pair.1,
                            layout: .board,
                            highlighted: (bucket == .thisWeek && pair.0.bucketKey != .thisWeek) || (bucket == .nextWeek && pair.0.bucketKey != .nextWeek),
                            onToggleCompletion: { onToggle(pair.0) },
                            onOpenEdit: { onEdit(pair.0) },
                            subtaskProgress: subtaskProgressByParent[pair.0.id],
                            showsRecursIcon: tasksWithRecurrence.contains(pair.0.id),
                            onPauseResume: { onPauseResume(pair.0.id) },
                            onSkipNext: { onSkipNext(pair.0.id) },
                            onGenerateNow: { onGenerateNow(pair.0.id) }
                        )
                        .contextMenu {
                            Menu("Labels") {
                                let top = topLabels(in: tasksWithLabels, limit: 15)
                                let currentIds = Set(pair.1.map { $0.id })
                                ForEach(top) { label in
                                    let isSelected = currentIds.contains(label.id)
                                    Button(action: { onToggleLabel(pair.0.id, label.id) }) {
                                        HStack {
                                            Circle().fill(label.uiColor).frame(width: 10, height: 10)
                                            Text(label.name)
                                            if isSelected { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                                Divider()
                                Button("Edit labels…") {
                                    editingLabelsTaskId = pair.0.id
                                    selectedLabelIdsForSheet = currentIds
                                    showingLabelsSheet = true
                                    Telemetry.record(.labelEditSheetOpened)
                                }
                            }
                            Menu("Move to") {
                                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { dest in
                                    Button(dest.displayName) { onMove(pair.0.id, dest) }
                                }
                            }
                            Button("Edit") { onEdit(pair.0) }
                            Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                        }
                        // Single-tap edit is handled inside TaskCard via onOpenEdit
                        .draggable(DraggableTaskID(id: pair.0.id))
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: BoardRowFramePreferenceKey.self, value: [pair.0.id: proxy.frame(in: .named("columnDrop"))])
                        })
                    }
                    if isDragActive && showEndIndicator {
                        Rectangle().fill(Colors.primary).frame(height: 2).padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, Spacing.xSmall)
                .transaction { $0.disablesAnimations = true }
                .onPreferenceChange(BoardRowFramePreferenceKey.self) { value in
                    let merged = rowFrames.merging(value) { _, new in new }
                    if merged != rowFrames { rowFrames = merged }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, Spacing.small)
        .surfaceStyle(.content)
        .cornerRadius(12)
        .coordinateSpace(name: "columnDrop")
        .frame(width: columnWidth)
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
        .sheet(isPresented: $showingLabelsSheet) {
            // Approximate userId from any pair if needed; callers pass set on commit
            LabelMultiSelectSheet(userId: tasksWithLabels.first?.0.userId ?? UUID(), selected: $selectedLabelIdsForSheet)
        }
        .presentationBackground(Materials.glassOverlay)
        .onChange(of: showingLabelsSheet) { _, newValue in
            if newValue == false, let tid = editingLabelsTaskId {
                onSetLabels(tid, selectedLabelIdsForSheet)
                editingLabelsTaskId = nil
            }
        }
    }

    private func topLabels(in pairs: [(Task, [Label])], limit: Int = 15) -> [Label] {
        var counts: [UUID: Int] = [:]
        var byId: [UUID: Label] = [:]
        for (_, labels) in pairs {
            for label in labels {
                counts[label.id, default: 0] += 1
                byId[label.id] = label
            }
        }
        return counts
            .sorted { (lhs, rhs) in
                if lhs.value == rhs.value { return (byId[lhs.key]?.name ?? "") < (byId[rhs.key]?.name ?? "") }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .compactMap { byId[$0.key] }
    }
}

struct InlineThisWeekColumn: View {
    let tasksWithLabels: [(Task, [Label])]
    let subtaskProgressByParent: [UUID: (completed: Int, total: Int)]
    let tasksWithRecurrence: Set<UUID>
    let isSectionCollapsed: (String) -> Bool
    let toggleSectionCollapsed: (String) -> Void
    let schedule: (UUID, Date) -> Void
    let unschedule: (UUID) -> Void
    let onMoveBucket: (UUID, TimeBucket) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void
    let onToggle: (Task) -> Void
    let onPauseResume: (UUID) -> Void
    let onSkipNext: (UUID) -> Void
    let onGenerateNow: (UUID) -> Void
    let onCompleteForever: (Task) -> Void
    let onAdd: () -> Void
    let columnWidth: CGFloat

    private var sections: [WeekdaySection] { WeekPlanner.buildSections(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: .thisWeek, count: tasksWithLabels.count, onAdd: onAdd)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(sections, id: \.id) { section in
                        sectionView(section)
                    }
                    unplannedSection
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, Spacing.small)
        .surfaceStyle(.content)
        .cornerRadius(12)
        .frame(width: columnWidth)
    }

    @ViewBuilder
    private func sectionView(_ section: WeekdaySection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack {
                Button(action: { toggleSectionCollapsed(section.id) }) {
                    Image(systemName: isSectionCollapsed(section.id) ? "chevron.right" : "chevron.down")
                }
                .buttonStyle(.plain)
                Text(section.isToday ? "Today" : section.title)
                    .style(Typography.title3)
                    .foregroundColor(section.isToday ? Colors.primary : Colors.onSurface)
                Spacer()
            }
            .padding(.horizontal, Spacing.xSmall)

            if isSectionCollapsed(section.id) == false {
                let items: [(Task, [Label])] = itemsForSection(section)
                if items.isEmpty {
                    Text("No tasks scheduled")
                        .style(Typography.body)
                        .foregroundColor(Colors.onSurfaceVariant)
                        .padding(.horizontal, Spacing.xSmall)
                        .padding(.vertical, Spacing.small)
                } else {
                    ForEach(items, id: \.0.id) { pair in
                        taskRow(pair: pair, section: section)
                    }
                }
            }
        }
        .dropDestination(for: DraggableTaskID.self) { items, _ in
            guard let item = items.first else { return false }
            Telemetry.record(.taskRescheduledDrag, metadata: ["to_day": section.title])
            schedule(item.id, section.date)
            return true
        }
    }

    private func itemsForSection(_ section: WeekdaySection) -> [(Task, [Label])] {
        let cal: Calendar = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        return tasksWithLabels.filter { pair in
            let t = pair.0
            guard t.isCompleted == false, let due = t.dueAt else { return false }
            let startDue = cal.startOfDay(for: due)
            if section.isToday { return startDue <= startToday }
            return startDue == section.date
        }
    }

    // MARK: - Unplanned section
    private var unplannedItems: [(Task, [Label])] {
        let cal = Calendar.current
        let now = Date()
        let monday = WeekPlanner.mondayOfCurrentWeek(for: now, calendar: cal)
        let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? now
        return tasksWithLabels.filter { pair in
            let t = pair.0
            guard t.bucketKey == .thisWeek, t.isCompleted == false else { return false }
            guard let due = t.dueAt else { return true }
            let d = cal.startOfDay(for: due)
            // Show any THIS_WEEK task whose date is outside Mon..Sun window
            return d < monday || d > sunday
        }
        .sorted { lhs, rhs in
            let ld = lhs.0.dueAt
            let rd = rhs.0.dueAt
            switch (ld, rd) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return false
            }
        }
    }

    @ViewBuilder
    private var unplannedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack {
                Button(action: { toggleSectionCollapsed("unplanned") }) {
                    Image(systemName: isSectionCollapsed("unplanned") ? "chevron.right" : "chevron.down")
                }
                .buttonStyle(.plain)
                Image(systemName: "tray")
                    .foregroundColor(Colors.onSurface)
                Text("Unplanned")
                    .style(Typography.title3)
                    .foregroundColor(Colors.onSurface)
                Spacer()
            }
            .padding(.horizontal, Spacing.xSmall)

            if isSectionCollapsed("unplanned") == false {
                let items = unplannedItems
                if items.isEmpty {
                    Text("No unplanned tasks")
                        .style(Typography.body)
                        .foregroundColor(Colors.onSurfaceVariant)
                        .padding(.horizontal, Spacing.xSmall)
                        .padding(.vertical, Spacing.small)
                } else {
                    ForEach(items, id: \.0.id) { pair in
                        TaskCard(
                            task: pair.0,
                            labels: pair.1,
                            layout: .board,
                            onToggleCompletion: { onToggle(pair.0) },
                            onOpenEdit: { onEdit(pair.0) },
                            subtaskProgress: subtaskProgressByParent[pair.0.id],
                            showsRecursIcon: tasksWithRecurrence.contains(pair.0.id),
                            onPauseResume: { onPauseResume(pair.0.id) },
                            onSkipNext: { onSkipNext(pair.0.id) },
                            onGenerateNow: { onGenerateNow(pair.0.id) }
                        )
                        .overlay(alignment: .topTrailing) {
                            if let tag = unplannedBadgeThisWeek(for: pair.0) {
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
                        .contextMenu {
                            Menu("Schedule") {
                                ForEach(sections, id: \.id) { sec in
                                    Button(sec.isToday ? "Today" : sec.title) { schedule(pair.0.id, sec.date) }
                                }
                            }
                            Button("Clear Due Date") { unschedule(pair.0.id) }
                            Button("Edit") { onEdit(pair.0) }
                            Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                        }
                        // Single-tap edit is handled inside TaskCard via onOpenEdit
                        .draggable(DraggableTaskID(id: pair.0.id))
                        .padding(.horizontal, Spacing.xSmall)
                    }
                }
            }
        }
        .dropDestination(for: DraggableTaskID.self) { items, _ in
            guard let item = items.first else { return false }
            unschedule(item.id)
            return true
        }
    }

    private func unplannedBadgeThisWeek(for task: Task) -> String? {
        let cal = Calendar.current
        let now = Date()
        let monday = WeekPlanner.mondayOfCurrentWeek(for: now, calendar: cal)
        let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? now
        guard let due = task.dueAt else { return "No date" }
        let d = cal.startOfDay(for: due)
        if d < monday { return "Past" }
        if d > sunday { return "Future" }
        return nil
    }

    @ViewBuilder
    private func taskRow(pair: (Task, [Label]), section: WeekdaySection) -> some View {
        TaskCard(
            task: pair.0,
            labels: pair.1,
            layout: .board,
            onToggleCompletion: { onToggle(pair.0) },
            onOpenEdit: { onEdit(pair.0) },
            subtaskProgress: subtaskProgressByParent[pair.0.id],
            showsRecursIcon: tasksWithRecurrence.contains(pair.0.id),
            onPauseResume: { onPauseResume(pair.0.id) },
            onSkipNext: { onSkipNext(pair.0.id) },
            onGenerateNow: { onGenerateNow(pair.0.id) },
            onCompleteForever: { onCompleteForever(pair.0) }
        )
        .contextMenu {
            if section.isToday == false { Button("Schedule Today") { Telemetry.record(.taskRescheduledQuickAction, metadata: ["to_day": "Today"]) ; schedule(pair.0.id, Date()) } }
            let remaining = Array(sections.dropFirst())
            ForEach(remaining, id: \.id) { sec in
                Button("Schedule \(sec.isToday ? "Today" : sec.title)") { Telemetry.record(.taskRescheduledQuickAction, metadata: ["to_day": sec.title]) ; schedule(pair.0.id, sec.date) }
            }
            Menu("Move to Bucket") {
                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { dest in
                    Button(dest.displayName) { onMoveBucket(pair.0.id, dest) }
                }
            }
            Button("Edit") { onEdit(pair.0) }
            Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
        }
        // Single-tap edit is handled inside TaskCard via onOpenEdit
        .draggable(DraggableTaskID(id: pair.0.id))
        .padding(.horizontal, Spacing.xSmall)
    }

}

struct InlineNextWeekColumn: View {
    let tasksWithLabels: [(Task, [Label])]
    let subtaskProgressByParent: [UUID: (completed: Int, total: Int)]
    let tasksWithRecurrence: Set<UUID>
    let isSectionCollapsed: (String) -> Bool
    let toggleSectionCollapsed: (String) -> Void
    let schedule: (UUID, Date) -> Void
    let unschedule: (UUID) -> Void
    let onMoveBucket: (UUID, TimeBucket) -> Void
    let onEdit: (Task) -> Void
    let onDelete: (Task) -> Void
    let onToggle: (Task) -> Void
    let onPauseResume: (UUID) -> Void
    let onSkipNext: (UUID) -> Void
    let onGenerateNow: (UUID) -> Void
    let onCompleteForever: (Task) -> Void
    let onAdd: () -> Void
    let columnWidth: CGFloat

    private var sections: [WeekdaySection] { WeekPlanner.buildNextWeekSections(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: .nextWeek, count: tasksWithLabels.count, onAdd: onAdd)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(sections, id: \.id) { section in
                        sectionView(section)
                    }
                    unplannedSection
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, Spacing.small)
        .surfaceStyle(.content)
        .cornerRadius(12)
        .frame(width: columnWidth)
    }

    @ViewBuilder
    private func sectionView(_ section: WeekdaySection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack {
                Button(action: { toggleSectionCollapsed(section.id) }) { Image(systemName: isSectionCollapsed(section.id) ? "chevron.right" : "chevron.down") }
                .buttonStyle(.plain)
                Text(section.title).style(Typography.title3).foregroundColor(Colors.onSurface)
                Spacer()
            }
            .padding(.horizontal, Spacing.xSmall)

            if isSectionCollapsed(section.id) == false {
                let items: [(Task, [Label])] = itemsForSection(section)
                if items.isEmpty {
                    Text("No tasks scheduled").style(Typography.body).foregroundColor(Colors.onSurfaceVariant).padding(.horizontal, Spacing.xSmall).padding(.vertical, Spacing.small)
                } else {
                    ForEach(items, id: \.0.id) { pair in
                        taskRow(pair: pair, section: section)
                    }
                }
            }
        }
        .dropDestination(for: DraggableTaskID.self) { items, _ in
            guard let item = items.first else { return false }
            Telemetry.record(.taskRescheduledDrag, metadata: ["to_day": section.title])
            schedule(item.id, section.date)
            return true
        }
    }

    private func itemsForSection(_ section: WeekdaySection) -> [(Task, [Label])] {
        let cal: Calendar = Calendar.current
        return tasksWithLabels.filter { pair in
            let t = pair.0
            guard t.isCompleted == false, let due = t.dueAt else { return false }
            let startDue = cal.startOfDay(for: due)
            return startDue == section.date
        }
    }

    @ViewBuilder
    private func taskRow(pair: (Task, [Label]), section: WeekdaySection) -> some View {
        TaskCard(
            task: pair.0,
            labels: pair.1,
            layout: .board,
            onToggleCompletion: { onToggle(pair.0) },
            subtaskProgress: subtaskProgressByParent[pair.0.id],
            showsRecursIcon: tasksWithRecurrence.contains(pair.0.id),
            onPauseResume: { onPauseResume(pair.0.id) },
            onSkipNext: { onSkipNext(pair.0.id) },
            onGenerateNow: { onGenerateNow(pair.0.id) },
            onCompleteForever: { onCompleteForever(pair.0) }
        )
        .contextMenu {
            Menu("Schedule") {
                ForEach(sections, id: \.id) { sec in
                    Button(sec.title) { schedule(pair.0.id, sec.date) }
                }
            }
            Menu("Move to Bucket") {
                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { dest in
                    Button(dest.displayName) { onMoveBucket(pair.0.id, dest) }
                }
            }
            Button("Edit") { onEdit(pair.0) }
            Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
        }
        .onTapGesture(count: 2) { onEdit(pair.0) }
        .draggable(DraggableTaskID(id: pair.0.id))
        .padding(.horizontal, Spacing.xSmall)
    }

    private var unplannedItems: [(Task, [Label])] {
        tasksWithLabels.filter { pair in
            let t = pair.0
            return t.bucketKey == .nextWeek && t.isCompleted == false && t.dueAt == nil
        }
    }

    @ViewBuilder
    private var unplannedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack {
                Button(action: { toggleSectionCollapsed("unplanned") }) { Image(systemName: isSectionCollapsed("unplanned") ? "chevron.right" : "chevron.down") }
                .buttonStyle(.plain)
                Image(systemName: "tray").foregroundColor(Colors.onSurface)
                Text("Unplanned").style(Typography.title3).foregroundColor(Colors.onSurface)
                Spacer()
            }
            .padding(.horizontal, Spacing.xSmall)

            if isSectionCollapsed("unplanned") == false {
                let items = unplannedItems
                if items.isEmpty {
                    Text("No unplanned tasks").style(Typography.body).foregroundColor(Colors.onSurfaceVariant).padding(.horizontal, Spacing.xSmall).padding(.vertical, Spacing.small)
                } else {
                    ForEach(items, id: \.0.id) { pair in
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
                            Menu("Schedule") {
                                ForEach(sections, id: \.id) { sec in
                                    Button(sec.title) { schedule(pair.0.id, sec.date) }
                                }
                            }
                            Button("Clear Due Date") { unschedule(pair.0.id) }
                            Button("Edit") { onEdit(pair.0) }
                            Button(role: .destructive) { onDelete(pair.0) } label: { Text("Delete") }
                        }
                        .onTapGesture(count: 2) { onEdit(pair.0) }
                        .draggable(DraggableTaskID(id: pair.0.id))
                        .padding(.horizontal, Spacing.xSmall)
                    }
                }
            }
        }
        .dropDestination(for: DraggableTaskID.self) { items, _ in
            guard let item = items.first else { return false }
            unschedule(item.id)
            return true
        }
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

struct BoardRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
#endif

#if DEBUG && os(macOS)
#Preview {
    let userId = UUID()
    let l1 = Label(userId: userId, name: "Home", color: "#FF0000")
    let l2 = Label(userId: userId, name: "Work", color: "#00FF00")
    let t1 = Task(userId: userId, bucketKey: .thisWeek, position: 0, title: "Buy milk")
    let t2 = Task(userId: userId, bucketKey: .thisWeek, position: 1, title: "Write report")
    InlineStandardBucketColumn(
        bucket: .thisWeek,
        tasksWithLabels: [(t1, [l1]), (t2, [l2])],
        subtaskProgressByParent: [:],
        tasksWithRecurrence: [],
        onDropTask: {_,_ in},
        onToggle: {_ in},
        onMove: {_,_ in},
        onEdit: {_ in},
        onDelete: {_ in},
        onAdd: {},
        onPauseResume: {_ in},
        onSkipNext: {_ in},
        onGenerateNow: {_ in},
        onToggleLabel: {_,_ in},
        onSetLabels: {_,_ in},
        columnWidth: 420
    )
    .background(Colors.background)
}
#endif



