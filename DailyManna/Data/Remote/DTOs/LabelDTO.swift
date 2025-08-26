//
//  LabelDTO.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

struct LabelDTO: Codable {
    let id: UUID
    let user_id: UUID
    let name: String
    let color: String
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
    
    static func from(domain label: Label) -> LabelDTO {
        return LabelDTO(
            id: label.id,
            user_id: label.userId,
            name: label.name,
            color: label.color,
            created_at: label.createdAt,
            updated_at: label.updatedAt,
            deleted_at: label.deletedAt
        )
    }
    
    func toDomain() -> Label {
        return Label(
            id: id,
            userId: user_id,
            name: name,
            color: color,
            createdAt: created_at,
            updatedAt: updated_at,
            deletedAt: deleted_at
        )
    }
}
