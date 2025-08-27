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
    
    init(bucket: TimeBucket, count: Int) {
        self.bucket = bucket
        self.count = count
    }
    
    var body: some View {
        HStack(spacing: Spacing.small) {
            Text(bucket.displayName)
                .style(Typography.title3)
                .foregroundColor(Colors.onSurface)
            CountBadge(count: count, tint: Colors.color(for: bucket))
            Spacer()
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
        .background(Colors.surfaceVariant)
        .cornerRadius(Spacing.xSmall)
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


