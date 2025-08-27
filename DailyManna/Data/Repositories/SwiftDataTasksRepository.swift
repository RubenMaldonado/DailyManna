//
//  SwiftDataTasksRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData implementation of TasksRepository
actor SwiftDataTasksRepository: TasksRepository {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchTasks(for userId: UUID, in bucket: TimeBucket?) async throws -> [Task] {
        var descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
                entity.userId == userId && entity.deletedAt == nil
            }
        )
        
        if let bucket {
            descriptor.predicate = #Predicate<TaskEntity> { entity in
                entity.userId == userId && entity.deletedAt == nil && entity.bucketKey == bucket.rawValue
            }
        }
        
        descriptor.sortBy = [SortDescriptor(\TaskEntity.dueAt, order: .forward), SortDescriptor(\TaskEntity.createdAt, order: .forward)]
        
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toDomainModel() }
    }
    
    func fetchTask(by id: UUID) async throws -> Task? {
        // Return task regardless of soft-delete state; callers can inspect deletedAt
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
                entity.id == id
            }
        )
        let entity = try modelContext.fetch(descriptor).first
        return entity?.toDomainModel()
    }
    
    func createTask(_ task: Task) async throws {
        var local = task
        // If this is a local create (no remoteId), mark for sync and bump timestamp.
        if local.remoteId == nil {
            local.needsSync = true
            local.updatedAt = Date()
        }
        // If coming from remote (remoteId present), preserve server timestamps and flags.
        let entity = TaskEntity(from: local)
        modelContext.insert(entity)
        try modelContext.save()
    }
    
    func updateTask(_ task: Task) async throws {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
                entity.id == task.id
            }
        )
        guard let entity = try modelContext.fetch(descriptor).first else {
            throw DataError.notFound("Task with ID \(task.id) not found for update.")
        }
        var local = task
        // For local updates (no remoteId or explicitly flagged), mark for sync and bump timestamp
        if local.remoteId == nil || local.needsSync {
            local.needsSync = true
            local.updatedAt = Date()
        }
        entity.update(from: local)
        try modelContext.save()
    }
    
    func deleteTask(by id: UUID) async throws {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
                entity.id == id
            }
        )
        guard let entity = try modelContext.fetch(descriptor).first else {
            throw DataError.notFound("Task with ID \(id) not found for deletion.")
        }
        // Perform soft delete and mark for sync
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        entity.needsSync = true
        try modelContext.save()
    }
    
    func purgeDeletedTasks(olderThan date: Date) async throws {
        // Fetch soft-deleted tasks, then compare dates in-memory to avoid optional unwrap in predicate
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
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
    
    func fetchSubTasks(for parentTaskId: UUID) async throws -> [Task] {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
                entity.parentTaskId == parentTaskId && entity.deletedAt == nil
            }
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toDomainModel() }
    }

    func countTasks(for userId: UUID, in bucket: TimeBucket, includeCompleted: Bool) async throws -> Int {
        var predicate = #Predicate<TaskEntity> { entity in
            entity.userId == userId && entity.bucketKey == bucket.rawValue && entity.deletedAt == nil
        }
        if includeCompleted == false {
            predicate = #Predicate<TaskEntity> { entity in
                entity.userId == userId && entity.bucketKey == bucket.rawValue && entity.deletedAt == nil && entity.isCompleted == false
            }
        }
        let descriptor = FetchDescriptor<TaskEntity>(predicate: predicate)
        return try modelContext.fetch(descriptor).count
    }

    func fetchTasksNeedingSync(for userId: UUID) async throws -> [Task] {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
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
        // Delete tasks for user
        let tasks = try modelContext.fetch(FetchDescriptor<TaskEntity>(predicate: #Predicate<TaskEntity> { $0.userId == userId }))
        for t in tasks { modelContext.delete(t) }
        try modelContext.save()
    }
}
