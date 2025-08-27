//
//  SyncStateEntity.swift
//  DailyManna
//
//  Created for Epic 1.3 (Basic Sync)
//

import Foundation
import SwiftData

/// SwiftData model to persist per-user sync checkpoints
@Model
final class SyncStateEntity {
    @Attribute(.unique) var userId: UUID
    var lastTasksSyncAt: Date?
    var lastLabelsSyncAt: Date?
    var updatedAt: Date
    
    init(
        userId: UUID,
        lastTasksSyncAt: Date? = nil,
        lastLabelsSyncAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.lastTasksSyncAt = lastTasksSyncAt
        self.lastLabelsSyncAt = lastLabelsSyncAt
        self.updatedAt = updatedAt
    }
}


