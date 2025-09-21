//
//  CountBadge.swift
//  DailyManna
//
//  Created for Epic 1.1
//

import SwiftUI

struct CountBadge: View {
    let count: Int
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    init(count: Int, tint: Color = Colors.primary) {
        self.count = count
        self.tint = tint
    }
    
    var body: some View {
        let label = Text("\(count)")
            .font(.system(.footnote, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .clipShape(Capsule())
            .accessibilityLabel("Count \(count)")
        if reduceTransparency {
            label
                .foregroundColor(Colors.onPrimary)
                .background(tint)
        } else {
            label
                .foregroundColor(Colors.onSurface)
                .background(Materials.glassChrome)
                .overlay(tint.opacity(0.22).clipShape(Capsule()))
                .overlay(Capsule().stroke(Materials.hairlineColor, lineWidth: 0.5))
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        CountBadge(count: 0)
        CountBadge(count: 3, tint: Colors.secondary)
        CountBadge(count: 12)
    }
    .padding()
}


