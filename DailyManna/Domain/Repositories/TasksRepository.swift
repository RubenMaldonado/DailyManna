//
//  TasksRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

/// Repository protocol for task data operations
public protocol TasksRepository: Sendable {
    /// Fetches all tasks for a specific user, optionally filtered by time bucket
    func fetchTasks(for userId: UUID, in bucket: TimeBucket?) async throws -> [Task]
    
    /// Fetches a specific task by ID
    func fetchTask(by id: UUID) async throws -> Task?
    
    /// Creates a new task
    func createTask(_ task: Task) async throws
    
    /// Updates an existing task
    func updateTask(_ task: Task) async throws
    
    /// Marks a task as deleted (soft delete)
    func deleteTask(by id: UUID) async throws
    
    /// Permanently removes deleted tasks (cleanup)
    func purgeDeletedTasks(olderThan date: Date) async throws
    
    /// Fetches sub-tasks for a given parent task
    func fetchSubTasks(for parentTaskId: UUID) async throws -> [Task]

    /// Counts tasks for a user and bucket. Excludes completed by default.
    func countTasks(for userId: UUID, in bucket: TimeBucket, includeCompleted: Bool) async throws -> Int
}
