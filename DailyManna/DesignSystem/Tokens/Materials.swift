//
//  Materials.swift
//  DailyManna
//
//  Tokenized Liquid Glass mappings and constants
//

import SwiftUI
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Liquid Glass material tokens and helpers.
/// These map logical DS materials to platform styles, with safe fallbacks.
struct Materials {
    // MARK: - Glass ShapeStyles (platform-conditional)
    static var glassChrome: AnyShapeStyle {
        #if os(iOS) || os(macOS)
        return AnyShapeStyle(.ultraThinMaterial)
        #else
        return AnyShapeStyle(Colors.surfaceVariant)
        #endif
    }

    static var glassOverlay: AnyShapeStyle {
        #if os(iOS) || os(macOS)
        return AnyShapeStyle(.regularMaterial)
        #else
        return AnyShapeStyle(Colors.surface)
        #endif
    }

    // MARK: - Tints
    static var glassTintNeutral: Color { Color.white.opacity(0.06) }
    static var glassTintPrimary: Color { Colors.primary.opacity(0.08) }
    static var glassTintDanger: Color { Colors.error.opacity(0.08) }

    // MARK: - Hairline stroke and dim
    static var hairlineColor: Color { Colors.outline.opacity(0.65) }

    static func dim(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    // One physical pixel convenience
    static var onePixel: CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return 1.0 / UIScreen.main.scale
        #elseif os(macOS)
        return 1.0 / (NSScreen.main?.backingScaleFactor ?? 2.0)
        #else
        return 1.0
        #endif
    }
}


