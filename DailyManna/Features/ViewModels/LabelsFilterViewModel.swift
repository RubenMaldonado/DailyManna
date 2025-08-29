//
//  LabelsFilterViewModel.swift
//  DailyManna
//
//  Inline filtering state for labels (shared across list/board)
//

import Foundation

@MainActor
final class LabelsFilterViewModel: ObservableObject {
    @Published var allLabels: [Label] = []
    @Published var selectedLabelIds: Set<UUID> = []
    @Published var matchAll: Bool = false
    @Published var isDrawerOpen: Bool = false
    @Published var search: String = ""
    let userId: UUID
    private let labelUseCases: LabelUseCases
    
    init(userId: UUID, labelUseCases: LabelUseCases) {
        self.userId = userId
        self.labelUseCases = labelUseCases
    }
    
    func load() async {
        allLabels = (try? await labelUseCases.fetchLabels(for: userId)) ?? []
    }
    
    func toggle(_ id: UUID) {
        if selectedLabelIds.contains(id) { selectedLabelIds.remove(id) } else { selectedLabelIds.insert(id) }
    }
    
    func clear() { selectedLabelIds.removeAll() }
    
    func create(name: String, color: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let label = Label(userId: userId, name: trimmed, color: color)
        try? await labelUseCases.createLabel(label)
        await load()
        selectedLabelIds.insert(label.id)
    }
    
    func createDeterministic(name: String) async {
        let hex = LabelColorHash.colorHex(for: name)
        await create(name: name, color: hex)
    }
    
    var filteredLabels: [Label] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false else { return allLabels }
        return allLabels.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}


