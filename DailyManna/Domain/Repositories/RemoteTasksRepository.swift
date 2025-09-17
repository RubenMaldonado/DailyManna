//
//  RemoteTasksRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

protocol RemoteTasksRepository {
    func createTask(_ task: Task) async throws -> Task
    /// Fetch a single task by id from the remote store
    func fetchTask(id: UUID) async throws -> Task?
    func fetchTasks(since lastSync: Date?) async throws -> [Task]
    /// Context-aware delta fetch trimmed by optional bucket and due date cutoff
    func fetchTasks(since lastSync: Date?, bucketKey: String?, dueBy: Date?) async throws -> [Task]
    func updateTask(_ task: Task) async throws -> Task
    func deleteTask(id: UUID) async throws
    func fetchTasksForBucket(_ bucketKey: String) async throws -> [Task]
    func syncTasks(_ tasks: [Task]) async throws -> [Task]
    // Realtime hooks (no-op for now)
    func startRealtime(userId: UUID) async throws
    func stopRealtime() async
    /// Bulk soft-delete all user tasks remotely (testing convenience)
    func deleteAll(for userId: UUID) async throws
}
