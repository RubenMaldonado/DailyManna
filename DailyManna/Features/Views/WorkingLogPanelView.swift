import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class WorkingLogPanelViewModel: ObservableObject {
    @Published var isOpen: Bool = UserDefaults.standard.bool(forKey: "workingLog.panel.open")
    @Published var searchText: String = ""
    @Published var dateRange: (start: Date, end: Date) = {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        return (start, end)
    }()
    @Published var itemsByDay: [(day: Date, tasks: [Task], notes: [WorkingLogItem])] = []
    @Published private(set) var labelsByTaskId: [UUID: [Label]] = [:]
    // Width persistence (per device)
    @AppStorage("workingLog.panel.width") private var panelWidthStored: Double = 360
    var panelWidth: Double {
        get { max(320, min(520, panelWidthStored)) }
        set { panelWidthStored = max(320, min(520, newValue)) }
    }
    // Range preset for segmented control (-1=all, 0=today, 7, 30)
    @AppStorage("workingLog.panel.rangePreset") var rangePreset: Int = 30
    @Published var collapsedDays: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "workingLog.panel.collapsedDays") ?? [])
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    // New item sheet state
    @Published var isPresentingForm: Bool = false
    @Published var draftTitle: String = ""
    @Published var draftDescription: String = ""
    @Published var draftDate: Date = Date()
    
    private let workingLogUseCases: WorkingLogUseCases
    private let taskUseCases: TaskUseCases
    private let labelsRepository: LabelsRepository
    private let userId: UUID
    
    init(userId: UUID,
         workingLogUseCases: WorkingLogUseCases = try! Dependencies.shared.resolve(type: WorkingLogUseCases.self),
         taskUseCases: TaskUseCases = try! Dependencies.shared.resolve(type: TaskUseCases.self),
         labelsRepository: LabelsRepository = try! Dependencies.shared.resolve(type: LabelsRepository.self)) {
        self.userId = userId
        self.workingLogUseCases = workingLogUseCases
        self.taskUseCases = taskUseCases
        self.labelsRepository = labelsRepository
        NotificationCenter.default.addObserver(forName: Notification.Name("dm.task.completed.changed"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isOpen {
                    await self.reload()
                }
            }
        }
    }
    
    func toggleOpen() {
        isOpen.toggle()
        UserDefaults.standard.set(isOpen, forKey: "workingLog.panel.open")
        if isOpen {
            Telemetry.record(.workingLogOpened)
            _Concurrency.Task { await reload() }
        }
    }
    
    func presentNewItem() {
        draftTitle = ""
        draftDescription = ""
        draftDate = Date()
        isPresentingForm = true
    }
    
    func saveNewItem() async {
        guard draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { errorMessage = "Title is required"; return }
        guard draftDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { errorMessage = "Description is required"; return }
        guard draftDate <= Date() else { errorMessage = "Date cannot be in the future"; return }
        do {
            let item = WorkingLogItem(userId: userId, title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines), description: draftDescription.trimmingCharacters(in: .whitespacesAndNewlines), occurredAt: draftDate)
            try await workingLogUseCases.create(item)
            Telemetry.record(.workingLogItemCreated)
            isPresentingForm = false
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func setRange(days: Int) {
        let end = Date()
        if days < 0 { // ALL
            dateRange = (Date.distantPast, end)
        } else if days == 0 {
            let start = Calendar.current.startOfDay(for: end)
            dateRange = (start, end)
        } else {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            dateRange = (start, end)
        }
        rangePreset = days
        _Concurrency.Task { await reload() }
    }
    
    func toggleDayCollapsed(_ dayKey: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if collapsedDays.contains(dayKey) { collapsedDays.remove(dayKey) } else { collapsedDays.insert(dayKey) }
        }
        UserDefaults.standard.set(Array(collapsedDays), forKey: "workingLog.panel.collapsedDays")
        Telemetry.record(.workingLogDayToggled, metadata: ["day": dayKey])
    }
    
    func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            // Fetch completed tasks in range and their labels
            let pairs = try await taskUseCases.fetchTasksWithLabels(for: userId, in: nil)
            let tasks = pairs
                .map { $0.0 }
                .filter { $0.isCompleted && $0.completedAt != nil && $0.completedAt! >= dateRange.start && $0.completedAt! <= dateRange.end }
            var map: [UUID: [Label]] = [:]
            for (t, ls) in pairs { map[t.id] = ls }
            self.labelsByTaskId = map
            let notes: [WorkingLogItem]
            if searchText.isEmpty {
                notes = try await workingLogUseCases.fetchRange(userId: userId, startDate: dateRange.start, endDate: dateRange.end)
            } else {
                notes = try await workingLogUseCases.search(userId: userId, text: searchText, startDate: dateRange.start, endDate: dateRange.end)
            }
            let grouped = groupByLocalDay(tasks: tasks, notes: notes)
            await MainActor.run { self.itemsByDay = grouped }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Collapse helpers
    func collapseOlderThan(days: Int) {
        let cal = Calendar.current
        let threshold = cal.startOfDay(for: cal.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        var updated = collapsedDays
        for (day, _, _) in itemsByDay { if day < threshold { updated.insert(dayKey(for: day)) } }
        withAnimation(.easeInOut(duration: 0.2)) { collapsedDays = updated }
        UserDefaults.standard.set(Array(collapsedDays), forKey: "workingLog.panel.collapsedDays")
    }
    func collapseAll() {
        let updated = Set(itemsByDay.map { dayKey(for: $0.0) })
        withAnimation(.easeInOut(duration: 0.2)) { collapsedDays = updated }
        UserDefaults.standard.set(Array(collapsedDays), forKey: "workingLog.panel.collapsedDays")
    }
    func expandAll() {
        withAnimation(.easeInOut(duration: 0.2)) { collapsedDays.removeAll() }
        UserDefaults.standard.set(Array(collapsedDays), forKey: "workingLog.panel.collapsedDays")
    }
    private func dayKey(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    
    private func groupByLocalDay(tasks: [Task], notes: [WorkingLogItem]) -> [(Date, [Task], [WorkingLogItem])] {
        let cal = Calendar.current
        let byTask: [Date: [Task]] = Dictionary(grouping: tasks, by: { t in cal.startOfDay(for: t.completedAt ?? Date.distantPast) })
        let byNote: [Date: [WorkingLogItem]] = Dictionary(grouping: notes, by: { n in cal.startOfDay(for: n.occurredAt) })
        let allDays = Set(byTask.keys).union(Set(byNote.keys))
        let ordered = allDays.sorted(by: { $0 > $1 })
        return ordered.map { day in
            let ts = (byTask[day] ?? []).sorted { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) }
            let ns = (byNote[day] ?? []).sorted { $0.occurredAt > $1.occurredAt }
            return (day, ts, ns)
        }
    }
}

