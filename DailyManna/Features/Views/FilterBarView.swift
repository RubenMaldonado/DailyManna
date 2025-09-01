//
//  FilterBarView.swift
//  DailyManna
//
//  Inline labels filter bar with chips, add-field, saved filters, and options.
//

import SwiftUI

struct FilterBarView: View {
    @ObservedObject var vm: LabelsFilterViewModel
    var onSelectionChanged: ((Set<UUID>, Bool) -> Void)? = nil
    var onSelectUnlabeled: (() -> Void)? = nil
    var onClearAll: (() -> Void)? = nil
    var unlabeledActive: Bool = false
    @FocusState private var isAddFocused: Bool
    @State private var draftName: String = ""
    @State private var savedFilters: [SavedFilter] = []
    @State private var showSaveSheet = false
    @State private var saveName: String = ""
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(vm.allLabels.filter { vm.selectedLabelIds.contains($0.id) }) { label in
                            HStack(spacing: 4) {
                                LabelChip(label: label)
                                Button { vm.toggle(label.id) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                TextField("Add label…", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isAddFocused)
                    .onSubmit { createOrToggle() }
                    .onChange(of: draftName) { _, _ in /* live suggestions shown below */ }
                Menu("Saved") {
                    // Built-in session-only saved filter
                    Button(action: {
                        onSelectionChanged?([], false)
                        onSelectUnlabeled?()
                    }) {
                        HStack {
                            Text("Unlabeled")
                            if unlabeledActive { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    if savedFilters.isEmpty { Text("No saved filters") }
                    ForEach(savedFilters) { filter in
                        Button(filter.name) {
                            vm.selectedLabelIds = Set(filter.labelIds)
                            vm.matchAll = filter.matchAll
                        }
                    }
                    Divider()
                    Button("Save Current…") { showSaveSheet = true }
                }
                .menuStyle(.borderlessButton)

                Menu("Options") {
                    Toggle(isOn: $vm.matchAll) { Text("Match all") }
                    if vm.selectedLabelIds.isEmpty == false {
                        Divider()
                        Button("Clear") { onClearAll?() ?? vm.clear() }
                    }
                }
                .menuStyle(.borderlessButton)
                if unlabeledActive || vm.selectedLabelIds.isEmpty == false {
                    Button("Clear filters") { onClearAll?() ?? vm.clear() }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                }
            }
            // Suggestions dropdown (inline, non-blocking)
            if draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                SuggestionsList(query: draftName, vm: vm, commit: { name in
                    if let existing = vm.allLabels.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        vm.toggle(existing.id)
                    } else {
                        _Concurrency.Task { await vm.createDeterministic(name: name) }
                    }
                    draftName = ""
                    isAddFocused = true
                })
            }
        }
        .surfaceStyle(.chrome)
        .padding(.vertical, 4)
        .task { await vm.load(); await loadSaved() }
        .onChange(of: vm.selectedLabelIds) { _, ids in onSelectionChanged?(ids, vm.matchAll) }
        .onChange(of: vm.matchAll) { _, _ in onSelectionChanged?(vm.selectedLabelIds, vm.matchAll) }
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }
    
    private func createOrToggle() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }
        if let existing = vm.allLabels.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            vm.toggle(existing.id)
        } else {
            _Concurrency.Task { await vm.createDeterministic(name: name) }
        }
        draftName = ""
        isAddFocused = true
    }
}
private extension FilterBarView {
    func loadSaved() async {
        let deps = Dependencies.shared
        if let repo: SavedFiltersRepository = try? deps.resolve(type: SavedFiltersRepository.self) {
            savedFilters = (try? await repo.list(for: vm.userId)) ?? []
        }
    }

    var saveSheet: some View {
        VStack(spacing: 12) {
            Text("Save Filter").font(.headline)
            TextField("Name", text: $saveName).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showSaveSheet = false }
                Spacer()
                Button("Save") {
                    let deps = Dependencies.shared
                    if let repo: SavedFiltersRepository = try? deps.resolve(type: SavedFiltersRepository.self) {
                        _Concurrency.Task {
                            try? await repo.create(name: saveName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   labelIds: Array(vm.selectedLabelIds),
                                                   matchAll: vm.matchAll,
                                                   userId: vm.userId)
                            await loadSaved()
                            showSaveSheet = false
                            saveName = ""
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

private struct SuggestionsList: View {
    let query: String
    @ObservedObject var vm: LabelsFilterViewModel
    let commit: (String) -> Void
    var body: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = vm.allLabels
            .filter { !$0.name.isEmpty && vm.selectedLabelIds.contains($0.id) == false }
            .sorted { a, b in
                // starts-with first
                let aStart = a.name.lowercased().hasPrefix(q.lowercased())
                let bStart = b.name.lowercased().hasPrefix(q.lowercased())
                if aStart != bStart { return aStart && !bStart }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .filter { $0.name.localizedCaseInsensitiveContains(q) }
            .prefix(12)

        return VStack(alignment: .leading, spacing: 4) {
            if matches.isEmpty {
                Button(action: { commit(q) }) {
                    HStack { Image(systemName: "plus.circle"); Text("Create \(q)") }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)
            } else {
                ForEach(Array(matches), id: \.id) { label in
                    Button(action: { commit(label.name) }) {
                        HStack(spacing: 8) {
                            Circle().fill(label.uiColor).frame(width: 10, height: 10)
                            Text(label.name)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
        .surfaceStyle(.content)
        .cornerRadius(8)
    }
}


