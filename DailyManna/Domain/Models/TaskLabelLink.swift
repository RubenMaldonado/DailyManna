//
//  TaskLabelLink.swift
//  DailyManna
//
//  Created for Epic 2.1 (Labels & Filtering)
//

import Foundation

/// Domain model representing the many-to-many link between a Task and a Label
public struct TaskLabelLink: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let taskId: UUID
    public let labelId: UUID
    public let userId: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsSync: Bool
    public var remoteId: UUID?
    public var version: Int
    
    public init(
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


