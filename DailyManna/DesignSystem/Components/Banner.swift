//
//  Pill.swift
//  DailyManna
//
//  Small capsule pill for inline filter indicators.
//

import SwiftUI

struct Pill: View {
    let text: String
    var onClear: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 6) {
            Text(text).style(Typography.caption).foregroundColor(Colors.onSurface)
            if let onClear = onClear {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundColor(Colors.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Colors.surface)
        .cornerRadius(999)
    }
}

//
//  Banner.swift
//  DailyManna
//
//  Inline banner for error/offline/info states
//

import SwiftUI

struct Banner: View {
    enum Kind { case info, warning, error }
    let kind: Kind
    let message: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: iconName)
            Text(message).style(Typography.caption)
            Spacer(minLength: 0)
        }
        .padding(12)
        .foregroundColor(Colors.onSurface)
        .surfaceStyle(.content)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(outlineColor, lineWidth: 1))
    }
    
    private var iconName: String {
        switch kind { case .info: return "info.circle"; case .warning: return "exclamationmark.triangle"; case .error: return "xmark.octagon" }
    }
    private var outlineColor: Color {
        switch kind { case .info: return Colors.info; case .warning: return Colors.warning; case .error: return Colors.error }
    }
}


