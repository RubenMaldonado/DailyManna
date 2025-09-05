import SwiftUI

struct LabelMultiSelectSheet: View {
    let userId: UUID
    @Binding var selected: Set<UUID>
    @StateObject private var vm: LabelsFilterViewModel
    @State private var search: String = ""

    init(userId: UUID, selected: Binding<Set<UUID>>) {
        self.userId = userId
        _selected = selected
        let deps = Dependencies.shared
        let useCases: LabelUseCases = try! deps.resolve(type: LabelUseCases.self)
        _vm = StateObject(wrappedValue: LabelsFilterViewModel(userId: userId, labelUseCases: useCases))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Type a label", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredLabels) { label in
                        HStack(spacing: 10) {
                            Circle().fill(label.uiColor).frame(width: 10, height: 10)
                            Text(label.name)
                            Spacer()
                            #if os(macOS)
                            Toggle("", isOn: Binding(get: { selected.contains(label.id) }, set: { isOn in toggle(label.id, isOn: isOn) }))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            #else
                            Button(action: { toggle(label.id, isOn: !selected.contains(label.id)) }) {
                                Image(systemName: selected.contains(label.id) ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(label.id, isOn: !selected.contains(label.id)) }
                    }
                }
            }
            HStack {
                Button("Clear") { selected.removeAll() }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                Spacer()
                Button("Done") { dismissSelf() }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
            }
        }
        .padding()
        .task { await vm.load() }
    }

    private var filteredLabels: [Label] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false else { return vm.allLabels }
        return vm.allLabels.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func toggle(_ id: UUID, isOn: Bool) {
        if isOn { selected.insert(id) } else { selected.remove(id) }
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissSelf() { dismiss() }
}


