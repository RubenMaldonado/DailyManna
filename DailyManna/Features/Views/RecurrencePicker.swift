import SwiftUI

struct RecurrencePicker: View {
    @Binding var rule: RecurrenceRule?
    @State private var preset: String = "None"
    @State private var time: Date = Date()
    @State private var weekdays: Set<String> = []
    @State private var monthDay: Int = 1
    @State private var interval: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Repeat", selection: $preset) {
                Text("None").tag("None")
                Text("Daily").tag("Daily")
                Text("Weekdays").tag("Weekdays")
                Text("Weekly…").tag("Weekly")
                Text("Monthly (day)…").tag("MonthlyDay")
            }
            .onChange(of: preset) { _, _ in rebuildRule() }

            if preset == "Weekly" {
                WeekdayGrid(selected: $weekdays)
                    .onChange(of: weekdays) { _, _ in rebuildRule() }
            }
            if preset == "MonthlyDay" {
                Stepper(value: $monthDay, in: 1...28) { Text("Day of month: \(monthDay)") }
                    .onChange(of: monthDay) { _, _ in rebuildRule() }
            }
            HStack {
                Stepper(value: $interval, in: 1...12) { Text("Every \(interval)") }
                    .onChange(of: interval) { _, _ in rebuildRule() }
                DatePicker("at", selection: $time, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .onChange(of: time) { _, _ in rebuildRule() }
            }
        }
        .onAppear { loadFromRule() }
        // If the bound rule changes from outside (e.g., loaded async), reflect it
        .onChange(of: rule) { _, _ in loadFromRule() }
    }

    private func loadFromRule() {
        guard let rule else { preset = "None"; return }
        interval = max(1, rule.interval)
        if let t = rule.time, let d = timeFromString(t) { time = d }
        switch rule.freq {
        case .daily:
            preset = "Daily"
        case .weekly:
            preset = "Weekly"
            weekdays = Set(rule.byWeekday ?? [])
        case .monthly:
            preset = "MonthlyDay"
            monthDay = (rule.byMonthDay?.first).map { max(1, min(28, $0)) } ?? 1
        case .yearly:
            preset = "None" // v1: omit
        }
    }

    private func rebuildRule() {
        switch preset {
        case "None":
            rule = nil
        case "Daily":
            rule = RecurrenceRule(freq: .daily, interval: interval, time: timeString(time))
        case "Weekdays":
            rule = RecurrenceRule(freq: .weekly, interval: 1, byWeekday: ["MO","TU","WE","TH","FR"], time: timeString(time))
        case "Weekly":
            let days = weekdays.isEmpty ? [weekdayFrom(date: Date())] : Array(weekdays)
            rule = RecurrenceRule(freq: .weekly, interval: interval, byWeekday: days.sorted(), time: timeString(time))
        case "MonthlyDay":
            rule = RecurrenceRule(freq: .monthly, interval: interval, byMonthDay: [monthDay], time: timeString(time))
        default:
            rule = nil
        }
    }

    private func timeString(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour,.minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }
    private func timeFromString(_ s: String) -> Date? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var comps = Calendar.current.dateComponents([.year,.month,.day], from: Date())
        comps.hour = h; comps.minute = m
        return Calendar.current.date(from: comps)
    }
    private func weekdayFrom(date: Date) -> String {
        let wd = Calendar.current.component(.weekday, from: date)
        let map = [1:"SU",2:"MO",3:"TU",4:"WE",5:"TH",6:"FR",7:"SA"]
        return map[wd] ?? "MO"
    }
}

private struct WeekdayGrid: View {
    @Binding var selected: Set<String>
    private let days: [(String,String)] = [("SU","S"),("MO","M"),("TU","T"),("WE","W"),("TH","T"),("FR","F"),("SA","S")]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.0) { (code, short) in
                Button(action: { toggle(code) }) {
                    Text(short)
                        .frame(width: 28, height: 28)
                        .background(selected.contains(code) ? Colors.primary.opacity(0.15) : Colors.surface)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    private func toggle(_ code: String) { if selected.contains(code) { selected.remove(code) } else { selected.insert(code) } }
}


