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
    
    // MARK: - Semantic Colors (SwiftUI-native)
    static let background = Color.white
    static let surface = Color.gray.opacity(0.05)
    static let surfaceVariant = Color.gray.opacity(0.1)
    
    // MARK: - Content Colors
    static let onPrimary = Color.white
    static let onSecondary = Color.white
    static let onBackground = Color.black
    static let onSurface = Color.black
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
}
