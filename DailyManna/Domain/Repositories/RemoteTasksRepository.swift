//
//  RemoteTasksRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

protocol RemoteTasksRepository {
    func createTask(_ task: Task) async throws -> Task
    func fetchTasks(since lastSync: Date?) async throws -> [Task]
    func updateTask(_ task: Task) async throws -> Task
    func deleteTask(id: UUID) async throws
    func fetchTasksForBucket(_ bucketKey: String) async throws -> [Task]
    func syncTasks(_ tasks: [Task]) async throws -> [Task]
}
