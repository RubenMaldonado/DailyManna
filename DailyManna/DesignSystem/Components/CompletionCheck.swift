//
//  CompletionCheck.swift
//  DailyManna
//
//  Reusable completion control with symbol animation, haptics, and optional sound.
//

import SwiftUI

#if os(iOS)
import AudioToolbox
#endif

struct CompletionCheck: View {
    let isCompleted: Bool
    let action: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("completionHapticEnabled") private var hapticEnabled: Bool = true
    @AppStorage("completionSoundEnabled") private var soundEnabled: Bool = false
    
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Button {
            // Immediate light tap for touch acknowledgment on iOS < 17
            #if os(iOS)
            Haptics.lightTap()
            #endif
            // Subtle scale micro-interaction
            if reduceMotion == false {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.75)) { scale = 1.1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { scale = 1.0 }
                }
            }
            action()
        } label: {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isCompleted ? Colors.primary : Colors.onSurface.opacity(0.6))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .modifier(SymbolEffectsModifier(isCompleted: isCompleted, reduceMotion: reduceMotion))
                .scaleEffect(reduceMotion ? 1.0 : scale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompleted ? "Mark incomplete" : "Mark complete")
        .accessibilityValue(isCompleted ? "Completed" : "Not completed")
        // iOS 17+: haptic success on state change
        .modifier(SensoryFeedbackModifier(triggerOn: isCompleted, enabled: hapticEnabled))
        // Optional: play a subtle sound when transitioning to completed (availability-aware)
        .modifier(CompletionSoundModifier(value: isCompleted, enabled: soundEnabled))
    }
}

private struct SymbolEffectsModifier: ViewModifier {
    let isCompleted: Bool
    let reduceMotion: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .contentTransition(.symbolEffect(.replace))
        } else {
            if #available(iOS 17.0, macOS 14.0, *) {
                content
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isCompleted)
            } else {
                content
                    .contentTransition(.identity)
            }
        }
    }
}

private struct CompletionSoundModifier: ViewModifier {
    let value: Bool
    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, macOS 14.0, *) {
            content.onChange(of: value) { oldValue, newValue in
                if newValue && enabled { AudioServicesPlaySystemSound(1106) }
            }
        } else {
            content.onChange(of: value) { newValue in
                if newValue && enabled { AudioServicesPlaySystemSound(1106) }
            }
        }
        #else
        content
        #endif
    }
}

private struct SensoryFeedbackModifier: ViewModifier {
    let triggerOn: Bool
    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            content
                .sensoryFeedback(.success, trigger: enabled && triggerOn)
        } else {
            content
        }
        #else
        content
        #endif
    }
}


