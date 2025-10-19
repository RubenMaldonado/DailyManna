//
//  SwiftDataLabelsRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData implementation of LabelsRepository
actor SwiftDataLabelsRepository: LabelsRepository {
    private let modelContext: ModelContext
    
    init(modelContainer: ModelContainer) {
        let ctx = ModelContext(modelContainer)
        ctx.autosaveEnabled = true
        self.modelContext = ctx
    }
    
    func fetchLabels(for userId: UUID) async throws -> [Label] {
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.userId == userId && entity.deletedAt == nil
            }
        )
        let entities = try modelContext.fetch(descriptor)
        let result = entities.map { $0.toDomainModel() }
        Logger.shared.info("Local fetch labels count=\(result.count) for user=\(userId)", category: .data)
        return result
    }
    
    func fetchLabel(by id: UUID) async throws -> Label? {
        // Return label regardless of soft-delete state for caller inspection
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.id == id
            }
        )
        let entity = try modelContext.fetch(descriptor).first
        return entity?.toDomainModel()
    }
    
    func createLabel(_ label: Label) async throws {
        Logger.shared.info("Creating label locally: \(label.name)", category: .data)
        var local = label
        if local.remoteId == nil {
            local.needsSync = true
            local.updatedAt = Date()
        }
        let entity = LabelEntity(from: local)
        modelContext.insert(entity)
        try modelContext.save()
        Logger.shared.info("Created label locally: \(label.id)", category: .data)
    }
    
    func updateLabel(_ label: Label) async throws {
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.id == label.id
            }
        )
        guard let entity = try modelContext.fetch(descriptor).first else {
            throw DataError.notFound("Label with ID \(label.id) not found for update.")
        }
        var local = label
        if local.remoteId == nil || local.needsSync {
            local.needsSync = true
            local.updatedAt = Date()
        }
        entity.update(from: local)
        try modelContext.save()
    }
    
    func deleteLabel(by id: UUID) async throws {
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.id == id
            }
        )
        guard let entity = try modelContext.fetch(descriptor).first else {
            throw DataError.notFound("Label with ID \(id) not found for deletion.")
        }
        // Perform soft delete and mark for sync
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        entity.needsSync = true
        try modelContext.save()
    }
    
    func purgeDeletedLabels(olderThan date: Date) async throws {
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.deletedAt != nil
            }
        )
        let entities = try modelContext.fetch(descriptor)
        let entitiesToPurge = entities.filter { ent in
            if let deletedAt = ent.deletedAt { return deletedAt < date }
            return false
        }
        for entity in entitiesToPurge { modelContext.delete(entity) }
        try modelContext.save()
    }
    
    func fetchLabelsForTask(_ taskId: UUID) async throws -> [Label] {
        let descriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.taskId == taskId && entity.deletedAt == nil
            }
        )
        let taskLabelEntities = try modelContext.fetch(descriptor)
        let labelIds = taskLabelEntities.map { $0.labelId }
        // Avoid SwiftData generating an invalid SQL IN () clause for empty arrays
        if labelIds.isEmpty { return [] }
        
        let labelDescriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                labelIds.contains(entity.id) && entity.deletedAt == nil
            }
        )
        let labelEntities = try modelContext.fetch(labelDescriptor)
        return labelEntities.map { $0.toDomainModel() }
    }
    
    func fetchTasks(with labelId: UUID) async throws -> [Task] {
        let descriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.labelId == labelId && entity.deletedAt == nil
            }
        )
        let taskLabelEntities = try modelContext.fetch(descriptor)
        let taskIds = taskLabelEntities.map { $0.taskId }
        
        let taskDescriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
                taskIds.contains(entity.id) && entity.deletedAt == nil
            }
        )
        let taskEntities = try modelContext.fetch(taskDescriptor)
        return taskEntities.map { $0.toDomainModel() }
    }
    
    func addLabel(_ labelId: UUID, to taskId: UUID, for userId: UUID) async throws {
        // Check if already exists
        let existingDescriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.taskId == taskId && entity.labelId == labelId
            }
        )
        if try modelContext.fetch(existingDescriptor).first != nil {
            return // Already associated
        }
        
        let taskLabelEntity = TaskLabelEntity(taskId: taskId, labelId: labelId, userId: userId)
        modelContext.insert(taskLabelEntity)
        // Bump task.updatedAt when labels change
        if let task = try modelContext.fetch(FetchDescriptor<TaskEntity>(predicate: #Predicate<TaskEntity> { $0.id == taskId })).first {
            task.updatedAt = Date()
        }
        try modelContext.save()
    }
    
    func removeLabel(_ labelId: UUID, from taskId: UUID, for userId: UUID) async throws {
        let descriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.taskId == taskId && entity.labelId == labelId
            }
        )
        if let entity = try modelContext.fetch(descriptor).first {
            // Soft-delete link (tombstone) to sync unlink across devices
            entity.deletedAt = Date()
            entity.updatedAt = Date()
            entity.needsSync = true
            // Bump task.updatedAt when labels change
            if let task = try modelContext.fetch(FetchDescriptor<TaskEntity>(predicate: #Predicate<TaskEntity> { $0.id == taskId })).first {
                task.updatedAt = Date()
            }
            try modelContext.save()
        }
    }

    func fetchLabelsNeedingSync(for userId: UUID) async throws -> [Label] {
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.userId == userId && entity.needsSync == true
            }
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toDomainModel() }
    }
    
    func deleteAll(for userId: UUID) async throws {
        // Delete task-label associations for user
        let junctions = try modelContext.fetch(FetchDescriptor<TaskLabelEntity>(predicate: #Predicate<TaskLabelEntity> { $0.userId == userId }))
        for j in junctions { modelContext.delete(j) }
        // Delete labels for user
        let labels = try modelContext.fetch(FetchDescriptor<LabelEntity>(predicate: #Predicate<LabelEntity> { $0.userId == userId }))
        for l in labels { modelContext.delete(l) }
        try modelContext.save()
    }

    // MARK: - Task-Label Links (junction)
    func fetchTaskLabelLinksNeedingSync(for userId: UUID) async throws -> [TaskLabelLink] {
        let descriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.userId == userId && entity.needsSync == true
            }
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { e in
            TaskLabelLink(
                id: e.id,
                taskId: e.taskId,
                labelId: e.labelId,
                userId: e.userId,
                createdAt: e.createdAt,
                updatedAt: e.updatedAt,
                deletedAt: e.deletedAt,
                needsSync: e.needsSync,
                remoteId: e.remoteId,
                version: e.version
            )
        }
    }

    func upsertTaskLabelLink(_ link: TaskLabelLink) async throws {
        let descriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.id == link.id
            }
        )
        if let entity = try modelContext.fetch(descriptor).first {
            entity.taskId = link.taskId
            entity.labelId = link.labelId
            entity.userId = link.userId
            entity.createdAt = link.createdAt
            entity.updatedAt = link.updatedAt
            entity.deletedAt = link.deletedAt
            entity.needsSync = false
            entity.remoteId = link.remoteId
            entity.version = link.version
        } else {
            let entity = TaskLabelEntity(
                id: link.id,
                taskId: link.taskId,
                labelId: link.labelId,
                userId: link.userId,
                createdAt: link.createdAt,
                updatedAt: link.updatedAt,
                deletedAt: link.deletedAt,
                needsSync: false,
                remoteId: link.remoteId,
                version: link.version
            )
            modelContext.insert(entity)
        }
        try modelContext.save()
    }

    func markTaskLabelLinkSynced(taskId: UUID, labelId: UUID) async throws {
        let descriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.taskId == taskId && entity.labelId == labelId
            }
        )
        if let entity = try modelContext.fetch(descriptor).first {
            entity.needsSync = false
            try modelContext.save()
        }
    }
}
