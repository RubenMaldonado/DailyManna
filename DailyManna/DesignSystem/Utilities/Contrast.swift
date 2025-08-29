//
//  Contrast.swift
//  DailyManna
//
//  Contrast helpers that do not rely on UIKit/AppKit
//

import SwiftUI

enum Contrast {
    /// Computes relative luminance for an sRGB hex (e.g., "#RRGGBB" or "RRGGBB")
    static func relativeLuminance(hex: String) -> Double? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        } else {
            // ARGB; ignore alpha for luminance
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        }
        func toLinear(_ c: Double) -> Double {
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rL = toLinear(r)
        let gL = toLinear(g)
        let bL = toLinear(b)
        return 0.2126 * rL + 0.7152 * gL + 0.0722 * bL
    }
    
    /// Returns black or white for best legibility over a hex background color
    static func bestBWForeground(forHexBackground hex: String) -> Color {
        guard let y = relativeLuminance(hex: hex) else { return .primary }
        // Simple threshold; mid-gray ~ 0.5. Bias slightly towards white text.
        return y > 0.6 ? Color.black : Color.white
    }
}


