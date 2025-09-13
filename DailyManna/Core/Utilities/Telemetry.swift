import Foundation
import OSLog

enum TelemetryEvent: String {
    case filterOpen
    case filterApply
    case filterClear
    case viewSwitch
    case bucketChange
    // This Week
    case thisWeekViewShown
    case taskRescheduledDrag
    case taskRescheduledQuickAction
    case thisWeekSectionToggle
    // Multi-bucket list
    case multiBucketListShown
    case bucketSectionToggle
    // Working Log
    case workingLogOpened
    case workingLogDayToggled
    case workingLogItemCreated
    case workingLogItemEdited
    case workingLogItemDeleted
    case taskCompletedMovedToWorkingLog
    case taskCompletedUndo
    case workingLogExportMarkdown
}

enum Telemetry {
    private static let store = UserDefaults.standard
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.dailymanna", category: "Telemetry")

    static func record(_ event: TelemetryEvent, metadata: [String: String] = [:]) {
        let key = "telemetry.count.\(event.rawValue)"
        let newValue = (store.integer(forKey: key) + 1)
        store.set(newValue, forKey: key)
        if metadata.isEmpty {
            os_log("%{public}@ #%{public}d", log: log, type: .info, event.rawValue, newValue)
        } else {
            os_log("%{public}@ #%{public}d %{public}@", log: log, type: .info, event.rawValue, newValue, String(describing: metadata))
        }
    }
}


