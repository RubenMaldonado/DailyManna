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
    
    init(label: Label) {
        self.label = label
    }
    
    var body: some View {
        // Make chips subtler in list context to reduce visual noise
        let bgAlpha: Double = colorScheme == .dark ? 0.18 : 0.12
        let fg = Contrast.bestBWForeground(forHexBackground: label.color)
        Text(label.name)
            .style(Typography.caption)
            .padding(.horizontal, Spacing.xxSmall)
            .padding(.vertical, 2)
            .frame(minHeight: 22)
            .background(label.uiColor.opacity(bgAlpha))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Colors.outline.opacity(0.6), lineWidth: 0.5))
            .cornerRadius(6)
            .foregroundColor(fg)
            .accessibilityLabel("Label: \(label.name)")
    }
}

#Preview {
    LabelChip(label: Label(userId: UUID(), name: "Work", color: "#007AFF"))
        .padding()
}
