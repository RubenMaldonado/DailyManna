//
//  KeyboardShortcutsView.swift
//  DailyManna
//

import SwiftUI

struct KeyboardShortcutsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    ShortcutRow(keys: "⌘N", action: "New task")
                    ShortcutRow(keys: "⌘⌥F", action: "Open filters")
                }
                #if os(macOS)
                Section("This Week scheduling (List)") {
                    ShortcutRow(keys: "⌘→", action: "Schedule to next weekday")
                    ShortcutRow(keys: "⌘←", action: "Schedule to previous weekday")
                }
                Section("Working Log (macOS)") {
                    ShortcutRow(keys: "⌘L", action: "Toggle Working Log panel")
                    ShortcutRow(keys: "⌘E", action: "Export Working Log (Markdown)")
                }
                Section("Task actions (macOS)") {
                    ShortcutRow(keys: "⏎", action: "Edit task")
                    ShortcutRow(keys: "⌫", action: "Delete task")
                }
                #endif
                #if !os(macOS)
                Section("Navigation (iOS/iPadOS)") {
                    ShortcutRow(keys: "⌘1", action: "Switch to List view")
                    ShortcutRow(keys: "⌘2", action: "Switch to Board view")
                }
                #endif
            }
            .navigationTitle("Keyboard Shortcuts")
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String
    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Colors.onSurface)
            Spacer()
            Text(action)
                .foregroundStyle(Colors.onSurfaceVariant)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shortcut \(keys) — \(action)")
    }
}


