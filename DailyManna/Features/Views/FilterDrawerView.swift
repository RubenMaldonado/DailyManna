//
//  FilterDrawerView.swift
//  DailyManna
//
//  Collapsible drawer showing all labels as chips with search and inline create.
//

import SwiftUI

struct FilterDrawerView: View {
    @ObservedObject var vm: LabelsFilterViewModel
    @State private var newName: String = ""
    @State private var newColor: String = Colors.labelPalette.first ?? "#3B82F6"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search labels", text: $vm.search)
                    .textFieldStyle(.roundedBorder)
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 100), spacing: 8), count: 4), spacing: 8) {
                    Button(action: { /* create inline via editor row */ }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Create new…")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                    .disabled(true) // Visual hint; real create row below
                    
                    ForEach(vm.filteredLabels) { label in
                        let selected = vm.selectedLabelIds.contains(label.id)
                        Button {
                            vm.toggle(label.id)
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(label.uiColor).frame(width: 10, height: 10)
                                Text(label.name)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? Colors.surface : Colors.surface.opacity(0.6))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Colors.outline, lineWidth: selected ? 1.0 : 0.5))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            
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
                Button("Create") { _Concurrency.Task { await vm.create(name: newName, color: newColor); newName = "" } }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        .surfaceStyle(.content)
        .cornerRadius(12)
    }
}


