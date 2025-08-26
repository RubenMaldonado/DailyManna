//
//  LabelEntity.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// SwiftData model for Label entities
@Model
final class LabelEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var name: String
    var color: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    
    // Sync metadata
    var version: Int
    var remoteId: UUID?
    var needsSync: Bool
    
    // Note: Label-task relationships are handled through TaskLabelEntity junction table
    // Relationships are managed through repository queries to avoid SwiftData circular references
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        color: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        version: Int = 1,
        remoteId: UUID? = nil,
        needsSync: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
        self.remoteId = remoteId
        self.needsSync = needsSync
    }
    
    // MARK: - Mappers
    
    func toDomainModel() -> Label {
        Label(
            id: id,
            userId: userId,
            name: name,
            color: color,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            version: version,
            remoteId: remoteId,
            needsSync: needsSync
        )
    }
    
    func update(from domain: Label) {
        self.userId = domain.userId
        self.name = domain.name
        self.color = domain.color
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
        self.deletedAt = domain.deletedAt
        self.version = domain.version
        self.remoteId = domain.remoteId
        self.needsSync = domain.needsSync
    }
}

// MARK: - Mapper Extension
extension LabelEntity {
    convenience init(from domain: Label) {
        self.init(
            id: domain.id,
            userId: domain.userId,
            name: domain.name,
            color: domain.color,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            deletedAt: domain.deletedAt,
            version: domain.version,
            remoteId: domain.remoteId,
            needsSync: domain.needsSync
        )
    }
}
