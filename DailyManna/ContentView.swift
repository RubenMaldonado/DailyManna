//
//  ContentView.swift
//  DailyManna
//
//  Created by Ruben Maldonado Tena on 8/24/25.
//  DEPRECATED: This view is no longer used in the modular architecture.
//  The app now uses TaskListView from the Features package.
//

import SwiftUI

/// DEPRECATED: This view is replaced by the modular architecture
/// See DailyMannaApp.swift which now uses TaskListView from Features package
struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            
            Text("Deprecated View")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("This view has been replaced by the modular architecture.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("The app now uses TaskListView from the Features package.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
