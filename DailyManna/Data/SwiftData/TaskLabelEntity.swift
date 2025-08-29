//
//  TaskLabelEntity.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData model for TaskLabel junction entities
@Model
final class TaskLabelEntity {
    @Attribute(.unique) var id: UUID
    var taskId: UUID
    var labelId: UUID
    var userId: UUID // For RLS and consistency
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool
    var remoteId: UUID?
    var version: Int
    
    // Note: This is a junction entity for many-to-many relationships
    // Relationships are handled through repository queries using taskId and labelId foreign keys
    
    init(
        id: UUID = UUID(),
        taskId: UUID,
        labelId: UUID,
        userId: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        needsSync: Bool = true,
        remoteId: UUID? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.taskId = taskId
        self.labelId = labelId
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.needsSync = needsSync
        self.remoteId = remoteId
        self.version = version
    }
}
