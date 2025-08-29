//
//  FilterBarView.swift
//  DailyManna
//
//  Inline labels filter bar with chips, add-field, match mode, and clear.
//

import SwiftUI

struct FilterBarView: View {
    @ObservedObject var vm: LabelsFilterViewModel
    @FocusState private var isAddFocused: Bool
    @State private var draftName: String = ""
    
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
        .task { await vm.load() }
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


