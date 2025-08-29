//
//  Haptics.swift
//  DailyManna
//
//  Lightweight cross-platform haptics helper
//

import SwiftUI

enum Haptics {
    static func success() {
        #if os(iOS)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        #endif
    }
    static func lightTap() {
        #if os(iOS)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
    }
}


