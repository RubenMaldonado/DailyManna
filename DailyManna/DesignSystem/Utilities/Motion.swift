//
//  Motion.swift
//  DailyManna
//
//  Motion helpers to respect Reduce Motion and cap durations per DS
//

import SwiftUI

/// Motion helpers that callers can use with the SwiftUI `accessibilityReduceMotion` environment.
enum Motion {
    static func microAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }
    static func pageAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.35)
    }
}

extension View {
    /// Apply an animation only when motion is allowed
    func animated(if reduceMotion: Bool, animation: Animation?) -> some View {
        self.animation(animation, value: reduceMotion)
    }
}


