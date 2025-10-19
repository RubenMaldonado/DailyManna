import SwiftUI

/// A ghost, icon-only button with platform-appropriate hit target and subtle hover/press feedback.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        let baseSize: CGFloat = 28
        #else
        let baseSize: CGFloat = 44
        #endif
        return configuration.label
            .foregroundColor(Colors.onSurfaceVariant)
            .frame(width: baseSize, height: baseSize)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        #if os(macOS)
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Colors.onSurface.opacity(isPressed ? 0.10 : 0.06))
            .opacity(0) // default hidden; revealed on hover via container if desired
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Colors.onSurface.opacity(isPressed ? 0.12 : 0.08))
                    .opacity(isPressed ? 1 : 0)
            )
        #else
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Colors.onSurface.opacity(isPressed ? 0.10 : 0.06))
        #endif
    }
}



