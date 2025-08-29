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
        let bgAlpha: Double = colorScheme == .dark ? 0.28 : 0.18
        let fg = Contrast.bestBWForeground(forHexBackground: label.color)
        Text(label.name)
            .style(Typography.caption)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .frame(minHeight: 28)
            .background(label.uiColor.opacity(bgAlpha))
            .overlay(RoundedRectangle(cornerRadius: Spacing.xxSmall).stroke(Colors.outline, lineWidth: 0.5))
            .cornerRadius(Spacing.xxSmall)
            .foregroundColor(fg)
            .accessibilityLabel("Label: \(label.name)")
    }
}

#Preview {
    LabelChip(label: Label(userId: UUID(), name: "Work", color: "#007AFF"))
        .padding()
}
