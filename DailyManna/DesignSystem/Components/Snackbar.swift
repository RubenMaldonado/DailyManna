import SwiftUI

struct Snackbar: View {
    let message: String
    let actionTitle: String?
    let duration: TimeInterval
    let action: (() -> Void)?
    @Binding var isPresented: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var timerFiredAt: Date = Date()

    init(message: String, actionTitle: String? = nil, duration: TimeInterval = 4.0, isPresented: Binding<Bool>, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.duration = duration
        self._isPresented = isPresented
        self.action = action
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .style(Typography.body)
                .foregroundColor(Colors.onSurface)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if let title = actionTitle, let action = action {
                Button(title) { action(); isPresented = false }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Colors.surface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 4)
        .padding(.horizontal, 16)
        .onAppear { scheduleDismiss() }
        .accessibilityAddTraits(.isModal)
    }

    private func scheduleDismiss() {
        let effective = voiceOverEnabled ? max(duration, 6.0) : duration
        timerFiredAt = Date().addingTimeInterval(effective)
        DispatchQueue.main.asyncAfter(deadline: .now() + effective) {
            if Date() >= timerFiredAt { isPresented = false }
        }
    }
}


