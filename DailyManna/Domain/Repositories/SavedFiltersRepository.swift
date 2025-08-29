//
//  SavedFiltersRepository.swift
//  DailyManna
//
//  Created for Epic 2.1
//

import Foundation

public struct SavedFilter: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let userId: UUID
    public var name: String
    public var labelIds: [UUID]
    public var matchAll: Bool
    public var createdAt: Date
    public var updatedAt: Date
}

protocol SavedFiltersRepository {
    func list(for userId: UUID) async throws -> [SavedFilter]
    func create(name: String, labelIds: [UUID], matchAll: Bool, userId: UUID) async throws
    func delete(id: UUID) async throws
    func rename(id: UUID, to newName: String) async throws
}