struct WorkingLogPanelView: View {
    @ObservedObject var viewModel: WorkingLogPanelViewModel
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif
    @State private var didInitialLoad: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                header
                Divider()
                content
            }
            #if !os(macOS)
            if hSizeClass == .compact {
                // Floating Add button (iPhone compact only)
                Button {
                    viewModel.presentNewItem()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .padding(14)
                }
                .background(Colors.primary)
                .foregroundColor(Colors.onPrimary)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(16)
            }
            #endif
        }
        .frame(width: viewModel.panelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .surfaceStyle(.chrome)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Colors.outline)
                .frame(width: 1)
                .ignoresSafeArea()
        }
        .shadow(color: .black.opacity(0.1), radius: 10, x: -2, y: 0)
        .overlay(alignment: .leading) { // Resize handle
            ResizeHandle(width: $viewModel.panelWidth)
        }
        .ignoresSafeArea(edges: [.bottom])
        .padding(.top, 12)
        .sheet(isPresented: $viewModel.isPresentingForm) {
            creationSheet
        }
        .task {
            if didInitialLoad == false {
                await viewModel.reload()
                didInitialLoad = true
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sidebar.right").foregroundStyle(Colors.onSurfaceVariant)
                Text("Working Log").style(Typography.title3)
                Spacer()
                Button { viewModel.presentNewItem() } label: { HStack(spacing: 6) { Image(systemName: "plus"); Text("Add Log Item") } }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
            }
            HStack(spacing: 8) {
                Picker("Range", selection: $viewModel.rangePreset) {
                    Text("All").tag(-1)
                    Text("Today").tag(0)
                    Text("7d").tag(7)
                    Text("30d").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 240, maxWidth: 360)
                .onChange(of: viewModel.rangePreset) { _, v in viewModel.setRange(days: v) }
                Menu {
                    // Collapse actions
                    Section("Collapse") {
                        Button("Older than 7 days") { viewModel.collapseOlderThan(days: 7) }
                        Button("Older than 30 days") { viewModel.collapseOlderThan(days: 30) }
                        Button("Collapse all") { viewModel.collapseAll() }
                        Button("Expand all") { viewModel.expandAll() }
                    }
                    // Export actions
                    Section("Export") {
                        Button("Export Markdown") {
                            let md = WorkingLogMarkdownExporter.generate(rangeStart: viewModel.dateRange.start, rangeEnd: viewModel.dateRange.end, itemsByDay: viewModel.itemsByDay)
                            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                            let name = "Working-Log_\(f.string(from: viewModel.dateRange.start))_to_\(f.string(from: viewModel.dateRange.end)).md"
                            do {
                                let url = try WorkingLogMarkdownExporter.saveToDefaultLocation(filename: name, contents: md)
                                Telemetry.record(.workingLogExportMarkdown, metadata: ["file": url.lastPathComponent])
                            } catch {}
                        }
                    }
                } label: { HStack(spacing: 6) { Image(systemName: "slider.horizontal.3"); Text("Options") } }
                .buttonStyle(SecondaryButtonStyle(size: .small))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
    
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Colors.onSurfaceVariant)
                    TextField("Search…", text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0; _Concurrency.Task { await viewModel.reload() } }))
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 12)
                if viewModel.isLoading { ProgressView().padding() }
                ForEach(viewModel.itemsByDay, id: \.0) { (day, tasks, notes) in
                    DaySection(day: day, tasks: tasks, notes: notes, labelsByTaskId: viewModel.labelsByTaskId, collapsed: viewModel.collapsedDays.contains(dayKey(day))) {
                        viewModel.toggleDayCollapsed(dayKey(day))
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Creation Sheet
extension WorkingLogPanelView {
    @ViewBuilder
    var creationSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Log Item").font(.headline)
            TextField("Title", text: $viewModel.draftTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: $viewModel.draftDescription, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            DatePicker("Date", selection: $viewModel.draftDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
            HStack {
                Button("Cancel") { viewModel.isPresentingForm = false }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                Spacer()
                Button("Add Item") { _Concurrency.Task { await viewModel.saveNewItem() } }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
                    .disabled(viewModel.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.draftDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.draftDate > Date())
            }
        }
        .padding()
        .frame(minWidth: 360)
    }
}

private func dayKey(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

private struct DaySection: View {
    let day: Date
    let tasks: [Task]
    let notes: [WorkingLogItem]
    let labelsByTaskId: [UUID: [Label]]
    let collapsed: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack {
                Text(formattedDay(day)).font(.subheadline).bold()
                Spacer()
                Button(action: onToggle) {
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                }.buttonStyle(SecondaryButtonStyle(size: .small))
            }
            .padding(.horizontal, 12)
            if !collapsed {
                if !tasks.isEmpty {
                    Text(sectionLabel(for: day)).font(.caption).padding(.horizontal, 12)
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        ForEach(tasks, id: \.id) { t in
                            WorkingLogTaskRow(task: t, labels: labelsByTaskId[t.id] ?? [])
                        }
                    }
                    .padding(.horizontal, 12)
                }
                if !notes.isEmpty {
                    Text("Log Items").font(.caption).padding(.horizontal, 12)
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        ForEach(notes, id: \.id) { n in
                            WorkingLogItemCard(item: n)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }
    
    private func formattedDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private func sectionLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Tasks — Today" }
        if cal.isDateInYesterday(date) { return "Tasks — Yesterday" }
        return "Tasks"
    }
}

private struct WorkingLogItemCard: View {
    let item: WorkingLogItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "note.text")
                Text(item.title).font(.subheadline)
                Spacer()
                Text(timeString(item.occurredAt)).font(.caption).foregroundStyle(.secondary)
            }
            Text(item.description).font(.footnote)
        }
        .padding(8)
        .surfaceStyle(.chrome)
        .cornerRadius(8)
    }
    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// Monochrome label chips (no color fill) to match request
