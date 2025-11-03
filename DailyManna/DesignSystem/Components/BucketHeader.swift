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
    let onCycleWidthMode: (() -> Void)?
    var onTogglePrimary: (() -> Void)? = nil
    
    @State private var isHovering: Bool = false
    
    init(bucket: TimeBucket, count: Int, onAdd: (() -> Void)? = nil, onCycleWidthMode: (() -> Void)? = nil, onTogglePrimary: (() -> Void)? = nil) {
        self.bucket = bucket
        self.count = count
        self.onAdd = onAdd
        self.onCycleWidthMode = onCycleWidthMode
        self.onTogglePrimary = onTogglePrimary
    }
    
    var body: some View {
        HStack(spacing: Spacing.small) {
            CountBadge(count: count, tint: Colors.color(for: bucket))
            Text(bucket.displayName)
                .style(Typography.title3)
                .foregroundColor(Colors.onSurface)
            Spacer()
            #if os(macOS)
            if let onCycleWidthMode {
                Button(action: onCycleWidthMode) {
                    Image(systemName: "rectangle.rightthird.inset.filled")
                        .foregroundColor(Colors.onSurface.opacity(isHovering ? 0.85 : 0.0))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel("Collapse column")
            }
            #endif
            if let onAdd {
                Button(action: onAdd) { Image(systemName: "plus") }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                    .accessibilityLabel("Add task to \(bucket.displayName)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTogglePrimary?() }
        .onHover { isHovering = $0 }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
        .surfaceStyle(.content)
        .cornerRadius(Spacing.xSmall)
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


