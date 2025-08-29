//
//  SavedFilterEntity.swift
//  DailyManna
//
//  Created for Epic 2.1
//

import Foundation
import SwiftData

@Model
final class SavedFilterEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var name: String
    var labelIds: [UUID]
    var matchAll: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), userId: UUID, name: String, labelIds: [UUID], matchAll: Bool, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.name = name
        self.labelIds = labelIds
        self.matchAll = matchAll
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}


