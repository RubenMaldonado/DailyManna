//
//  TaskUseCases.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

/// Domain errors
public enum DomainError: Error, LocalizedError {
    case notFound(String)
    case invalidOperation(String)
    case validationError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notFound(let id): return "Item with ID \(id) not found"
        case .invalidOperation(let message): return "Invalid operation: \(message)"
        case .validationError(let message): return "Validation error: \(message)"
        }
    }
}

/// Use cases for task-related operations
public final class TaskUseCases {
    private let tasksRepository: TasksRepository
    private let labelsRepository: LabelsRepository
    
    public init(tasksRepository: TasksRepository, labelsRepository: LabelsRepository) {
        self.tasksRepository = tasksRepository
        self.labelsRepository = labelsRepository
    }
    
    // MARK: - Task Operations
    
    /// Fetches all tasks for a user, optionally filtered by bucket, and includes their associated labels
    public func fetchTasksWithLabels(for userId: UUID, in bucket: TimeBucket?) async throws -> [(Task, [Label])] {
        let tasks = try await tasksRepository.fetchTasks(for: userId, in: bucket)
        var result: [(Task, [Label])] = []
        
        for task in tasks.filter({ !$0.isDeleted }) {
            let labels = try await labelsRepository.fetchLabelsForTask(task.id)
            result.append((task, labels.filter { !$0.isDeleted }))
        }
        
        return result
    }
    
    /// Fetches a specific task by ID, including its associated labels
    public func fetchTaskWithLabels(by id: UUID) async throws -> (Task, [Label])? {
        guard let task = try await tasksRepository.fetchTask(by: id), !task.isDeleted else { return nil }
        let labels = try await labelsRepository.fetchLabelsForTask(task.id)
        return (task, labels.filter { !$0.isDeleted })
    }
    
    /// Creates a new task
    public func createTask(_ task: Task) async throws {
        var local = task
        local.updatedAt = Date()
        local.needsSync = true
        try await tasksRepository.createTask(local)
    }
    
    /// Updates an existing task
    public func updateTask(_ task: Task) async throws {
        var updated = task
        updated.updatedAt = Date()
        updated.needsSync = true
        try await tasksRepository.updateTask(updated)
    }
    
    /// Marks a task as completed or incomplete
    public func toggleTaskCompletion(id: UUID, userId: UUID) async throws {
        guard var task = try await tasksRepository.fetchTask(by: id) else {
            throw DomainError.notFound(id.uuidString)
        }
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? Date() : nil
        task.updatedAt = Date()
        task.needsSync = true
        try await tasksRepository.updateTask(task)
    }
    
    /// Moves a task to a different time bucket
    public func moveTask(id: UUID, to newBucket: TimeBucket, for userId: UUID) async throws {
        guard var task = try await tasksRepository.fetchTask(by: id) else {
            throw DomainError.notFound(id.uuidString)
        }
        task.bucketKey = newBucket
        task.updatedAt = Date()
        task.needsSync = true
        try await tasksRepository.updateTask(task)
    }
    
    /// Soft deletes a task
    public func deleteTask(by id: UUID, for userId: UUID) async throws {
        guard var task = try await tasksRepository.fetchTask(by: id) else {
            throw DomainError.notFound(id.uuidString)
        }
        task.deletedAt = Date()
        task.updatedAt = Date()
        task.needsSync = true
        try await tasksRepository.updateTask(task)
    }
    
    /// Fetches sub-tasks for a given parent task
    public func fetchSubTasks(for parentTaskId: UUID) async throws -> [Task] {
        let subTasks = try await tasksRepository.fetchSubTasks(for: parentTaskId)
        return subTasks.filter { !$0.isDeleted }
    }

    // MARK: - Counts
    /// Returns the number of tasks in a specific bucket for the user. Excludes completed by default.
    public func countTasks(for userId: UUID, in bucket: TimeBucket, includeCompleted: Bool = false) async throws -> Int {
        try await tasksRepository.countTasks(for: userId, in: bucket, includeCompleted: includeCompleted)
    }
}
