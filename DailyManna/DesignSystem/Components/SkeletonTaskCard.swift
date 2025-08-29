//
//  SkeletonTaskCard.swift
//  DailyManna
//
//  Non-animated skeleton placeholder for loading states
//

import SwiftUI

struct SkeletonTaskCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Colors.onSurface.opacity(0.12)).frame(height: 16)
            RoundedRectangle(cornerRadius: 4).fill(Colors.onSurface.opacity(0.08)).frame(height: 12)
            HStack {
                Capsule().fill(Colors.onSurface.opacity(0.12)).frame(width: 60, height: 18)
                Capsule().fill(Colors.onSurface.opacity(0.12)).frame(width: 40, height: 18)
            }
        }
        .cardPadding()
        .surfaceStyle(.content)
        .cornerRadius(Spacing.small)
        .redacted(reason: .placeholder)
    }
}


