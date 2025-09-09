import SwiftUI

struct FilterSheetView: View {
    let userId: UUID
    @Binding var selected: Set<UUID>
    @Binding var availableOnly: Bool
    @Binding var unlabeledOnly: Bool
    @Binding var matchAll: Bool
    let savedFilters: [SavedFilter]
    let onApply: () -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search: String = ""
    @State private var labels: [Label] = []
    @State private var localSelected: Set<UUID>
    @State private var localAvailableOnly: Bool
    @State private var localUnlabeledOnly: Bool
    @State private var localMatchAll: Bool
    @State private var showSaveDialog: Bool = false
    @State private var saveName: String = ""

    init(userId: UUID,
         selected: Binding<Set<UUID>>,
         availableOnly: Binding<Bool>,
         unlabeledOnly: Binding<Bool>,
         matchAll: Binding<Bool>,
         savedFilters: [SavedFilter],
         onApply: @escaping () -> Void,
         onClear: @escaping () -> Void) {
        self.userId = userId
        _selected = selected
        _availableOnly = availableOnly
        _unlabeledOnly = unlabeledOnly
        _matchAll = matchAll
        self.savedFilters = savedFilters
        self.onApply = onApply
        self.onClear = onClear
        _localSelected = State(initialValue: selected.wrappedValue)
        _localAvailableOnly = State(initialValue: availableOnly.wrappedValue)
        _localUnlabeledOnly = State(initialValue: unlabeledOnly.wrappedValue)
        _localMatchAll = State(initialValue: matchAll.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Built-in").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Available", isOn: $localAvailableOnly)
                        Toggle("Unlabeled only", isOn: $localUnlabeledOnly)
                        Toggle("Match all labels", isOn: $localMatchAll)
                    }
                    .padding(.bottom, 8)

                    Text("Presets").font(.headline)
                    if savedFilters.isEmpty {
                        Text("No saved filters").foregroundStyle(Colors.onSurfaceVariant)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(savedFilters) { filter in
                                Button(filter.name) {
                                    localSelected = Set(filter.labelIds)
                                    localMatchAll = filter.matchAll
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    Button("Save Current…") { showSaveDialog = true }
                        .buttonStyle(SecondaryButtonStyle(size: .small))

                    Text("Labels").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { label in
                            HStack {
                                Image(systemName: localSelected.contains(label.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(localSelected.contains(label.id) ? Colors.primary : Colors.onSurfaceVariant)
                                Circle().fill(label.uiColor).frame(width: 14, height: 14)
                                Text(label.name)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(label.id) }
                        }
                    }

                    HStack {
                        Button("Clear All") {
                            dismiss()
                            DispatchQueue.main.async { onClear() }
                        }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                        Spacer()
                        Button("Apply") {
                            selected = localSelected
                            availableOnly = localAvailableOnly
                            unlabeledOnly = localUnlabeledOnly
                            matchAll = localMatchAll
                            dismiss()
                            DispatchQueue.main.async { onApply() }
                        }
                        .buttonStyle(PrimaryButtonStyle(size: .small))
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Filters")
            .searchable(text: $search)
            .task { await load() }
            .sheet(isPresented: $showSaveDialog) { saveSheet }
        }
    }

    private var filtered: [Label] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? labels : labels.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
    private func toggle(_ id: UUID) {
        if localSelected.contains(id) { localSelected.remove(id) } else { localSelected.insert(id) }
    }
    private func load() async {
        let deps = Dependencies.shared
        if let useCases: LabelUseCases = try? deps.resolve(type: LabelUseCases.self) {
            labels = (try? await useCases.fetchLabels(for: userId)) ?? []
        }
    }

    @ViewBuilder
    private var saveSheet: some View {
        VStack(spacing: 12) {
            Text("Save Filter").font(.headline)
            TextField("Name", text: $saveName).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showSaveDialog = false }
                Spacer()
                Button("Save") {
                    let deps = Dependencies.shared
                    if let repo: SavedFiltersRepository = try? deps.resolve(type: SavedFiltersRepository.self) {
                        _Concurrency.Task {
                            try? await repo.create(name: saveName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   labelIds: Array(localSelected),
                                                   matchAll: localMatchAll,
                                                   userId: userId)
                            saveName = ""
                            showSaveDialog = false
                        }
                    }
                }.disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(minWidth: 320)
    }
}

struct FilterSheetPreviewContainer: View {
    @State var selected: Set<UUID> = []
    @State var available: Bool = true
    @State var unlabeled: Bool = false
    @State var matchAll: Bool = false
    var body: some View {
        FilterSheetView(
            userId: UUID(),
            selected: $selected,
            availableOnly: $available,
            unlabeledOnly: $unlabeled,
            matchAll: $matchAll,
            savedFilters: [],
            onApply: {},
            onClear: {}
        )
    }
}

#Preview {
    FilterSheetPreviewContainer()
}


