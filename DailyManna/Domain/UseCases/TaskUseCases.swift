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
        let visible = tasks.filter { !$0.isDeleted }
        // Fetch labels in small batches to reduce UI stall; still parallelized per batch
        var output: [(Task, [Label])] = []
        output.reserveCapacity(visible.count)
        let batchSize = 50
        var index = 0
        while index < visible.count {
            let end = min(index + batchSize, visible.count)
            let slice = Array(visible[index..<end])
            let batch: [(Task, [Label])] = try await withThrowingTaskGroup(of: (Task, [Label]).self) { group in
                for task in slice {
                    group.addTask { [labelsRepository] in
                        let labels = try await labelsRepository.fetchLabelsForTask(task.id).filter { !$0.isDeleted }
                        return (task, labels)
                    }
                }
                var results: [(Task, [Label])] = []
                results.reserveCapacity(slice.count)
                for try await pair in group { results.append(pair) }
                return results
            }
            output.append(contentsOf: batch)
            index = end
        }
        return output
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
        // New tasks go to the bottom of the selected bucket (incomplete set)
        let bottom = try await tasksRepository.nextPositionForBottom(userId: task.userId, in: task.bucketKey)
        local.position = bottom
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

    /// Assigns labels to a task using a target set (diff add/remove)
    public func setLabels(for taskId: UUID, to desired: Set<UUID>, userId: UUID) async throws {
        let current = try await labelsRepository.fetchLabelsForTask(taskId).map { $0.id }
        let currentSet = Set(current)
        let toAdd = desired.subtracting(currentSet)
        let toRemove = currentSet.subtracting(desired)
        for id in toAdd { try await labelsRepository.addLabel(id, to: taskId, for: userId) }
        for id in toRemove { try await labelsRepository.removeLabel(id, from: taskId, for: userId) }
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
        // Default to append at bottom if position will be assigned later by caller
        task.updatedAt = Date()
        task.needsSync = true
        try await tasksRepository.updateTask(task)
    }

    /// Update only ordering and bucket in one step.
    public func updateTaskOrderAndBucket(id: UUID, to newBucket: TimeBucket, position: Double, userId: UUID) async throws {
        guard var task = try await tasksRepository.fetchTask(by: id) else {
            throw DomainError.notFound(id.uuidString)
        }
        task.bucketKey = newBucket
        task.position = position
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

    /// Returns (completed, total) subtask counts for a given parent
    public func getSubtaskProgress(parentTaskId: UUID) async throws -> (Int, Int) {
        try await tasksRepository.countSubtasks(parentTaskId: parentTaskId)
    }

    // MARK: - Subtasks
    /// Creates a new subtask under a parent with next bottom position
    public func createSubtask(parentId: UUID, userId: UUID, title: String) async throws -> Task {
        guard let parent = try await tasksRepository.fetchTask(by: parentId) else {
            throw DomainError.notFound(parentId.uuidString)
        }
        let position = try await tasksRepository.nextSubtaskBottomPosition(parentTaskId: parentId)
        var sub = Task(
            userId: userId,
            bucketKey: parent.bucketKey,
            position: position,
            parentTaskId: parentId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        sub.updatedAt = Date()
        sub.needsSync = true
        try await tasksRepository.createTask(sub)
        return sub
    }

    /// Reorders a parent's incomplete subtasks using ordered IDs
    public func reorderSubtasks(parentId: UUID, orderedIds: [UUID]) async throws {
        try await tasksRepository.reorderSubtasks(parentTaskId: parentId, orderedIds: orderedIds)
    }

    /// Toggles subtask completion and updates parent completion if all children complete
    public func toggleSubtaskCompletion(id: UUID) async throws {
        guard var sub = try await tasksRepository.fetchTask(by: id) else { throw DomainError.notFound(id.uuidString) }
        sub.isCompleted.toggle()
        sub.completedAt = sub.isCompleted ? Date() : nil
        sub.updatedAt = Date()
        sub.needsSync = true
        try await tasksRepository.updateTask(sub)

        if let parentId = sub.parentTaskId {
            let (completed, total) = try await tasksRepository.countSubtasks(parentTaskId: parentId)
            if let parent = try await tasksRepository.fetchTask(by: parentId) {
                var updatedParent = parent
                let shouldBeComplete = (total > 0 && completed == total)
                if updatedParent.isCompleted != shouldBeComplete {
                    updatedParent.isCompleted = shouldBeComplete
                    updatedParent.completedAt = shouldBeComplete ? Date() : nil
                    updatedParent.updatedAt = Date()
                    updatedParent.needsSync = true
                    try await tasksRepository.updateTask(updatedParent)
                }
            }
        }
    }

    /// Cascades parent completion toggle to all subtasks
    public func toggleParentCompletionCascade(parentId: UUID) async throws {
        guard var parent = try await tasksRepository.fetchTask(by: parentId) else { throw DomainError.notFound(parentId.uuidString) }
        let newState = !parent.isCompleted
        parent.isCompleted = newState
        parent.completedAt = newState ? Date() : nil
        parent.updatedAt = Date()
        parent.needsSync = true
        try await tasksRepository.updateTask(parent)

        let children = try await tasksRepository.fetchSubTasks(for: parentId).filter { !$0.isDeleted }
        for var child in children {
            if child.isCompleted != newState {
                child.isCompleted = newState
                child.completedAt = newState ? Date() : nil
                child.updatedAt = Date()
                child.needsSync = true
                try await tasksRepository.updateTask(child)
            }
        }
    }

    // MARK: - Counts
    /// Returns the number of tasks in a specific bucket for the user. Excludes completed by default.
    public func countTasks(for userId: UUID, in bucket: TimeBucket, includeCompleted: Bool = false) async throws -> Int {
        try await tasksRepository.countTasks(for: userId, in: bucket, includeCompleted: includeCompleted)
    }

    // MARK: - Ordering Helpers
    public func recompactPositions(userId: UUID, in bucket: TimeBucket) async throws {
        try await tasksRepository.recompactPositions(userId: userId, in: bucket)
    }
}
