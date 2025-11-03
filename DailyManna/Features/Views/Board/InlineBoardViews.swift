import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
private enum ColumnWidthMode: String, Codable { case expanded, compact, rail }
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
    static let expandedWidth: CGFloat = 360
    static let compactWidth: CGFloat = 260
    static let railWidth: CGFloat = 56
}
struct InlineBoardView: View {
    @ObservedObject var viewModel: TaskListViewModel
    @StateObject private var templatesVM = TemplatesListViewModel()
    @State private var templatesCollapsed: Bool = false
    private var buckets: [TimeBucket] { TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder } }
    @State private var preferredModeByBucket: [String: String] = [:]
    @State private var lastNonRailByBucket: [String: String] = [:]
    @State private var userWidthByBucket: [String: CGFloat] = [:]
    @State private var resizingBucketKey: String? = nil
    @State private var cachedEffectiveByBucket: [String: String] = [:]
    var body: some View {
        GeometryReader { geo in
        let colWidth = BoardMetrics.columnWidth(for: geo.size.width)
        let computed = effectiveModes(containerWidth: geo.size.width, baseColumnWidth: colWidth)
        let usingCached = (resizingBucketKey != nil && cachedEffectiveByBucket.isEmpty == false)
        let effective = usingCached ? cachedEffectiveByBucket : computed
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.medium) {
                let visibleBuckets: [TimeBucket] = buckets.filter { effective[$0.rawValue] != nil }
                ForEach(Array(visibleBuckets.enumerated()), id: \.element.rawValue) { (index, bucket) in
                    let key = bucket.rawValue
                    Group {
                        if let mode = effective[key], mode == "rail" {
                            BucketRailView(
                                bucket: bucket,
                                count: viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket }.count,
                                onExpand: { setPreferredMode(bucket, to: lastNonRail(bucket)) }
                            )
                        } else {
                    let chosenWidth: CGFloat = widthFor(bucket: bucket, effectiveMode: effective[key])
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
                            onCycleWidthMode: { cycleMode(bucket) },
                            onToggleHeader: { cycleCompactExpanded(for: bucket) },
                            onCollapseToRail: { collapseToRail(bucket) },
                            onExpandAll: { expandAllBuckets() },
                            onCollapseRight: { collapseRight(of: bucket) },
                            columnWidth: chosenWidth
                        )
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
                            onCycleWidthMode: { cycleMode(bucket) },
                            onToggleHeader: { cycleCompactExpanded(for: bucket) },
                            onCollapseToRail: { collapseToRail(bucket) },
                            onExpandAll: { expandAllBuckets() },
                            onCollapseRight: { collapseRight(of: bucket) },
                            columnWidth: chosenWidth
                        )
                            } else if bucket == .routines {
                        // Routines column with Templates section (macOS)
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            // Templates
                            VStack(alignment: .leading, spacing: Spacing.small) {
                                HStack(spacing: Spacing.small) {
                                    Button(action: { templatesCollapsed.toggle() }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: templatesCollapsed ? "chevron.right" : "chevron.down")
                                            Text("Templates")
                                                .style(Typography.headline)
                                                .foregroundColor(Colors.onSurface)
                                        }
                                    }
                                    .buttonStyle(SecondaryButtonStyle(size: .small))
                                    Spacer()
                                    Button(action: { templatesVM.presentNewTemplate() }) { HStack(spacing: 6) { Image(systemName: "plus"); Text("New Template") } }
                                        .buttonStyle(PrimaryButtonStyle(size: .small))
                                }
                                if templatesCollapsed == false {
                                    TemplatesListView(viewModel: templatesVM)
                                        .environmentObject(viewModel)
                                }
                            }
                            .padding(Spacing.small)
                            .surfaceStyle(.content)
                            .cornerRadius(12)

                            // Upcoming list for routines
                            InlineStandardBucketColumn(
                                bucket: bucket,
                                tasksWithLabels: viewModel.tasksWithLabels
                                    .filter { t, _ in t.bucketKey == bucket && t.parentTaskId != nil && t.isCompleted == false }
                                    .sorted { a, b in
                                        let ta = a.0; let tb = b.0
                                        let da = ta.dueAt ?? ta.occurrenceDate ?? ta.createdAt
                                        let db = tb.dueAt ?? tb.occurrenceDate ?? tb.createdAt
                                        return da < db
                                    },
                                subtaskProgressByParent: viewModel.subtaskProgressByParent,
                                tasksWithRecurrence: viewModel.tasksWithRecurrence,
                                onDropTask: { taskId, targetIndex in _Concurrency.Task {
                                    let ids = viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket && $0.0.isCompleted == false && $0.0.parentTaskId != nil }.map { $0.0.id }
                                    let beforeId: UUID? = (targetIndex < ids.count) ? ids[targetIndex] : nil
                                    await viewModel.reorder(taskId: taskId, to: bucket, insertBeforeId: beforeId)
                                } },
                                onToggle: { task in _Concurrency.Task { await viewModel.toggleTaskCompletion(task: task, refreshIn: nil) } },
                                onMove: { taskId, dest in _Concurrency.Task { await viewModel.move(taskId: taskId, to: dest, refreshIn: nil) } },
                                onEdit: { task in viewModel.presentEditForm(task: task) },
                                onDelete: { task in viewModel.confirmDelete(task) },
                                onAdd: {
                                    var draft = TaskDraft(userId: viewModel.userId, bucket: bucket)
                                    draft.dueAt = nil
                                    draft.dueHasTime = false
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
                                onCycleWidthMode: { cycleMode(bucket) },
                                onToggleHeader: { cycleCompactExpanded(for: bucket) },
                                onCollapseToRail: { collapseToRail(bucket) },
                                onExpandAll: { expandAllBuckets() },
                                onCollapseRight: { collapseRight(of: bucket) },
                                columnWidth: chosenWidth
                            )
                        }
                        .padding(.vertical, Spacing.small)
                        .surfaceStyle(.content)
                        .cornerRadius(12)
                        .frame(width: chosenWidth)
                        .task { await templatesVM.load(userId: viewModel.userId) }
                        .sheet(isPresented: $templatesVM.isPresentingEditor) {
                            let tpl = templatesVM.editingTemplate
                            let series = tpl.flatMap { templatesVM.seriesByTemplateId[$0.id] }
                            NewTemplateView(userId: viewModel.userId, editing: tpl, series: series)
                        }
                            } else {
                        InlineStandardBucketColumn(
                            bucket: bucket,
                            tasksWithLabels: viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket },
                            subtaskProgressByParent: viewModel.subtaskProgressByParent,
                            tasksWithRecurrence: viewModel.tasksWithRecurrence,
                            onDropTask: { taskId, targetIndex in _Concurrency.Task {
                                let ids = viewModel.tasksWithLabels.filter { $0.0.bucketKey == bucket && $0.0.isCompleted == false }.map { $0.0.id }
                                let beforeId: UUID? = (targetIndex < ids.count) ? ids[targetIndex] : nil
                                await viewModel.reorder(taskId: taskId, to: bucket, insertBeforeId: beforeId)
                            } },
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
                            onCycleWidthMode: { cycleMode(bucket) },
                            onToggleHeader: { cycleCompactExpanded(for: bucket) },
                            onCollapseToRail: { collapseToRail(bucket) },
                            onExpandAll: { expandAllBuckets() },
                            onCollapseRight: { collapseRight(of: bucket) },
                            columnWidth: chosenWidth
                        )
                        }
                        // Add resize handle after every column, including the last one,
                        // so users can resize the trailing column (e.g., Routines/Templates)
                        ColumnResizeHandle(
                            onBegin: { cachedEffectiveByBucket = computed; resizingBucketKey = bucket.rawValue },
                            onDrag: { delta in withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.88)) { adjustWidth(for: bucket, by: delta) } },
                            onEnd: { withAnimation(.easeOut(duration: 0.18)) { persistUserWidth(for: bucket); resizingBucketKey = nil; cachedEffectiveByBucket = computed } }
                        )
                        }
                    }
                    .id(key)
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
        .transaction { txn in
            // Keep list interactions snappy but allow width changes to animate smoothly
            if resizingBucketKey == nil { txn.disablesAnimations = true }
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: resizingBucketKey) { _, newValue in
            if newValue == nil { DispatchQueue.main.async { cachedEffectiveByBucket = computed } }
        }
        .onChange(of: geo.size.width) { _, _ in
            if resizingBucketKey == nil { DispatchQueue.main.async { cachedEffectiveByBucket = effectiveModes(containerWidth: geo.size.width, baseColumnWidth: colWidth) } }
        }
        }
    }
}
#if os(macOS)
// MARK: - Width mode helpers (macOS only)
extension InlineBoardView {
    private func keyFor(_ bucket: TimeBucket) -> String { "board.widthMode.\(bucket.rawValue)" }
    private func keyLastNonRail(_ bucket: TimeBucket) -> String { "board.lastNonRail.\(bucket.rawValue)" }
    private func preferredMode(_ bucket: TimeBucket) -> String {
        if let mode = preferredModeByBucket[bucket.rawValue] { return mode }
        if let raw = UserDefaults.standard.string(forKey: keyFor(bucket)) { return raw }
        return "expanded"
    }
    private func setPreferredMode(_ bucket: TimeBucket, to mode: String) {
        preferredModeByBucket[bucket.rawValue] = mode
        UserDefaults.standard.set(mode, forKey: keyFor(bucket))
        if mode != "rail" {
            lastNonRailByBucket[bucket.rawValue] = mode
            UserDefaults.standard.set(mode, forKey: keyLastNonRail(bucket))
        }
    }
    private func cycleMode(_ bucket: TimeBucket) {
        let current = preferredMode(bucket)
        let next: String = (current == "expanded") ? "compact" : (current == "compact" ? "rail" : "expanded")
        setPreferredMode(bucket, to: next)
    }
    private func cycleCompactExpanded(for bucket: TimeBucket) {
        let current = preferredMode(bucket)
        let next: String = (current == "expanded") ? "compact" : "expanded"
        setPreferredMode(bucket, to: next)
    }
    private func lastNonRail(_ bucket: TimeBucket) -> String {
        if let v = lastNonRailByBucket[bucket.rawValue] { return v }
        if let raw = UserDefaults.standard.string(forKey: keyLastNonRail(bucket)) { return raw }
        return "expanded"
    }
    private func collapseToRail(_ bucket: TimeBucket) {
        setPreferredMode(bucket, to: "rail")
    }
    private func expandAllBuckets() {
        for b in buckets { setPreferredMode(b, to: "expanded") }
    }
    private func collapseRight(of bucket: TimeBucket) {
        guard let idx = buckets.firstIndex(of: bucket) else { return }
        for i in (idx+1)..<buckets.count { setPreferredMode(buckets[i], to: "rail") }
    }
    private func effectiveModes(containerWidth: CGFloat, baseColumnWidth: CGFloat) -> [String: String] {
        let gutter: CGFloat = Spacing.medium
        var modes: [String: String] = [:]
        for b in buckets { modes[b.rawValue] = preferredMode(b) }
        func width(for mode: String) -> CGFloat {
            switch mode {
            case "expanded": return BoardMetrics.expandedWidth
            case "compact": return BoardMetrics.compactWidth
            case "rail": return BoardMetrics.railWidth
            default: return BoardMetrics.expandedWidth
            }
        }
        func totalWidth() -> CGFloat {
            let visible = buckets.compactMap { modes[$0.rawValue] }
            if visible.isEmpty { return 0 }
            let sum = visible.map { width(for: $0) }.reduce(0, +)
            let gutters = gutter * CGFloat(max(visible.count - 1, 0))
            let padding: CGFloat = 32
            return sum + gutters + padding
        }
        var idx = buckets.count - 1
        while totalWidth() > containerWidth && idx >= 0 {
            let b = buckets[idx]
            if let m = modes[b.rawValue] {
                if m == "expanded" { modes[b.rawValue] = "compact" }
                else if m == "compact" { modes[b.rawValue] = "rail" }
            }
            if idx > 0 { idx -= 1 } else { break }
        }
        idx = buckets.count - 1
        while totalWidth() > containerWidth && idx >= 1 { // keep at least one visible
            let b = buckets[idx]
            modes[b.rawValue] = nil
            if idx > 1 { idx -= 1 } else { break }
        }
        return modes
    }
    private func defaultWidth(for mode: String?) -> CGFloat {
        switch mode {
        case "compact": return BoardMetrics.compactWidth
        case "rail": return BoardMetrics.railWidth
        default: return BoardMetrics.expandedWidth
        }
    }
    private func widthFor(bucket: TimeBucket, effectiveMode: String?) -> CGFloat {
        let key = bucket.rawValue
        // Prefer in-memory width while dragging or after prior adjustments
        if let w = userWidthByBucket[key] { return max(220, min(560, w)) }
        // Otherwise, read persisted width without mutating state during render
        if let saved = loadUserWidth(for: bucket) { return max(220, min(560, saved)) }
        return defaultWidth(for: effectiveMode)
    }
    private func adjustWidth(for bucket: TimeBucket, by delta: CGFloat) {
        let key = bucket.rawValue
        let current = userWidthByBucket[key] ?? defaultWidth(for: preferredMode(bucket))
        userWidthByBucket[key] = max(220, min(560, current + delta))
    }
    private func persistUserWidth(for bucket: TimeBucket) {
        let key = bucket.rawValue
        if let w = userWidthByBucket[key] { UserDefaults.standard.set(Double(w), forKey: "board.userWidth.\(key)") }
    }
    private func loadUserWidth(for bucket: TimeBucket) -> CGFloat? {
        let key = bucket.rawValue
        if let v = UserDefaults.standard.object(forKey: "board.userWidth.\(key)") as? NSNumber { return CGFloat(truncating: v) }
        return nil
    }
}
#endif

