//
//  SurfaceStyle.swift
//  DailyManna
//
//  Lightweight surface/material abstraction aligned with the DS
//

import SwiftUI

struct SurfaceStyle: ViewModifier {
    enum Kind { case background, content, chrome, overlay, solidFallback }
    var kind: Kind
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    func body(content: Content) -> some View {
        switch kind {
        case .background:
            content.background(Colors.background)
        case .content:
            // Opaque content surface for readable text
            content.background(Colors.surface)
        case .chrome:
            // Translucent chrome candidate; fallback to solid variant when transparency is reduced
            if reduceTransparency {
                content.background(Colors.surfaceVariant)
            } else {
                #if os(iOS) || os(macOS)
                content.background(.ultraThinMaterial)
                #else
                content.background(Colors.surfaceVariant)
                #endif
            }
        case .overlay:
            // Dimmed overlay; adapt dim color to scheme
            let dim = colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
            if reduceTransparency {
                content.background(Colors.surface).overlay(dim)
            } else {
                #if os(iOS) || os(macOS)
                content.background(.regularMaterial).overlay(dim)
                #else
                content.background(Colors.surface).overlay(dim)
                #endif
            }
        case .solidFallback:
            content.background(Colors.background)
        }
    }
}

extension View {
    func surfaceStyle(_ kind: SurfaceStyle.Kind) -> some View { modifier(SurfaceStyle(kind: kind)) }
}


