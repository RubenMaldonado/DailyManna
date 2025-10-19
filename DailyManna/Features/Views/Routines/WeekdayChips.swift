import SwiftUI

struct WeekdayChips: View {
    @Binding var selection: Set<Int> // 1..7
    
    private let weekdays = Array(1...7)
    
    var body: some View {
        FlowLayout(spacing: 8, runSpacing: 8) {
            ForEach(weekdays, id: \.self) { wd in
                let selected = selection.contains(wd)
                Button(action: { toggle(wd) }) {
                    Text(shortName(wd))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(fullName(wd))"))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
    
    private func toggle(_ wd: Int) { if selection.contains(wd) { selection.remove(wd) } else { selection.insert(wd) } }
    
    private func shortName(_ wd: Int) -> String {
        let cal = Calendar.current
        return String(cal.shortWeekdaySymbols[(wd - 1 + 7) % 7])
    }
    private func fullName(_ wd: Int) -> String { NewTemplateViewModel.weekdayDisplayName(wd) }
}

// Fixed grid version for compact, single-row layout when space allows
struct WeekdayGrid: View {
    @Binding var selection: Set<Int>
    private let order: [Int] = [2,3,4,5,6,7,1] // Mon..Sun for left-to-right familiarity
    var body: some View {
        HStack(spacing: 8) {
            ForEach(order, id: \.self) { wd in
                let isOn = selection.contains(wd)
                Button(action: { toggle(wd) }) {
                    Text(shortName(wd))
                        .frame(width: 36)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                        .foregroundStyle(isOn ? Color.accentColor : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(fullName(wd)))
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }
    private func toggle(_ wd: Int) { if selection.contains(wd) { selection.remove(wd) } else { selection.insert(wd) } }
    private func shortName(_ wd: Int) -> String {
        let cal = Calendar.current
        let idx = (wd - 1 + 7) % 7
        return String(cal.shortWeekdaySymbols[idx])
    }
    private func fullName(_ wd: Int) -> String { NewTemplateViewModel.weekdayDisplayName(wd) }
}

// Minimal flow layout to wrap chips
struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let runSpacing: CGFloat
    let content: Content
    
    init(spacing: CGFloat = 8, runSpacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.runSpacing = runSpacing
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
        .frame(minHeight: 0)
    }
    
    private func generateContent(in g: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        return ZStack(alignment: .topLeading) {
            content
                .alignmentGuide(.leading, computeValue: { d in
                    if width + d.width > g.size.width {
                        width = 0
                        height -= d.height + runSpacing
                    }
                    let result = width
                    width += d.width + spacing
                    return result
                })
                .alignmentGuide(.top, computeValue: { d in
                    let result = height
                    return result
                })
        }
    }
}


