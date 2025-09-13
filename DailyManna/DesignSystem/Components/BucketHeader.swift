//
//  BucketHeader.swift
//  DailyManna
//
//  Created for Epic 1.1
//

import SwiftUI

struct BucketHeader: View {
    let bucket: TimeBucket
    let count: Int
    let onAdd: (() -> Void)?
    
    init(bucket: TimeBucket, count: Int, onAdd: (() -> Void)? = nil) {
        self.bucket = bucket
        self.count = count
        self.onAdd = onAdd
    }
    
    var body: some View {
        HStack(spacing: Spacing.small) {
            Text(bucket.displayName)
                .style(Typography.title3)
                .foregroundColor(Colors.onSurface)
            CountBadge(count: count, tint: Colors.color(for: bucket))
            Spacer()
            if let onAdd {
                Button(action: onAdd) { Image(systemName: "plus") }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                    .accessibilityLabel("Add task to \(bucket.displayName)")
            }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
        .surfaceStyle(.content)
        .cornerRadius(Spacing.xSmall)
        // Add a subtle leading accent to strengthen section hierarchy
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Colors.color(for: bucket))
                .opacity(0.25)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        BucketHeader(bucket: .thisWeek, count: 5)
        BucketHeader(bucket: .weekend, count: 1)
        BucketHeader(bucket: .nextWeek, count: 0)
    }
    .padding()
}


