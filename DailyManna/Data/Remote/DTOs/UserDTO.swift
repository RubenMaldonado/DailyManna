//
//  UserDTO.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

struct UserDTO: Codable {
    let id: UUID
    let email: String?
    let full_name: String?
    let created_at: Date
    let updated_at: Date
    
    static func from(domain user: User) -> UserDTO {
        return UserDTO(
            id: user.id,
            email: user.email,
            full_name: user.fullName,
            created_at: user.createdAt,
            updated_at: user.updatedAt
        )
    }
    
    func toDomain() -> User {
        return User(
            id: id,
            email: email ?? "",
            fullName: full_name ?? "",
            createdAt: created_at,
            updatedAt: updated_at
        )
    }
}
