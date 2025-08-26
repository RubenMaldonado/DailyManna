//
//  Label.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftUI

/// Core domain model for a task label
public struct Label: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let userId: UUID
    public var name: String
    public var color: String // Hex color string or predefined name
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
    
    public var isDeleted: Bool {
        deletedAt != nil
    }
    
    public var uiColor: Color {
        Color(hex: color) ?? .gray
    }
}

// Helper for Color from hex string
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
