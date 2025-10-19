//
//  Task.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

/// Core domain model for a task
public struct Task: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let userId: UUID
    public var bucketKey: TimeBucket
    public var position: Double
    public var parentTaskId: UUID?
    public var templateId: UUID?
    public var seriesId: UUID?
    public var title: String
    public var description: String?
    public var dueAt: Date?
    public var dueHasTime: Bool = true
    public var occurrenceDate: Date?
    public var recurrenceRule: String?
    public var priority: TaskPriority = .normal
    public var reminders: [Date]? = nil
    /// Names of fields that are exceptions (do not auto-propagate from template)
    public var exceptionMask: Set<String>?
    public var isCompleted: Bool
    public var completedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    
    // Sync metadata
    public var version: Int
    public var remoteId: UUID?
    public var needsSync: Bool
    
    public init(
        id: UUID = UUID(),
        userId: UUID,
        bucketKey: TimeBucket,
        position: Double = 0,
        parentTaskId: UUID? = nil,
        templateId: UUID? = nil,
        seriesId: UUID? = nil,
        title: String,
        description: String? = nil,
        dueAt: Date? = nil,
        dueHasTime: Bool = true,
        occurrenceDate: Date? = nil,
        recurrenceRule: String? = nil,
        priority: TaskPriority = .normal,
        reminders: [Date]? = nil,
        exceptionMask: Set<String>? = nil,
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
        self.position = position
        self.parentTaskId = parentTaskId
        self.templateId = templateId
        self.seriesId = seriesId
        self.title = title
        self.description = description
        self.dueAt = dueAt
        self.dueHasTime = dueHasTime
        self.occurrenceDate = occurrenceDate
        self.recurrenceRule = recurrenceRule
        self.priority = priority
        self.reminders = reminders
        self.exceptionMask = exceptionMask
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
        self.remoteId = remoteId
        self.needsSync = needsSync
    }
    
    public var isDeleted: Bool {
        deletedAt != nil
    }
    
    public var hasSubtasks: Bool {
        // This would be determined by the repository layer
        false
    }
}
