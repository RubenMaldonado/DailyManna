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
    
    init(count: Int, tint: Color = Colors.primary) {
        self.count = count
        self.tint = tint
    }
    
    var body: some View {
        Text("\(count)")
            .font(.system(.footnote, design: .monospaced))
            .foregroundColor(Colors.onPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint)
            .clipShape(Capsule())
            .accessibilityLabel("Count \(count)")
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


