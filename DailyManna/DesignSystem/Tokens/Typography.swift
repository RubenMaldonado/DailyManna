//
//  Typography.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import SwiftUI

/// Typography tokens for the Daily Manna design system
struct Typography {
    // MARK: - Font Styles
    static let largeTitle = Font.largeTitle
    static let title1 = Font.title
    static let title2 = Font.title2
    static let title3 = Font.title3
    static let headline = Font.headline
    static let subheadline = Font.subheadline
    static let body = Font.body
    static let callout = Font.callout
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let caption2 = Font.caption2
    
    // MARK: - Custom Font Modifiers
    static func customBody(weight: Font.Weight = .regular) -> Font {
        .system(.body, design: .default, weight: weight)
    }
    
    static func customHeadline(weight: Font.Weight = .semibold) -> Font {
        .system(.headline, design: .default, weight: weight)
    }
}

extension View {
    func style(_ font: Font) -> some View {
        self.font(font)
    }
}
