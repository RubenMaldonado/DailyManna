//
//  WorkingLogItem.swift
//  DailyManna
//
//  Created for Epic 2.6 - Working Log
//

import Foundation

/// Core domain model for a non-task working log item
public struct WorkingLogItem: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let userId: UUID
    public var title: String
    public var description: String
    public var occurredAt: Date
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
        title: String,
        description: String,
        occurredAt: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        version: Int = 1,
        remoteId: UUID? = nil,
        needsSync: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.description = description
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
        self.remoteId = remoteId
        self.needsSync = needsSync
    }
    
    public var isDeleted: Bool { deletedAt != nil }
}


