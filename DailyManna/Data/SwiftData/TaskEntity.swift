//
//  TaskEntity.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData model for Task entities
@Model
final class TaskEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var bucketKey: String
    var position: Double
    var parentTaskId: UUID?
    var title: String
    var taskDescription: String? // Renamed to avoid conflict with Swift's `description`
    var dueAt: Date?
    var dueHasTime: Bool = true
    var recurrenceRule: String?
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    
    // Sync metadata
    var version: Int
    var remoteId: UUID?
    var needsSync: Bool
    
    // Note: Relationships are handled through repository queries to avoid SwiftData circular reference issues
    // Sub-tasks are fetched via parentTaskId foreign key
    // Task-label relationships are managed through TaskLabelEntity
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        bucketKey: String,
        parentTaskId: UUID? = nil,
        position: Double = 0,
        title: String,
        taskDescription: String? = nil,
        dueAt: Date? = nil,
        dueHasTime: Bool = true,
        recurrenceRule: String? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        version: Int = 1,
        remoteId: UUID? = nil,
        needsSync: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.bucketKey = bucketKey
        self.parentTaskId = parentTaskId
        self.position = position
        self.title = title
        self.taskDescription = taskDescription
        self.dueAt = dueAt
        self.dueHasTime = dueHasTime
        self.recurrenceRule = recurrenceRule
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
        self.remoteId = remoteId
        self.needsSync = needsSync
    }
    
    // MARK: - Mappers
    
    func toDomainModel() -> Task {
        Task(
            id: id,
            userId: userId,
            bucketKey: TimeBucket(rawValue: bucketKey) ?? .thisWeek,
            position: position,
            parentTaskId: parentTaskId,
            title: title,
            description: taskDescription,
            dueAt: dueAt,
            dueHasTime: dueHasTime,
            recurrenceRule: recurrenceRule,
            isCompleted: isCompleted,
            completedAt: completedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            version: version,
            remoteId: remoteId,
            needsSync: needsSync
        )
    }
    
    func update(from domain: Task) {
        self.userId = domain.userId
        self.bucketKey = domain.bucketKey.rawValue
        self.position = domain.position
        self.parentTaskId = domain.parentTaskId
        self.title = domain.title
        self.taskDescription = domain.description
        self.dueAt = domain.dueAt
        self.dueHasTime = domain.dueHasTime
        self.recurrenceRule = domain.recurrenceRule
        self.isCompleted = domain.isCompleted
        self.completedAt = domain.completedAt
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
        self.deletedAt = domain.deletedAt
        self.version = domain.version
        self.remoteId = domain.remoteId
        self.needsSync = domain.needsSync
    }
}

// MARK: - Mapper Extension
extension TaskEntity {
    convenience init(from domain: Task) {
        self.init(
            id: domain.id,
            userId: domain.userId,
            bucketKey: domain.bucketKey.rawValue,
            parentTaskId: domain.parentTaskId,
            position: domain.position,
            title: domain.title,
            taskDescription: domain.description,
            dueAt: domain.dueAt,
            dueHasTime: domain.dueHasTime,
            recurrenceRule: domain.recurrenceRule,
            isCompleted: domain.isCompleted,
            completedAt: domain.completedAt,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            deletedAt: domain.deletedAt,
            version: domain.version,
            remoteId: domain.remoteId,
            needsSync: domain.needsSync
        )
    }
}
