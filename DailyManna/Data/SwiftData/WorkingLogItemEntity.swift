//
//  WorkingLogItemEntity.swift
//  DailyManna
//
//  Created for Epic 2.6 - Working Log
//

import Foundation
import SwiftData

@Model
final class WorkingLogItemEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var title: String
    var body: String // maps to domain description
    var occurredAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    
    // Sync metadata
    var version: Int
    var remoteId: UUID?
    var needsSync: Bool
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        title: String,
        body: String,
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
        self.body = body
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
        self.remoteId = remoteId
        self.needsSync = needsSync
    }
}

extension WorkingLogItemEntity {
    func toDomainModel() -> WorkingLogItem {
        WorkingLogItem(
            id: id,
            userId: userId,
            title: title,
            description: body,
            occurredAt: occurredAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            version: version,
            remoteId: remoteId,
            needsSync: needsSync
        )
    }
    
    func update(from domain: WorkingLogItem) {
        self.userId = domain.userId
        self.title = domain.title
        self.body = domain.description
        self.occurredAt = domain.occurredAt
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
        self.deletedAt = domain.deletedAt
        self.version = domain.version
        self.remoteId = domain.remoteId
        self.needsSync = domain.needsSync
    }
}


