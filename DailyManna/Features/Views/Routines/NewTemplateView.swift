import SwiftUI

struct NewTemplateView: View {
    @StateObject private var viewModel: NewTemplateViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm: Bool = false
    
    init(userId: UUID, editing: Template? = nil, series: Series? = nil) {
        _viewModel = StateObject(wrappedValue: NewTemplateViewModel(userId: userId, editing: editing, series: series))
    }
    
    var body: some View {
        Group {
            #if os(macOS)
            macLayout
            #else
            iOSLayout
            #endif
        }
        .onChange(of: viewModel.frequency) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.interval) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.selectedWeekdays) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.monthDay) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.monthlyKind) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.monthlyOrdinal) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.monthlyWeekday) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.yearlyMonth) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.yearlyKind) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.yearlyDay) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.yearlyOrdinal) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.yearlyWeekday) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.defaultTime) { _ in viewModel.recomputePreview() }
        .onChange(of: viewModel.startsOn) { _ in viewModel.recomputePreview() }
        .navigationTitle(viewTitle)
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Delete template and future instances?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let doDismiss = dismiss
                doDismiss()
                _Concurrency.Task { await viewModel.deleteTemplateAndFutureInstances() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the template, pause/delete its series, and delete only upcoming instances. Past tasks remain.")
        }
    }
    
    // MARK: - macOS
    @ViewBuilder
    private var macLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            form
                .frame(minWidth: 360, maxWidth: 420)
            Divider()
            previewPanel
                .frame(minWidth: 320)
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
    }
    
    // MARK: - iOS
    private var iOSLayout: some View {
        VStack(spacing: 0) {
            form
            Divider()
            bottomBar
        }
    }
    
    // MARK: - Shared subviews
    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $viewModel.name)
                TextField("Description", text: $viewModel.descriptionText, axis: .vertical)
                Picker("Priority", selection: $viewModel.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { p in
                        Text(p.rawValue.capitalized).tag(p)
                    }
                }
                DatePicker("Default Time", selection: $viewModel.defaultTime, displayedComponents: [.hourAndMinute])
            }
            Section(header: Text("Recurrence")) {
                RecurrenceBuilderView(viewModel: viewModel)
            }
        }
    }
    
    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.summaryText)
                .foregroundStyle(.secondary)
            if viewModel.upcomingPreview.isEmpty {
                ContentUnavailableView("No upcoming occurrences", systemImage: "calendar")
            } else {
                List(viewModel.upcomingPreview, id: \.self) { d in
                    HStack {
                        Image(systemName: "calendar")
                        Text(DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .short))
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 240)
            }
            Spacer()
        }
    }
    
    private var bottomBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Save") {
                let doDismiss = dismiss
                doDismiss()
                _Concurrency.Task { await viewModel.save() }
            }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSave)
        }
        .padding()
        .background(Material.ultraThin)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                let doDismiss = dismiss
                doDismiss()
                _Concurrency.Task { await viewModel.save() }
            }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSave)
        }
        // Delete (edit mode only)
        if !viewModel.name.isEmpty {
            ToolbarItem(placement: .destructiveAction) {
                Button { showDeleteConfirm = true } label: { Image(systemName: "trash") }
            }
        }
    }

    private var viewTitle: String {
        viewModel.name.isEmpty ? "New Template" : "Edit Template"
    }
}


