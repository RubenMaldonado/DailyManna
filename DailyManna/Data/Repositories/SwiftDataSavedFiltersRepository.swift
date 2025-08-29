//
//  SwiftDataSavedFiltersRepository.swift
//  DailyManna
//
//  Created for Epic 2.1
//

import Foundation
import SwiftData

actor SwiftDataSavedFiltersRepository: SavedFiltersRepository {
    private let modelContext: ModelContext
    init(modelContext: ModelContext) { self.modelContext = modelContext }
    
    func list(for userId: UUID) async throws -> [SavedFilter] {
        let descriptor = FetchDescriptor<SavedFilterEntity>(predicate: #Predicate { $0.userId == userId })
        let entities = try modelContext.fetch(descriptor)
        return entities.map { e in SavedFilter(id: e.id, userId: e.userId, name: e.name, labelIds: e.labelIds, matchAll: e.matchAll, createdAt: e.createdAt, updatedAt: e.updatedAt) }
    }
    
    func create(name: String, labelIds: [UUID], matchAll: Bool, userId: UUID) async throws {
        let entity = SavedFilterEntity(userId: userId, name: name, labelIds: labelIds, matchAll: matchAll)
        modelContext.insert(entity)
        try modelContext.save()
    }
    
    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<SavedFilterEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
    
    func rename(id: UUID, to newName: String) async throws {
        let descriptor = FetchDescriptor<SavedFilterEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try modelContext.fetch(descriptor).first {
            entity.name = newName
            entity.updatedAt = Date()
            try modelContext.save()
        }
    }
}


