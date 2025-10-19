import SwiftUI

struct TemplateEditorView: View {
    let userId: UUID
    @State var name: String = ""
    @State var descriptionText: String = ""
    @State var defaultTime: Date = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State var priority: TaskPriority = .normal
    @State var endAfterCount: String = ""
    @State var weeklyInterval: Int = 1
    @State var anchorWeekday: Int = Calendar.current.component(.weekday, from: Date())
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basics")) {
                    TextField("Name", text: $name)
                    TextField("Description", text: $descriptionText, axis: .vertical)
                }
                Section(header: Text("Defaults")) {
                    DatePicker("Default Time", selection: $defaultTime, displayedComponents: [.hourAndMinute])
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag(TaskPriority.low)
                        Text("Normal").tag(TaskPriority.normal)
                        Text("High").tag(TaskPriority.high)
                    }
                    TextField("End after N occurrences (optional)", text: $endAfterCount)
                }
                Section(header: Text("Recurrence")) {
                    Stepper(value: $weeklyInterval, in: 1...8) { Text("Every \(weeklyInterval) week(s)") }
                    Picker("Weekday", selection: $anchorWeekday) {
                        ForEach(1...7, id: \.self) { wd in Text(weekdayName(wd)).tag(wd) }
                    }
                }
                Section(header: Text("Preview (next 7)")) {
                    ForEach(nextSevenDates(), id: \.self) { d in
                        Text("\(DateFormatter.shortDate.string(from: d))")
                    }
                }
            }
            .navigationTitle("Template")
            .toolbar(content: {
                ToolbarItemGroup {
                    Button("Cancel") { dismiss() }
                    Button("Save") { _Concurrency.Task { await save() } }
                }
            })
        }
        .frame(minWidth: 640, minHeight: 560)
    }

    private func weekdayName(_ w: Int) -> String {
        let cal = Calendar.current
        return cal.weekdaySymbols[(w - 1 + 7) % 7]
    }

    private func nextSevenDates() -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var result: [Date] = []
        // Find first matching anchor weekday from today
        var first = start
        while cal.component(.weekday, from: first) != anchorWeekday {
            first = cal.date(byAdding: .day, value: 1, to: first) ?? first
        }
        // Add 7 upcoming instances spaced by intervalWeeks
        for i in 0..<7 {
            if let d = cal.date(byAdding: .weekOfYear, value: i * max(1, weeklyInterval), to: first) {
                result.append(cal.startOfDay(for: d))
            }
        }
        return result
    }

    private func save() async {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        let comps = Calendar.current.dateComponents([.hour,.minute], from: defaultTime)
        let tpl = Template(ownerId: userId, name: name, description: descriptionText, defaultDueTime: comps, priority: priority, status: "active", endAfterCount: Int(endAfterCount))
        do {
            let deps = Dependencies.shared
            let tplUC = try deps.resolve(type: TemplatesUseCases.self)
            try await tplUC.create(tpl)
            // Create one-to-one series starting next matching weekday
            let tz = TimeZone.current.identifier
            let cal = Calendar.current
            var start = cal.startOfDay(for: Date())
            while cal.component(.weekday, from: start) != anchorWeekday {
                start = cal.date(byAdding: .day, value: 1, to: start) ?? start
            }
            let series = Series(templateId: tpl.id, ownerId: userId, startsOn: start, endsOn: nil, timezoneIdentifier: tz, status: "active", lastGeneratedAt: nil, intervalWeeks: weeklyInterval, anchorWeekday: anchorWeekday)
            let serUC = try deps.resolve(type: SeriesUseCases.self)
            try await serUC.create(series)
            dismiss()
        } catch {
            Logger.shared.error("Failed to save template/series", category: .ui, error: error)
        }
    }
}

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
}


