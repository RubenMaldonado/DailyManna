//
//  LabelChip.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import SwiftUI

struct LabelChip: View {
    let label: Label
    
    init(label: Label) {
        self.label = label
    }
    
    var body: some View {
        Text(label.name)
            .style(Typography.caption)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .background(label.uiColor.opacity(0.2))
            .cornerRadius(Spacing.xxSmall)
            .foregroundColor(label.uiColor)
    }
}

#Preview {
    LabelChip(label: Label(userId: UUID(), name: "Work", color: "#007AFF"))
        .padding()
}
