//
//  Colors.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import SwiftUI

/// Color tokens for the Daily Manna design system
/// SwiftUI-only implementation using semantic colors and custom design tokens
struct Colors {
    
    // MARK: - Primary Colors
    static let primary = Color.blue
    static let primaryVariant = Color.blue.opacity(0.8)
    static let secondary = Color.orange
    static let secondaryVariant = Color.orange.opacity(0.8)
    
    // MARK: - Semantic Colors (adaptive via asset catalog)
    static let background = Color("Background")
    static let surface = Color("Surface")
    static let surfaceVariant = Color("SurfaceVariant")
    
    // MARK: - Content Colors
    static let onPrimary = Color.white
    static let onSecondary = Color.white
    static let onBackground = Color("OnSurface")
    static let onSurface = Color("OnSurface")
    static let onSurfaceVariant = Color.gray
    
    // MARK: - Status Colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    
    // MARK: - Time Bucket Colors
    static let thisWeek = Color.blue
    static let weekend = Color.purple
    static let nextWeek = Color.green
    static let nextMonth = Color.orange
    static let routines = Color.indigo
    
    // MARK: - Neutral Scale (Custom Design Tokens)
    static let neutral100 = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let neutral200 = Color(red: 0.90, green: 0.90, blue: 0.90)
    static let neutral300 = Color(red: 0.83, green: 0.83, blue: 0.83)
    static let neutral400 = Color(red: 0.74, green: 0.74, blue: 0.74)
    static let neutral500 = Color(red: 0.62, green: 0.62, blue: 0.62)
    static let neutral600 = Color(red: 0.45, green: 0.45, blue: 0.45)
    static let neutral700 = Color(red: 0.32, green: 0.32, blue: 0.32)
    static let neutral800 = Color(red: 0.20, green: 0.20, blue: 0.20)
    static let neutral900 = Color(red: 0.11, green: 0.11, blue: 0.11)
    
    // MARK: - Layout Colors
    static let separator = neutral300
    static let opaqueSeparator = neutral400
    static let outline = neutral300
    
    // MARK: - Helper Methods
    
    /// Returns a color for a given time bucket
    static func color(for bucket: TimeBucket) -> Color {
        switch bucket {
        case .thisWeek: return thisWeek
        case .weekend: return weekend
        case .nextWeek: return nextWeek
        case .nextMonth: return nextMonth
        case .routines: return routines
        }
    }

    // MARK: - Label Color Palette (curated)
    /// Curated, accessible label color hex values
    static let labelPalette: [String] = [
        "#EF4444", // red-500
        "#F97316", // orange-500
        "#EAB308", // yellow-500
        "#22C55E", // green-500
        "#06B6D4", // cyan-500
        "#3B82F6", // blue-500
        "#8B5CF6", // violet-500
        "#EC4899", // pink-500
        "#10B981", // emerald-500
        "#F59E0B", // amber-500
        "#0EA5E9", // sky-500
        "#A855F7"  // purple-500
    ]
}
