//
//  SwiftDataLabelsRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData implementation of LabelsRepository
final class SwiftDataLabelsRepository: LabelsRepository {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchLabels(for userId: UUID) async throws -> [Label] {
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.userId == userId && entity.deletedAt == nil
            }
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toDomainModel() }
    }
    
    func fetchLabel(by id: UUID) async throws -> Label? {
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.id == id && entity.deletedAt == nil
            }
        )
        let entity = try modelContext.fetch(descriptor).first
        return entity?.toDomainModel()
    }
    
    func createLabel(_ label: Label) async throws {
        let entity = LabelEntity(from: label)
        modelContext.insert(entity)
        try modelContext.save()
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
        entity.update(from: label)
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
        // Perform soft delete
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try modelContext.save()
    }
    
    func purgeDeletedLabels(olderThan date: Date) async throws {
        let descriptor = FetchDescriptor<LabelEntity>(
            predicate: #Predicate<LabelEntity> { entity in
                entity.deletedAt != nil && entity.deletedAt! < date
            }
        )
        let entitiesToPurge = try modelContext.fetch(descriptor)
        for entity in entitiesToPurge {
            modelContext.delete(entity)
        }
        try modelContext.save()
    }
    
    func fetchLabelsForTask(_ taskId: UUID) async throws -> [Label] {
        let descriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.taskId == taskId
            }
        )
        let taskLabelEntities = try modelContext.fetch(descriptor)
        let labelIds = taskLabelEntities.map { $0.labelId }
        
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
                entity.labelId == labelId
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
        try modelContext.save()
    }
    
    func removeLabel(_ labelId: UUID, from taskId: UUID, for userId: UUID) async throws {
        let descriptor = FetchDescriptor<TaskLabelEntity>(
            predicate: #Predicate<TaskLabelEntity> { entity in
                entity.taskId == taskId && entity.labelId == labelId
            }
        )
        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
}
