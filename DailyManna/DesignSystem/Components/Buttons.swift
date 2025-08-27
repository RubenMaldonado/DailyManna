//
//  Buttons.swift
//  DailyManna
//
//  Created for Epic 1.2
//

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.xSmall)
            .background(Colors.primary.opacity(configuration.isPressed ? 0.8 : 1.0))
            .foregroundColor(Colors.onPrimary)
            .clipShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.xSmall)
            .background(Colors.surfaceVariant)
            .foregroundColor(Colors.onSurface)
            .clipShape(Capsule())
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.xSmall)
            .background(Colors.error.opacity(configuration.isPressed ? 0.85 : 1.0))
            .foregroundColor(Colors.onPrimary)
            .clipShape(Capsule())
    }
}