#if os(macOS)
// MARK: - Rail view (macOS only)
private struct BucketRailView: View {
    let bucket: TimeBucket
    let count: Int
    let onExpand: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Button(action: onExpand) { Image(systemName: "rectangle.leftthird.inset.filled") }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel("Expand \(bucket.displayName)")
            ZStack {
                // Flip full name to read bottom-to-top when collapsed; keep same size as header
                Text(bucket.displayName)
                    .style(Typography.title3)
                    .foregroundColor(Colors.onSurface)
                    .rotationEffect(.degrees(90))
                    .fixedSize()
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.vertical, 4)
            CountBadge(count: count, tint: Colors.color(for: bucket))
        }
        .onTapGesture(count: 2) { onExpand() }
        .padding(.vertical, Spacing.small)
        .frame(width: BoardMetrics.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .surfaceStyle(.content)
        .cornerRadius(12)
        .help("\(bucket.displayName): \(count) tasks")
    }
    // No longer stacking letters; we rotate the full display name instead
}
#endif

#if os(macOS)
// MARK: - Column Resize Handle (hover-only, accent on hover)
private struct ColumnResizeHandle: View {
    let onBegin: () -> Void
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    @State private var isHovering: Bool = false
    @State private var lastX: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(isHovering ? Colors.primary : Colors.onSurface.opacity(0.04))
            .frame(width: 8)
            .overlay(
                Capsule()
                    .fill(isHovering ? Colors.primary : Colors.onSurface.opacity(0.18))
                    .frame(width: 4, height: 36)
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isHovering)
            )
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onBegin()
                        let delta = value.translation.width - lastX
                        lastX = value.translation.width
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        lastX = 0
                        onEnd()
                    }
            )
            .onTapGesture(count: 2) { onBegin(); withAnimation(.easeInOut(duration: 0.18)) { /* no-op here; header handles toggle via onTogglePrimary */ } ; onEnd() }
            .overlay(Rectangle().fill(Colors.onSurface.opacity(isHovering ? 0.28 : 0.12)).frame(width: 1), alignment: .center)
            .help("Drag to resize column")
    }
}
#endif

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
    let onCycleWidthMode: () -> Void
    let onToggleHeader: () -> Void
    let onCollapseToRail: () -> Void
    let onExpandAll: () -> Void
    let onCollapseRight: () -> Void
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
            BucketHeader(bucket: bucket, count: tasksWithLabels.count, onAdd: onAdd, onCycleWidthMode: onCycleWidthMode, onTogglePrimary: onToggleHeader)
                .contextMenu {
                    Button("Collapse to Rail") { onCollapseToRail() }
                    Button("Expand All Buckets") { onExpandAll() }
                    Button("Collapse Right of This") { onCollapseRight() }
                }
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
    let onCycleWidthMode: () -> Void
    let onToggleHeader: () -> Void
    let onCollapseToRail: () -> Void
    let onExpandAll: () -> Void
    let onCollapseRight: () -> Void
    let columnWidth: CGFloat

    private var sections: [WeekdaySection] { WeekPlanner.buildSections(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: .thisWeek, count: tasksWithLabels.count, onAdd: onAdd, onCycleWidthMode: onCycleWidthMode, onTogglePrimary: onToggleHeader)
                .contextMenu {
                    Button("Collapse to Rail") { onCollapseToRail() }
                    Button("Expand All Buckets") { onExpandAll() }
                    Button("Collapse Right of This") { onCollapseRight() }
                }
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

    private func unplannedBadgeNextWeek(for task: Task) -> String? {
        let cal = Calendar.current
        guard let due = task.dueAt else { return "No date" }
        let nextDates = WeekPlanner.datesOfNextWeek(from: Date(), calendar: cal)
        guard let first = nextDates.first, let last = nextDates.last else { return nil }
        let d = cal.startOfDay(for: due)
        if d < cal.startOfDay(for: first) { return "Past" }
        if d > cal.startOfDay(for: last) { return "Future" }
        return nil
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
    let onCycleWidthMode: () -> Void
    let onToggleHeader: () -> Void
    let onCollapseToRail: () -> Void
    let onExpandAll: () -> Void
    let onCollapseRight: () -> Void
    let columnWidth: CGFloat

    private var sections: [WeekdaySection] { WeekPlanner.buildNextWeekSections(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            BucketHeader(bucket: .nextWeek, count: tasksWithLabels.count, onAdd: onAdd, onCycleWidthMode: onCycleWidthMode, onTogglePrimary: onToggleHeader)
                .contextMenu {
                    Button("Collapse to Rail") { onCollapseToRail() }
                    Button("Expand All Buckets") { onExpandAll() }
                    Button("Collapse Right of This") { onCollapseRight() }
                }
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

    private func unplannedBadgeNextWeek(for task: Task) -> String? {
        let cal = Calendar.current
        guard let due = task.dueAt else { return "No date" }
        let nextDates = WeekPlanner.datesOfNextWeek(from: Date(), calendar: cal)
        guard let first = nextDates.first, let last = nextDates.last else { return nil }
        let d = cal.startOfDay(for: due)
        if d < cal.startOfDay(for: first) { return "Past" }
        if d > cal.startOfDay(for: last) { return "Future" }
        return nil
    }

    private var unplannedItems: [(Task, [Label])] {
        let cal = Calendar.current
        let sectionIds = Set(sections.map { $0.id })
        return tasksWithLabels.filter { pair in
            let t = pair.0
            guard t.bucketKey == .nextWeek, t.isCompleted == false else { return false }
            guard let due = t.dueAt else { return true }
            let key = WeekPlanner.isoDayKey(for: cal.startOfDay(for: due))
            return sectionIds.contains(key) == false
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
                        .overlay(alignment: .topTrailing) {
                            if let tag = unplannedBadgeNextWeek(for: pair.0) {
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
        onCycleWidthMode: {},
        onToggleHeader: {},
        onCollapseToRail: {},
        onExpandAll: {},
        onCollapseRight: {},
        columnWidth: 420
    )
    .background(Colors.background)
}
#endif



