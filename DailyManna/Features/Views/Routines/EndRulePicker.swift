import SwiftUI

struct EndRulePicker: View {
    @Binding var endRule: NewTemplateViewModel.EndRule
    
    @State private var occurrencesText: String = ""
    @State private var endDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Ends", selection: Binding(get: {
                switch endRule { case .never: return 0; case .onDate: return 1; case .afterCount: return 2 }
            }, set: { newValue in
                switch newValue {
                case 0: endRule = .never
                case 1: endRule = .onDate(endDate)
                case 2:
                    if let n = Int(occurrencesText), n > 0 { endRule = .afterCount(min(n, 999)) } else { endRule = .afterCount(10) }
                default: break
                }
            })) {
                Text("Never").tag(0)
                Text("On date").tag(1)
                Text("After N").tag(2)
            }
            .pickerStyle(.segmented)
            
            switch endRule {
            case .onDate:
                DatePicker("End date", selection: Binding(get: {
                    if case .onDate(let d) = endRule { return d } else { return endDate }
                }, set: { new in
                    endDate = new
                    endRule = .onDate(new)
                }), displayedComponents: [.date])
            case .afterCount:
                HStack {
                    Text("Occurrences")
                    TextField("10", text: Binding(get: {
                        if case .afterCount(let n) = endRule { return String(n) } else { return occurrencesText }
                    }, set: { new in
                        occurrencesText = new
                        if let n = Int(new), n > 0 { endRule = .afterCount(min(n, 999)) }
                    }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
            default:
                EmptyView()
            }
        }
    }
}


