//
//  WeeklyRolloverService.swift
//  DailyManna
//
//  Moves remaining THIS_WEEK tasks to NEXT_WEEK starting Saturday 00:00 local time.
//

import Foundation

struct WeeklyRolloverService {
    private let userDefaults = UserDefaults.standard
    private let stride: Double = 1024
    
    private func saturdayStartOfCurrentWeek(now: Date, calendar: Calendar) -> Date {
        WeekPlanner.saturdayAndSundayOfCurrentWeek(for: now, calendar: calendar).saturday
    }
    
    private func upcomingMonday(now: Date, calendar: Calendar) -> Date {
        WeekPlanner.nextMonday(after: now, calendar: calendar)
    }
    
    private func performedKey(for userId: UUID) -> String { "weeklyRollover.lastPerformed.\(userId.uuidString)" }
    
    private func upcomingWeekKey(now: Date, calendar: Calendar) -> String {
        let monday = upcomingMonday(now: now, calendar: calendar)
        return WeekPlanner.isoDayKey(for: monday, calendar: calendar) // e.g., 2025-09-22
    }
    
    private func hasPerformed(userId: UUID, weekKey: String) -> Bool {
        userDefaults.string(forKey: performedKey(for: userId)) == weekKey
    }
    
    private func markPerformed(userId: UUID, weekKey: String) {
        userDefaults.set(weekKey, forKey: performedKey(for: userId))
    }
    
    /// Returns true if rollover ran and performed any work (moved at least one task), false otherwise.
    @MainActor
    func performIfNeeded(userId: UUID) async -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let saturdayStart = saturdayStartOfCurrentWeek(now: now, calendar: calendar)
        guard now >= saturdayStart else { return false }
        let weekKey = upcomingWeekKey(now: now, calendar: calendar)
        guard hasPerformed(userId: userId, weekKey: weekKey) == false else { return false }
        
        do {
            let deps = Dependencies.shared
            let taskUC = try TaskUseCases(
                tasksRepository: deps.resolve(type: TasksRepository.self),
                labelsRepository: deps.resolve(type: LabelsRepository.self)
            )
            // Fetch candidates: all incomplete tasks in THIS_WEEK
            let thisWeekPairs = try await taskUC.fetchTasksWithLabels(for: userId, in: .thisWeek)
            let candidates = thisWeekPairs
                .map { $0.0 }
                .filter { $0.isCompleted == false }
                .sorted { $0.position < $1.position }
            
            // If none, still mark performed for this upcoming week to avoid re-checking repeatedly this weekend
            if candidates.isEmpty {
                markPerformed(userId: userId, weekKey: weekKey)
                return false
            }
            
            // Compute tail of NEXT_WEEK to append after
            let nextWeekPairs = try await taskUC.fetchTasksWithLabels(for: userId, in: .nextWeek)
            let basePos = nextWeekPairs.map { $0.0.position }.max() ?? 0
            
            // Move each candidate preserving relative order
            var didAnyMove = false
            for (idx, task) in candidates.enumerated() {
                let newPos = basePos + stride * Double(idx + 1)
                try await taskUC.updateTaskOrderAndBucket(id: task.id, to: .nextWeek, position: newPos, userId: userId)
                didAnyMove = true
            }
            
            // Mark performed for this upcoming week (covers both Saturday and Sunday)
            markPerformed(userId: userId, weekKey: weekKey)
            return didAnyMove
        } catch {
            // On failure, do not mark performed so we can retry later
            return false
        }
    }
}