private struct MonochromeChips: View {
    let labels: [Label]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xxSmall) {
                ForEach(labels) { label in
                    HStack(spacing: 6) {
                        Circle().fill(Colors.onSurfaceVariant.opacity(0.35)).frame(width: 6, height: 6)
                        Text(label.name).font(.caption2).foregroundStyle(Colors.onSurface)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Colors.surfaceVariant.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

// Resize handle area on the left edge of the panel
private struct ResizeHandle: View {
    @Binding var width: Double
    @State private var dragStart: Double = 0
    var body: some View {
        Rectangle().fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                if dragStart == 0 { dragStart = width }
                let delta = -value.translation.width
                width = dragStart + delta
            }.onEnded { _ in dragStart = 0 })
            .overlay(alignment: .trailing) { Rectangle().fill(Colors.outline.opacity(0.6)).frame(width: 1) }
            #if os(macOS)
            .onHover { hovering in NSCursor.resizeLeftRight.set() }
            #endif
    }
}

// Compact task row for Working Log: title line, then a metadata row (labels + completed time)
private struct WorkingLogTaskRow: View {
    let task: Task
    let labels: [Label]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title (strikethrough if completed)
            Text(task.title)
                .style(Typography.headline)
                .strikethrough(task.isCompleted)
                .foregroundColor(task.isCompleted ? Colors.onSurfaceVariant : Colors.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            // Metadata line
            HStack(alignment: .center, spacing: 8) {
                if labels.isEmpty == false {
                    MonochromeChips(labels: labels)
                }
                Spacer(minLength: 0)
                if let completed = task.completedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDateTime(completed))
                    }
                    .font(.caption2)
                    .foregroundStyle(Colors.onSurfaceVariant)
                }
            }
        }
        .padding(8)
        .surfaceStyle(.content)
        .cornerRadius(8)
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}


