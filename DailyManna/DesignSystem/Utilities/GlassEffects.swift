//
//  GlassEffects.swift
//  DailyManna
//
//  Subtle effects for Liquid Glass components
//

import SwiftUI

enum GlassEffects {
    /// Hairline bottom divider for chrome surfaces.
    static func hairlineDivider() -> some View {
        Rectangle()
            .fill(Materials.hairlineColor)
            .frame(height: Materials.onePixel)
    }

    /// A micro specular highlight overlay for press/hover states.
    /// Use with masking to component bounds.
    static func specularOverlay(opacity: Double = 0.16) -> some View {
        LinearGradient(
            gradient: Gradient(colors: [Color.white.opacity(opacity), Color.white.opacity(0.0)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
    }
}


