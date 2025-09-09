//
//  SwiftDataWorkingLogRepository.swift
//  DailyManna
//
//  Local repository for Working Log items using SwiftData
//

import Foundation
import SwiftData

actor SwiftDataWorkingLogRepository: WorkingLogRepository {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func create(_ item: WorkingLogItem) async throws {
        var local = item
        if local.remoteId == nil {
            local.needsSync = true
            local.updatedAt = Date()
        }
        let entity = WorkingLogItemEntity(
            id: local.id,
            userId: local.userId,
            title: local.title,
            body: local.description,
            occurredAt: local.occurredAt,
            createdAt: local.createdAt,
            updatedAt: local.updatedAt,
            deletedAt: local.deletedAt,
            version: local.version,
            remoteId: local.remoteId,
            needsSync: local.needsSync
        )
        modelContext.insert(entity)
        try modelContext.save()
    }
    
    func update(_ item: WorkingLogItem) async throws {
        let descriptor = FetchDescriptor<WorkingLogItemEntity>(
            predicate: #Predicate<WorkingLogItemEntity> { $0.id == item.id }
        )
        guard let entity = try modelContext.fetch(descriptor).first else {
            throw DataError.notFound("WorkingLogItem with ID \(item.id) not found")
        }
        var local = item
        if local.remoteId == nil || local.needsSync {
            local.needsSync = true
            local.updatedAt = Date()
        }
        entity.update(from: local)
        try modelContext.save()
    }
    
    func deleteSoft(id: UUID) async throws {
        let descriptor = FetchDescriptor<WorkingLogItemEntity>(
            predicate: #Predicate<WorkingLogItemEntity> { $0.id == id }
        )
        guard let entity = try modelContext.fetch(descriptor).first else {
            throw DataError.notFound("WorkingLogItem with ID \(id) not found")
        }
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        entity.needsSync = true
        try modelContext.save()
    }
    
    func deleteHard(id: UUID) async throws {
        let descriptor = FetchDescriptor<WorkingLogItemEntity>(
            predicate: #Predicate<WorkingLogItemEntity> { $0.id == id }
        )
        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
    
    func fetch(by id: UUID) async throws -> WorkingLogItem? {
        let descriptor = FetchDescriptor<WorkingLogItemEntity>(
            predicate: #Predicate<WorkingLogItemEntity> { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first?.toDomainModel()
    }
    
    func fetchRange(userId: UUID, startDate: Date, endDate: Date) async throws -> [WorkingLogItem] {
        let descriptor = FetchDescriptor<WorkingLogItemEntity>(
            predicate: #Predicate<WorkingLogItemEntity> { e in
                e.userId == userId && e.deletedAt == nil && e.occurredAt >= startDate && e.occurredAt <= endDate
            }
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toDomainModel() }.sorted { $0.occurredAt > $1.occurredAt }
    }
    
    func search(userId: UUID, text: String, startDate: Date?, endDate: Date?) async throws -> [WorkingLogItem] {
        // Simple contains search (case-insensitive); diacritics-insensitive left to UI normalization
        let lowered = text.lowercased()
        let descriptor = FetchDescriptor<WorkingLogItemEntity>(
            predicate: #Predicate<WorkingLogItemEntity> { e in
                e.userId == userId && e.deletedAt == nil &&
                (startDate == nil || e.occurredAt >= startDate!) &&
                (endDate == nil || e.occurredAt <= endDate!)
            }
        )
        let entities = try modelContext.fetch(descriptor)
        let filtered = entities.filter { e in
            e.title.lowercased().contains(lowered) || e.body.lowercased().contains(lowered)
        }
        return filtered.map { $0.toDomainModel() }.sorted { $0.occurredAt > $1.occurredAt }
    }
    
    func purgeSoftDeleted(olderThan date: Date) async throws {
        let descriptor = FetchDescriptor<WorkingLogItemEntity>(
            predicate: #Predicate<WorkingLogItemEntity> { e in
                e.deletedAt != nil
            }
        )
        let entities = try modelContext.fetch(descriptor)
        let toPurge = entities.filter { ent in
            if let deletedAt = ent.deletedAt { return deletedAt < date }
            return false
        }
        for e in toPurge { modelContext.delete(e) }
        try modelContext.save()
    }
    
    func fetchNeedingSync(for userId: UUID) async throws -> [WorkingLogItem] {
        let descriptor = FetchDescriptor<WorkingLogItemEntity>(
            predicate: #Predicate<WorkingLogItemEntity> { e in
                e.userId == userId && e.needsSync == true
            }
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toDomainModel() }
    }
}


