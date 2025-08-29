//
//  LabelsRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

/// Repository protocol for label data operations
public protocol LabelsRepository: Sendable {
    /// Fetches all labels for a specific user
    func fetchLabels(for userId: UUID) async throws -> [Label]
    
    /// Fetches a specific label by ID
    func fetchLabel(by id: UUID) async throws -> Label?
    
    /// Creates a new label
    func createLabel(_ label: Label) async throws
    
    /// Updates an existing label
    func updateLabel(_ label: Label) async throws
    
    /// Marks a label as deleted (soft delete)
    func deleteLabel(by id: UUID) async throws
    
    /// Permanently removes deleted labels (cleanup)
    func purgeDeletedLabels(olderThan date: Date) async throws
    
    /// Fetches labels for a specific task
    func fetchLabelsForTask(_ taskId: UUID) async throws -> [Label]
    
    /// Fetches tasks that have a specific label
    func fetchTasks(with labelId: UUID) async throws -> [Task]
    
    /// Associates a label with a task
    func addLabel(_ labelId: UUID, to taskId: UUID, for userId: UUID) async throws
    
    /// Dissociates a label from a task
    func removeLabel(_ labelId: UUID, from taskId: UUID, for userId: UUID) async throws
    
    /// Fetches labels that are marked as needing sync for push
    func fetchLabelsNeedingSync(for userId: UUID) async throws -> [Label]
    
    /// Deletes all labels and associations for a user (local-only)
    func deleteAll(for userId: UUID) async throws

    // MARK: - Task-Label Links (junction)
    /// Fetches task-label links marked as needing sync (adds and tombstoned removes)
    func fetchTaskLabelLinksNeedingSync(for userId: UUID) async throws -> [TaskLabelLink]
    /// Upserts a task-label link from a remote payload
    func upsertTaskLabelLink(_ link: TaskLabelLink) async throws
    /// Marks a task-label link as synced (clears needsSync) identified by task and label
    func markTaskLabelLinkSynced(taskId: UUID, labelId: UUID) async throws
}
