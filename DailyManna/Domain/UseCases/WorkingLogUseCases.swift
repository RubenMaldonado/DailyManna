//
//  WorkingLogUseCases.swift
//  DailyManna
//
//  Created for Epic 2.6 - Working Log
//

import Foundation

public final class WorkingLogUseCases {
    private let repository: WorkingLogRepository
    
    public init(repository: WorkingLogRepository) {
        self.repository = repository
    }
    
    // MARK: - Queries
    public func fetchRange(userId: UUID, startDate: Date, endDate: Date) async throws -> [WorkingLogItem] {
        try await repository.fetchRange(userId: userId, startDate: startDate, endDate: endDate)
    }
    
    public func search(userId: UUID, text: String, startDate: Date?, endDate: Date?) async throws -> [WorkingLogItem] {
        try await repository.search(userId: userId, text: text, startDate: startDate, endDate: endDate)
    }
    
    // MARK: - Mutations
    public func create(_ item: WorkingLogItem) async throws {
        var local = item
        // Validation
        if local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DomainError.validationError("Title is required")
        }
        if local.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DomainError.validationError("Description is required")
        }
        if local.occurredAt > Date() { throw DomainError.validationError("Date cannot be in the future") }
        local.updatedAt = Date()
        local.needsSync = true
        try await repository.create(local)
    }
    
    public func update(_ item: WorkingLogItem) async throws {
        var local = item
        if local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DomainError.validationError("Title is required")
        }
        if local.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DomainError.validationError("Description is required")
        }
        if local.occurredAt > Date() { throw DomainError.validationError("Date cannot be in the future") }
        local.updatedAt = Date()
        local.needsSync = true
        try await repository.update(local)
    }
    
    public func deleteSoft(id: UUID) async throws {
        try await repository.deleteSoft(id: id)
    }
    
    public func deleteHard(id: UUID) async throws {
        try await repository.deleteHard(id: id)
    }
    
    public func purgeSoftDeleted(olderThan date: Date) async throws {
        try await repository.purgeSoftDeleted(olderThan: date)
    }
}


