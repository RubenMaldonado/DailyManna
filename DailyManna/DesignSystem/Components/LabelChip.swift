//
//  LabelChip.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import SwiftUI

struct LabelChip: View {
    let label: Label
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    init(label: Label) {
        self.label = label
    }
    
    var body: some View {
        // Frosted chip: translucent background with label tint; fallback to solid tint
        let fg = Contrast.bestBWForeground(forHexBackground: label.color)
        let base = Text(label.name)
            .style(Typography.caption)
            .padding(.horizontal, Spacing.xxSmall)
            .padding(.vertical, 2)
            .frame(minHeight: 22)
            .cornerRadius(6)
            .accessibilityLabel("Label: \(label.name)")
        if reduceTransparency {
            base
                .background(label.uiColor.opacity(colorScheme == .dark ? 0.18 : 0.14))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Colors.outline.opacity(0.6), lineWidth: 0.5))
                .foregroundColor(fg)
        } else {
            base
                .background(Materials.glassChrome)
                .overlay(label.uiColor.opacity(0.18).clipShape(RoundedRectangle(cornerRadius: 6)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Materials.hairlineColor, lineWidth: 0.5))
                .foregroundColor(fg)
        }
    }
}

#Preview {
    LabelChip(label: Label(userId: UUID(), name: "Work", color: "#007AFF"))
        .padding()
}
