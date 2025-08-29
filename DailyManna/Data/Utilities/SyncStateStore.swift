//
//  SyncStateStore.swift
//  DailyManna
//
//  Created for Epic 1.3 (Basic Sync)
//

import Foundation
import SwiftData

/// Lightweight store to manage per-user sync checkpoints
public struct SyncStateSnapshot: Sendable {
    public let lastTasksSyncAt: Date?
    public let lastLabelsSyncAt: Date?
}

actor SyncStateStore {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func loadEntity(userId: UUID) throws -> SyncStateEntity? {
        let descriptor = FetchDescriptor<SyncStateEntity>(
            predicate: #Predicate<SyncStateEntity> { entity in
                entity.userId == userId
            }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    func ensure(userId: UUID) async throws -> SyncStateEntity {
        if let existing = try loadEntity(userId: userId) { return existing }
        let state = SyncStateEntity(userId: userId)
        modelContext.insert(state)
        try modelContext.save()
        return state
    }
    
    /// Loads a Sendable snapshot of the checkpoints for use across actor boundaries
    func loadSnapshot(userId: UUID) async throws -> SyncStateSnapshot? {
        if let entity = try loadEntity(userId: userId) {
            return SyncStateSnapshot(lastTasksSyncAt: entity.lastTasksSyncAt, lastLabelsSyncAt: entity.lastLabelsSyncAt)
        }
        return nil
    }
    
    func updateTasksCheckpoint(userId: UUID, to date: Date) async throws {
        let state = try await ensure(userId: userId)
        state.lastTasksSyncAt = date
        state.updatedAt = Date()
        try modelContext.save()
    }
    
    func updateLabelsCheckpoint(userId: UUID, to date: Date) async throws {
        let state = try await ensure(userId: userId)
        state.lastLabelsSyncAt = date
        state.updatedAt = Date()
        try modelContext.save()
    }

    /// Resets checkpoints for a user by deleting the entity
    func reset(userId: UUID) async throws {
        if let entity = try loadEntity(userId: userId) {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
}


