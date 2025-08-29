//
//  InlineTaskLabelSelector.swift
//  DailyManna
//
//  Inline tokenized selector for assigning labels to a task (no popup).
//

import SwiftUI

struct InlineTaskLabelSelector: View {
    let userId: UUID
    @Binding var selected: Set<UUID>
    @StateObject private var vm: LabelsFilterViewModel
    @FocusState private var isFocused: Bool
    @State private var draftName: String = ""
    
    init(userId: UUID, selected: Binding<Set<UUID>>) {
        self.userId = userId
        _selected = selected
        let deps = Dependencies.shared
        let useCases: LabelUseCases = try! deps.resolve(type: LabelUseCases.self)
        _vm = StateObject(wrappedValue: LabelsFilterViewModel(userId: userId, labelUseCases: useCases))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.allLabels.filter { selected.contains($0.id) }) { label in
                        HStack(spacing: 4) {
                            LabelChip(label: label)
                            Button { toggle(label.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            TextField("Assign Labels…", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { commit(draftName) }
                .onChange(of: draftName) { _, _ in }
            if draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { suggestions }
        }
        .task { await vm.load() }
        .onChange(of: vm.allLabels) { _, _ in syncFromExternal() }
    }
    
    private func syncFromExternal() {
        // ensure selected set remains valid when labels change
        selected = selected.intersection(Set(vm.allLabels.map { $0.id }))
    }
    
    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    
    private func commit(_ name: String) {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false else { return }
        if let existing = vm.allLabels.first(where: { $0.name.caseInsensitiveCompare(q) == .orderedSame }) {
            toggle(existing.id)
        } else {
            _Concurrency.Task { await vm.createDeterministic(name: q); if let newly = vm.allLabels.first(where: { $0.name.caseInsensitiveCompare(q) == .orderedSame }) { selected.insert(newly.id) } }
        }
        draftName = ""
        isFocused = true
    }
    
    private var suggestions: some View {
        let q = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = vm.allLabels
            .filter { !selected.contains($0.id) }
            .sorted { a, b in
                let aStart = a.name.lowercased().hasPrefix(q.lowercased())
                let bStart = b.name.lowercased().hasPrefix(q.lowercased())
                if aStart != bStart { return aStart && !bStart }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .filter { $0.name.localizedCaseInsensitiveContains(q) }
            .prefix(10)
        return VStack(alignment: .leading, spacing: 4) {
            if matches.isEmpty {
                Button(action: { commit(q) }) { HStack { Image(systemName: "plus.circle"); Text("Create \(q)") } }
                    .buttonStyle(.plain)
            } else {
                ForEach(Array(matches), id: \.id) { label in
                    Button(action: { commit(label.name) }) {
                        HStack(spacing: 8) { Circle().fill(label.uiColor).frame(width: 10, height: 10); Text(label.name) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .surfaceStyle(.content)
        .cornerRadius(8)
    }
}


