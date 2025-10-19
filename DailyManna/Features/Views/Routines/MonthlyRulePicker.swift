import SwiftUI

struct MonthlyRulePicker: View {
    @Binding var kind: NewTemplateViewModel.MonthlyKind
    @Binding var monthDay: Int
    @Binding var ordinal: Int
    @Binding var weekday: Int
    
    private let ordinals = [1,2,3,4,-1]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Pattern", selection: $kind) {
                Text("On day").tag(NewTemplateViewModel.MonthlyKind.dayOfMonth)
                Text("On nth weekday").tag(NewTemplateViewModel.MonthlyKind.nthWeekday)
            }
            .pickerStyle(.segmented)
            if kind == .dayOfMonth {
                Stepper(value: $monthDay, in: 1...31) { Text("Day \(monthDay)") }
            } else {
                HStack {
                    Picker("Ordinal", selection: $ordinal) {
                        ForEach(ordinals, id: \.self) { v in Text(ordinalName(v)).tag(v) }
                    }
                    Picker("Weekday", selection: $weekday) {
                        ForEach(1...7, id: \.self) { w in Text(NewTemplateViewModel.weekdayDisplayName(w)).tag(w) }
                    }
                }
            }
        }
    }
}

func ordinalName(_ n: Int) -> String {
    switch n {
    case 1: return "1st"
    case 2: return "2nd"
    case 3: return "3rd"
    case 4: return "4th"
    case -1: return "Last"
    default: return "\(n)th"
    }
}


