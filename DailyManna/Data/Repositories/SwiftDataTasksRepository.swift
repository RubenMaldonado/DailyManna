//
//  SwiftDataTasksRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData implementation of TasksRepository
final class SwiftDataTasksRepository: TasksRepository {
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
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
                entity.id == id && entity.deletedAt == nil
            }
        )
        let entity = try modelContext.fetch(descriptor).first
        return entity?.toDomainModel()
    }
    
    func createTask(_ task: Task) async throws {
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
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate<TaskEntity> { entity in
                entity.deletedAt != nil && entity.deletedAt! < date
            }
        )
        let entitiesToPurge = try modelContext.fetch(descriptor)
        for entity in entitiesToPurge {
            modelContext.delete(entity)
        }
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
}
