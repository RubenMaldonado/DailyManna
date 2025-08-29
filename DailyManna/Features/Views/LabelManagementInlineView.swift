//
//  LabelManagementInlineView.swift
//  DailyManna
//
//  Inline labels manager for Settings (no popups, no extra toolbars).
//

import SwiftUI

struct LabelManagementInlineView: View {
    @StateObject private var vm: LabelManagementViewModel
    @State private var search: String = ""
    @State private var newName: String = ""
    @State private var newColor: String = Colors.labelPalette.first ?? "#3B82F6"
    
    init(userId: UUID) {
        let deps = Dependencies.shared
        let useCases: LabelUseCases = try! deps.resolve(type: LabelUseCases.self)
        _vm = StateObject(wrappedValue: LabelManagementViewModel(userId: userId, labelUseCases: useCases))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Labels").style(Typography.headline)
            // Search
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
            
            // Inline create row
            HStack(spacing: 8) {
                TextField("New label name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Colors.labelPalette, id: \.self) { hex in
                            ZStack {
                                Circle().fill(Color(hex: hex) ?? .gray).frame(width: 22, height: 22)
                                if hex == newColor { Image(systemName: "checkmark").font(.caption2).foregroundColor(.white) }
                            }
                            .onTapGesture { newColor = hex }
                        }
                    }
                }
                Button("New") { _Concurrency.Task { await vm.create(name: newName, color: newColor); newName = "" } }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            // List
            VStack(spacing: 8) {
                if let error = vm.errorMessage { Text(error).foregroundColor(.red) }
                ForEach(filtered, id: \.id) { label in
                    if vm.editingLabel?.id == label.id {
                        editRow(label)
                    } else {
                        row(label)
                    }
                }
            }
        }
        .padding()
        .surfaceStyle(.content)
        .cornerRadius(12)
        .task { await vm.load() }
    }
    
    private var filtered: [Label] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false else { return vm.labels }
        return vm.labels.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
    
    @ViewBuilder
    private func row(_ label: Label) -> some View {
        HStack {
            Circle().fill(label.uiColor).frame(width: 14, height: 14)
            Text(label.name)
            Spacer()
            Button("Edit") { vm.presentEdit(label) }.buttonStyle(.plain).foregroundColor(Colors.primary)
            Button(role: .destructive) { _Concurrency.Task { await vm.delete(label) } } label: { Text("Delete") }.buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func editRow(_ label: Label) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Colors.labelPalette, id: \.self) { hex in
                        ZStack {
                            Circle().fill(Color(hex: hex) ?? .gray).frame(width: 22, height: 22)
                            if hex == vm.draftColor { Image(systemName: "checkmark").font(.caption2).foregroundColor(.white) }
                        }
                        .onTapGesture { vm.draftColor = hex }
                    }
                }
            }
            TextField("Name", text: $vm.draftName)
                .textFieldStyle(.roundedBorder)
            Button("Save") { _Concurrency.Task { await vm.save() } }.buttonStyle(PrimaryButtonStyle(size: .small))
            Button("Cancel") { vm.isPresentingEditor = false; vm.editingLabel = nil }.buttonStyle(SecondaryButtonStyle(size: .small))
        }
        .padding(.vertical, 4)
    }
}


