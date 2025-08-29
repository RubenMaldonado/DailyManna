//
//  Buttons.swift
//  DailyManna
//
//  Created for Epic 1.2
//

import SwiftUI

enum ButtonSize {
    case small
    case regular
    
    var horizontalPadding: CGFloat { self == .small ? Spacing.medium : Spacing.large }
    var verticalPadding: CGFloat { self == .small ? Spacing.xxSmall : Spacing.xSmall }
    var minHeight: CGFloat { self == .small ? 32 : 44 }
}

struct PrimaryButtonStyle: ButtonStyle {
    var size: ButtonSize = .regular
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(minHeight: size.minHeight)
            .background(Colors.primary.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.5))
            .foregroundColor(Colors.onPrimary.opacity(isEnabled ? 1.0 : 0.7))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var size: ButtonSize = .regular
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(minHeight: size.minHeight)
            .background(Colors.surfaceVariant.opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.6))
            .foregroundColor(Colors.onSurface.opacity(isEnabled ? 1.0 : 0.6))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Colors.outline, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    var size: ButtonSize = .regular
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(minHeight: size.minHeight)
            .background(Colors.error.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.5))
            .foregroundColor(Colors.onPrimary.opacity(isEnabled ? 1.0 : 0.7))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}


