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
}
