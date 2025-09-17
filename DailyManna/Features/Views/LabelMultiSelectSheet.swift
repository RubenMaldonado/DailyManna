import SwiftUI

struct LabelMultiSelectSheet: View {
    let userId: UUID
    @Binding var selected: Set<UUID>
    @StateObject private var vm: LabelsFilterViewModel
    @State private var search: String = ""
    @State private var isCreating: Bool = false
    @State private var createName: String = ""
    @State private var createColor: String = (Colors.labelPalette.first ?? "#3B82F6")
    @State private var errorText: String? = nil

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
                .onChange(of: search) { _, q in
                    createName = q
                    errorText = nil
                }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if showCreateRowAtTop { createRow }
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
                            Button(action: { toggle(label.id, isOn: !selected.contains(label.id)) }) { Image(systemName: selected.contains(label.id) ? "checkmark.circle.fill" : "circle") }
                                .buttonStyle(.plain)
                            #endif
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(label.id, isOn: !selected.contains(label.id)) }
                    }
                    if showCreateRowAtBottom { createRow }
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

    private var showCreateRowAtTop: Bool {
        let q = trimmedQuery
        return !q.isEmpty && filteredLabels.isEmpty
    }

    private var showCreateRowAtBottom: Bool {
        let q = trimmedQuery
        guard !q.isEmpty && filteredLabels.isEmpty == false else { return false }
        return filteredLabels.contains(where: { $0.name.compare(q, options: .caseInsensitive) == .orderedSame }) == false
    }

    private var trimmedQuery: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder
    private var createRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { beginCreate() }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundColor(Colors.primary)
                    Text("Create \"\(trimmedQuery)\"")
                        .style(Typography.body)
                        .foregroundColor(Colors.onSurface)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            if isCreating { createMiniForm }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var createMiniForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Label name", text: $createName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                ForEach(Array(Colors.labelPalette.prefix(8)), id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? Colors.surface)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(createColor == hex ? Colors.onSurface : .clear, lineWidth: 2))
                        .onTapGesture { createColor = hex }
                }
                Spacer()
                Button("Cancel") { cancelCreate() }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                Button("Create") { _Concurrency.Task { await performCreate() } }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
                    .disabled(createDisabled)
            }
            if let error = errorText { Text(error).style(Typography.caption).foregroundColor(Colors.onSurfaceVariant) }
        }
    }

    private var createDisabled: Bool {
        let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > 30 { return true }
        return vm.allLabels.contains { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    private func beginCreate() { isCreating = true; createName = trimmedQuery; errorText = nil }
    private func cancelCreate() { isCreating = false; createName = ""; errorText = nil }

    private func performCreate() async {
        let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }
        if vm.allLabels.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
            if let existing = vm.allLabels.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                selected.insert(existing.id)
            }
            errorText = "Already exists"
            return
        }
        await vm.create(name: name, color: createColor)
        await vm.load()
        if let new = vm.allLabels.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
            selected.insert(new.id)
        }
        isCreating = false
        search = name
    }

    private func toggle(_ id: UUID, isOn: Bool) {
        if isOn { selected.insert(id) } else { selected.remove(id) }
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissSelf() { dismiss() }
}


