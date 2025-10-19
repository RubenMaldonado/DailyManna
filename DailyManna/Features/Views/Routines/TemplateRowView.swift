import SwiftUI

struct TemplateRowView: View {
    let name: String
    let status: String
    let nextDate: Date?
    let remaining: Int?
    let isActive: Bool
    let onToggle: () -> Void
    let onSkipNext: () -> Void
    let onEdit: () -> Void
    
    #if os(macOS)
    @State private var hovering: Bool = false
    #endif
    var body: some View {
        HStack(alignment: .center, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(name)
                        .style(Typography.body)
                        .foregroundColor(Colors.onSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let remaining { badge(text: "Remaining: \(remaining)") }
                }
                HStack(spacing: 12) {
                    if isActive == false { badge(text: "Paused") }
                    if let d = nextDate {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                            Text(DateFormatter.dmShortDate.string(from: d))
                        }
                        .style(Typography.caption)
                        .foregroundColor(Colors.onSurfaceVariant)
                    }
                }
            }
            Spacer(minLength: 12)
            // Compact, icon-only actions (macOS only)
            #if os(macOS)
            HStack(spacing: 4) {
                Button(action: onToggle) { Image(systemName: isActive ? "pause.fill" : "play.fill") }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel(Text(isActive ? "Pause" : "Resume"))
                HStack(spacing: 4) {
                    Button(action: onSkipNext) { Image(systemName: "forward.end.fill") }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel(Text("Skip Next"))
                    Button(action: onEdit) { Image(systemName: "square.and.pencil") }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel(Text("Edit"))
                }
                .opacity(hovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: hovering)
            }
            #endif
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { onToggle() } label: { SwiftUI.Label(isActive ? "Pause" : "Resume", systemImage: isActive ? "pause.fill" : "play.fill") }
            Button { onEdit() } label: { SwiftUI.Label("Edit", systemImage: "pencil") }
            Button { onSkipNext() } label: { SwiftUI.Label("Skip Next", systemImage: "forward.end.fill") }
        }
        .contextMenu {
            Button(isActive ? "Pause" : "Resume") { onToggle() }
            Button("Skip Next") { onSkipNext() }
            Button("Edit") { onEdit() }
        }
        #endif
    }
    
    private func badge(text: String) -> some View {
        Text(text)
            .style(Typography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Colors.surface.opacity(0.10))
            .cornerRadius(6)
            .foregroundColor(Colors.onSurfaceVariant)
    }
}

private extension DateFormatter {
    static let dmShortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
}


