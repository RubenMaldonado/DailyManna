//
//  LoadingView.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Signing you in...")
                .font(Typography.body)
                .foregroundColor(Colors.onSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Colors.background)
    }
}

#Preview {
    LoadingView()
}
