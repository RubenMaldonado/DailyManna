//
//  SavedFilterDTO.swift
//  DailyManna
//
//  Created for Epic 2.2 - Saved Filters
//

import Foundation

struct SavedFilterDTO: Codable {
    let id: UUID
    let user_id: UUID
    let name: String
    let label_ids: [UUID]
    let match_all: Bool
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?

    func toDomain() -> SavedFilter {
        SavedFilter(
            id: id,
            userId: user_id,
            name: name,
            labelIds: label_ids,
            matchAll: match_all,
            createdAt: created_at,
            updatedAt: updated_at
        )
    }

    static func from(domain: SavedFilter) -> SavedFilterDTO {
        SavedFilterDTO(
            id: domain.id,
            user_id: domain.userId,
            name: domain.name,
            label_ids: domain.labelIds,
            match_all: domain.matchAll,
            created_at: domain.createdAt,
            updated_at: domain.updatedAt,
            deleted_at: nil
        )
    }
}


