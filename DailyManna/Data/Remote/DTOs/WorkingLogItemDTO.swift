//
//  WorkingLogItemDTO.swift
//  DailyManna
//
//  DTO for Supabase working_log_items
//

import Foundation

struct WorkingLogItemDTO: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let description: String
    let occurred_at: Date
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
}

extension WorkingLogItemDTO {
    static func from(domain: WorkingLogItem) -> WorkingLogItemDTO {
        WorkingLogItemDTO(
            id: domain.id,
            user_id: domain.userId,
            title: domain.title,
            description: domain.description,
            occurred_at: domain.occurredAt,
            created_at: domain.createdAt,
            updated_at: domain.updatedAt,
            deleted_at: domain.deletedAt
        )
    }
    
    func toDomain() -> WorkingLogItem {
        WorkingLogItem(
            id: id,
            userId: user_id,
            title: title,
            description: description,
            occurredAt: occurred_at,
            createdAt: created_at,
            updatedAt: updated_at,
            deletedAt: deleted_at,
            version: 1,
            remoteId: id,
            needsSync: false
        )
    }
}


