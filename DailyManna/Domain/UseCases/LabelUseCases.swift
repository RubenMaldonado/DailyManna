//
//  LabelUseCases.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

/// Use cases for label-related operations
public final class LabelUseCases {
    private let labelsRepository: LabelsRepository
    
    public init(labelsRepository: LabelsRepository) {
        self.labelsRepository = labelsRepository
    }
    
    // MARK: - Label Operations
    
    /// Fetches all labels for a user
    public func fetchLabels(for userId: UUID) async throws -> [Label] {
        let labels = try await labelsRepository.fetchLabels(for: userId)
        return labels.filter { !$0.isDeleted }
    }
    
    /// Fetches labels associated with a specific task
    public func fetchLabelsForTask(_ taskId: UUID) async throws -> [Label] {
        let labels = try await labelsRepository.fetchLabelsForTask(taskId)
        return labels.filter { !$0.isDeleted }
    }
    
    /// Searches labels by name
    public func searchLabels(query: String, for userId: UUID) async throws -> [Label] {
        let allLabels = try await labelsRepository.fetchLabels(for: userId)
        return allLabels.filter { !$0.isDeleted && $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    /// Creates a new label
    public func createLabel(_ label: Label) async throws {
        var local = label
        local.updatedAt = Date()
        local.needsSync = true
        try await labelsRepository.createLabel(local)
    }
    
    /// Updates an existing label
    public func updateLabel(_ label: Label) async throws {
        var updated = label
        updated.updatedAt = Date()
        updated.needsSync = true
        try await labelsRepository.updateLabel(updated)
    }
    
    /// Soft deletes a label
    public func deleteLabel(by id: UUID, for userId: UUID) async throws {
        guard var label = try await labelsRepository.fetchLabel(by: id) else {
            throw DomainError.notFound(id.uuidString)
        }
        label.deletedAt = Date()
        label.updatedAt = Date()
        label.needsSync = true
        try await labelsRepository.updateLabel(label)
    }
    
    /// Associates a label with a task
    public func addLabel(_ labelId: UUID, to taskId: UUID, for userId: UUID) async throws {
        try await labelsRepository.addLabel(labelId, to: taskId, for: userId)
    }
    
    /// Dissociates a label from a task
    public func removeLabel(_ labelId: UUID, from taskId: UUID, for userId: UUID) async throws {
        try await labelsRepository.removeLabel(labelId, from: taskId, for: userId)
    }
}
