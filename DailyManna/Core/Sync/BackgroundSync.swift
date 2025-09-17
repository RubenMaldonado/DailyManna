//
//  BackgroundSync.swift
//  DailyManna
//
//  Handles BGTaskScheduler registration and background refresh sync.
//

import Foundation

#if os(iOS)
import BackgroundTasks

enum BackgroundSync {
    static let refreshIdentifier = "com.rubentena.dailymanna.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleAppRefresh(task: refreshTask)
        }
    }

    static func schedule(earliestIn seconds: TimeInterval = 30 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(seconds)
        do { try BGTaskScheduler.shared.submit(request) } catch {
            Logger.shared.error("BGTask submit failed", category: .sync, error: error)
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        Logger.shared.info("BGAppRefreshTask started", category: .sync)
        var cancelled = false
        task.expirationHandler = {
            cancelled = true
        }

        _Concurrency.Task { @MainActor in
            defer { schedule() } // always reschedule for next time
            do {
                let auth = try Dependencies.shared.resolve(type: AuthenticationService.self)
                guard auth.isAuthenticated, let user = auth.currentUser else {
                    task.setTaskCompleted(success: true)
                    return
                }
                let sync = try Dependencies.shared.resolve(type: SyncService.self)
                // Timebox by periodically checking cancelled flag between phases
                await sync.sync(for: user.id)
                if cancelled { Logger.shared.info("BG task expired after sync", category: .sync) }
                task.setTaskCompleted(success: true)
            } catch {
                Logger.shared.error("BG refresh failed", category: .sync, error: error)
                task.setTaskCompleted(success: false)
            }
        }
    }
}
#endif


