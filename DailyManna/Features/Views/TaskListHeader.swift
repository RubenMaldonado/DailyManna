import SwiftUI

struct TaskListHeader: View {
    let onNew: () -> Void
    let onSyncNow: () -> Void
    let isSyncing: Bool
    let userId: UUID
    let selectedBucket: TimeBucket
    let showBucketMenu: Bool
    let onSelectBucket: (TimeBucket) -> Void
    let onOpenFilter: () -> Void
    let activeFilterCount: Int
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Daily Manna").style(Typography.title2).foregroundColor(Colors.onSurface)
                SyncStatusView(isSyncing: isSyncing)
            }
            Spacer()
            #if os(macOS)
            if showBucketMenu {
                Menu {
                    ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                        Button(action: { onSelectBucket(bucket) }) {
                            HStack { Text(bucket.displayName); if bucket == selectedBucket { Spacer(); Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    HStack(spacing: 6) { Image(systemName: "tray" ); Text(selectedBucket.displayName).fixedSize(horizontal: true, vertical: false) }
                }
                .menuStyle(.borderlessButton)
            }
            #endif
            Button(action: onOpenFilter) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    if activeFilterCount > 0 { CountBadge(count: activeFilterCount) }
                }
            }
            .buttonStyle(SecondaryButtonStyle(size: .small))
            .accessibilityLabel(activeFilterCount > 0 ? "Filters, \(activeFilterCount) active" : "Filters")
            Button(action: onSyncNow) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(SecondaryButtonStyle(size: .small))
            Button(action: onNew) { SwiftUI.Label("New", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle(size: .small))
            Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                .buttonStyle(SecondaryButtonStyle(size: .small))
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
    }
}

struct SyncStatusView: View {
    let isSyncing: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isSyncing ? Colors.onSurfaceVariant : Colors.success)
                .frame(width: 8, height: 8)
            Text(isSyncing ? "Syncing…" : "Up to date")
                .style(Typography.caption)
                .foregroundColor(isSyncing ? Colors.onSurfaceVariant : Colors.success)
                .frame(width: 80, alignment: .leading)
                .accessibilityLabel(isSyncing ? "Sync in progress" : "Up to date")
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TaskListHeader(
        onNew: {},
        onSyncNow: {},
        isSyncing: true,
        userId: UUID(),
        selectedBucket: .thisWeek,
        showBucketMenu: true,
        onSelectBucket: { _ in },
        onOpenFilter: {},
        activeFilterCount: 2,
        onOpenSettings: {}
    )
    .background(Colors.background)
}


