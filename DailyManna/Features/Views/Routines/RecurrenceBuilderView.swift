import SwiftUI

struct RecurrenceBuilderView: View {
    @ObservedObject var viewModel: NewTemplateViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Frequency", selection: $viewModel.frequency) {
                Text("Daily").tag(NewTemplateViewModel.Frequency.daily)
                Text("Weekly").tag(NewTemplateViewModel.Frequency.weekly)
                Text("Monthly").tag(NewTemplateViewModel.Frequency.monthly)
                Text("Yearly").tag(NewTemplateViewModel.Frequency.yearly)
            }
            .pickerStyle(.segmented)
            
            Stepper(value: $viewModel.interval, in: 1...99) { Text("Every \(viewModel.interval) \(unitName())") }
            
            switch viewModel.frequency {
            case .daily:
                EmptyView()
            case .weekly:
                WeekdayGrid(selection: $viewModel.selectedWeekdays)
            case .monthly:
                MonthlyRulePicker(kind: $viewModel.monthlyKind, monthDay: $viewModel.monthDay, ordinal: $viewModel.monthlyOrdinal, weekday: $viewModel.monthlyWeekday)
            case .yearly:
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Month", selection: $viewModel.yearlyMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text(DateFormatter().monthSymbols[(m - 1 + 12) % 12]).tag(m)
                        }
                    }
                    MonthlyRulePicker(kind: $viewModel.yearlyKind, monthDay: $viewModel.yearlyDay, ordinal: $viewModel.yearlyOrdinal, weekday: $viewModel.yearlyWeekday)
                }
            }
            
            DatePicker("Starts", selection: $viewModel.startsOn, displayedComponents: [.date])
            
            EndRulePicker(endRule: $viewModel.endRule)
            
            if let error = validationError {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func unitName() -> String {
        switch viewModel.frequency {
        case .daily: return viewModel.interval == 1 ? "day" : "days"
        case .weekly: return viewModel.interval == 1 ? "week" : "weeks"
        case .monthly: return viewModel.interval == 1 ? "month" : "months"
        case .yearly: return viewModel.interval == 1 ? "year" : "years"
        }
    }
    
    private var validationError: String? {
        // Re-evaluate without side-effects
        switch viewModel.frequency {
        case .weekly:
            return viewModel.selectedWeekdays.isEmpty ? "Choose at least one weekday" : nil
        case .monthly:
            if viewModel.monthlyKind == .dayOfMonth && (viewModel.monthDay < 1 || viewModel.monthDay > 31) { return "Day must be 1–31" }
            return nil
        case .yearly:
            if viewModel.yearlyKind == .dayOfMonth && (viewModel.yearlyDay < 1 || viewModel.yearlyDay > 31) { return "Day must be 1–31" }
            return nil
        default:
            return nil
        }
    }
}


