//
//  Spacing.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import SwiftUI

/// Spacing tokens for the Daily Manna design system
struct Spacing {
    static let xxSmall: CGFloat = 4
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let xxLarge: CGFloat = 48
    
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let buttonPadding: CGFloat = 12
}

extension View {
    func screenPadding() -> some View {
        self.padding(Spacing.screenPadding)
    }
    
    func cardPadding() -> some View {
        self.padding(Spacing.cardPadding)
    }
}
