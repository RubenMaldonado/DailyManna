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
        // Preserve provided updatedAt (e.g., from remote); local callers should set appropriately
        let entity = TaskEntity(from: task)
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
        // Do not override updatedAt; callers (use-cases or sync) must set it
        entity.update(from: task)
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
        // Perform soft delete
        entity.deletedAt = Date()
        entity.updatedAt = Date()
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
}
