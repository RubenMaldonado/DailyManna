//
//  LabelManagementView.swift
//  DailyManna
//
//  Created for Epic 2.1
//

import SwiftUI

@MainActor
final class LabelManagementViewModel: ObservableObject {
    @Published var labels: [Label] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var isPresentingEditor = false
    @Published var draftName: String = ""
    @Published var draftColor: String = Colors.labelPalette.first ?? "#3B82F6"
    @Published var editingLabel: Label? = nil
    let userId: UUID
    private let labelUseCases: LabelUseCases
    
    init(userId: UUID, labelUseCases: LabelUseCases) {
        self.userId = userId
        self.labelUseCases = labelUseCases
    }
    
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            labels = try await labelUseCases.fetchLabels(for: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func presentCreate() {
        editingLabel = nil
        draftName = ""
        draftColor = Colors.labelPalette.first ?? "#3B82F6"
        isPresentingEditor = true
    }
    
    func presentEdit(_ label: Label) {
        editingLabel = label
        draftName = label.name
        draftColor = label.color
        isPresentingEditor = true
    }
    
    func save() async {
        guard draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        do {
            if var editing = editingLabel {
                editing.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                editing.color = draftColor
                try await labelUseCases.updateLabel(editing)
            } else {
                let label = Label(userId: userId, name: draftName.trimmingCharacters(in: .whitespacesAndNewlines), color: draftColor)
                try await labelUseCases.createLabel(label)
            }
            isPresentingEditor = false
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Convenience for inline manager: create and reload without using the sheet
    func create(name: String, color: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        do {
            let label = Label(userId: userId, name: trimmed, color: color)
            try await labelUseCases.createLabel(label)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func delete(_ label: Label) async {
        do {
            try await labelUseCases.deleteLabel(by: label.id, for: userId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LabelManagementView: View {
    @StateObject var viewModel: LabelManagementViewModel
    init(viewModel: LabelManagementViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    
    var body: some View {
        NavigationStack {
            content
                .animation(.default, value: viewModel.labels.count)
                .searchable(text: $search)
                .navigationTitle("Labels")
                .toolbar {
                    #if os(macOS)
                    ToolbarItem(placement: .automatic) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .automatic) { Button("New") { viewModel.presentCreate() } }
                    #else
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("New") { viewModel.presentCreate() } }
                    #endif
                }
            .task {
                // Ensure local store is hydrated before first load
                let deps = Dependencies.shared
                if let sync: SyncService = try? deps.resolve(type: SyncService.self) {
                    await sync.sync(for: viewModel.userId)
                }
                await viewModel.load()
            }
            .onChange(of: viewModel.isPresentingEditor) { _, showing in
                if showing == false { _Concurrency.Task { await viewModel.load() } }
            }
            .sheet(isPresented: $viewModel.isPresentingEditor) {
                LabelEditorSheet(name: $viewModel.draftName, selectedHex: $viewModel.draftColor, onSave: { _Concurrency.Task { await viewModel.save() } }, onCancel: { viewModel.isPresentingEditor = false })
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let error = viewModel.errorMessage { Text(error).foregroundColor(.red) }
                ForEach(filteredLabels, id: \.id) { label in rowView(label) }
            }
            .padding(.horizontal)
        }
        #else
        List {
            if let error = viewModel.errorMessage { Text(error).foregroundColor(.red) }
            ForEach(filteredLabels, id: \.id) { label in rowView(label) }
        }
        .listStyle(.inset)
        #endif
    }

    private var filteredLabels: [Label] {
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return viewModel.labels }
        return viewModel.labels.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    @ViewBuilder
    private func rowView(_ label: Label) -> some View {
        HStack {
            Circle().fill(label.uiColor).frame(width: 14, height: 14)
            Text(label.name)
            Spacer()
            Button("Edit") { viewModel.presentEdit(label) }
                .buttonStyle(.borderless)
                .foregroundColor(Colors.primary)
            Button(role: .destructive) { _Concurrency.Task { await viewModel.delete(label) } } label: { Text("Delete") }
                .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.presentEdit(label) }
    }
}

private struct LabelEditorSheet: View {
    @Binding var name: String
    @Binding var selectedHex: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(Colors.labelPalette, id: \.self) { hex in
                            ZStack {
                                Circle().fill(Color(hex: hex) ?? .gray).frame(width: 28, height: 28)
                                if hex == selectedHex { Image(systemName: "checkmark.circle.fill").foregroundColor(.white) }
                            }
                            .onTapGesture { selectedHex = hex }
                            .accessibilityLabel(hex)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Label")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}


