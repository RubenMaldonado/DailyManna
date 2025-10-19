//
//  Template.swift
//  DailyManna
//
//  Defines routine templates with defaults used to generate occurrences.
//

import Foundation

public struct Template: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let ownerId: UUID
    public var name: String
    public var description: String?
    public var labelsDefault: [UUID] // label IDs
    public var checklistDefault: [String]
    public var defaultBucket: TimeBucket // defaults to .routines
    public var defaultDueTime: DateComponents? // hour/minute in local TZ
    public var priority: TaskPriority
    public var defaultDurationMinutes: Int?
    public var status: String // draft|active|paused|archived
    public var version: Int
    public var endAfterCount: Int?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        ownerId: UUID,
        name: String,
        description: String? = nil,
        labelsDefault: [UUID] = [],
        checklistDefault: [String] = [],
        defaultBucket: TimeBucket = .routines,
        defaultDueTime: DateComponents? = nil,
        priority: TaskPriority = .normal,
        defaultDurationMinutes: Int? = nil,
        status: String = "draft",
        version: Int = 1,
        endAfterCount: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.description = description
        self.labelsDefault = labelsDefault
        self.checklistDefault = checklistDefault
        self.defaultBucket = defaultBucket
        self.defaultDueTime = defaultDueTime
        self.priority = priority
        self.defaultDurationMinutes = defaultDurationMinutes
        self.status = status
        self.version = version
        self.endAfterCount = endAfterCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}


