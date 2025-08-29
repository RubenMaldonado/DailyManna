//
//  DesignSystemPreviewCatalog.swift
//  DailyManna
//
//  Centralized previews for DS components across states and themes
//

import SwiftUI

struct DesignSystemPreviewCatalog: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Buttons").style(Typography.title2)
                HStack {
                    Button("Primary") { }.buttonStyle(PrimaryButtonStyle())
                    Button("Secondary") { }.buttonStyle(SecondaryButtonStyle())
                    Button("Delete") { }.buttonStyle(DestructiveButtonStyle())
                }
                .padding()
                .surfaceStyle(.content)
                .cornerRadius(12)

                Text("Chips").style(Typography.title2)
                HStack {
                    LabelChip(label: Label(userId: UUID(), name: "Work", color: "#007AFF"))
                    LabelChip(label: Label(userId: UUID(), name: "Urgent", color: "#FF3B30"))
                    LabelChip(label: Label(userId: UUID(), name: "Idea", color: "#34C759"))
                }

                Text("Task Card").style(Typography.title2)
                TaskCard(
                    task: Task(userId: UUID(), bucketKey: .thisWeek, title: "Long task title for layout validation", description: "Optional description that might wrap to multiple lines to test dynamic type and truncation.", dueAt: Date().addingTimeInterval(3600)),
                    labels: [Label(userId: UUID(), name: "Personal", color: "#FF9500")]
                )
            }
            .padding()
        }
        .surfaceStyle(.background)
    }
}

#Preview("Light") {
    DesignSystemPreviewCatalog()
        .preferredColorScheme(.light)
}

#Preview("Dark XXL") {
    DesignSystemPreviewCatalog()
        .preferredColorScheme(.dark)
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}


