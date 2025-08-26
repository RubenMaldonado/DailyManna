//
//  User.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

/// Core domain model for a user
public struct User: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let email: String
    public let fullName: String
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID,
        email: String,
        fullName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
