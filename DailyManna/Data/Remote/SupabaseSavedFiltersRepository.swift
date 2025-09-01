//
//  SupabaseSavedFiltersRepository.swift
//  DailyManna
//
//  Created for Epic 2.2 - Saved Filters (Supabase-only)
//

import Foundation
import Supabase

final class SupabaseSavedFiltersRepository: SavedFiltersRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient = SupabaseConfig.shared.client) { self.client = client }

    func list(for userId: UUID) async throws -> [SavedFilter] {
        let dtos: [SavedFilterDTO] = try await client
            .from("saved_filters")
            .select("*")
            .eq("user_id", value: userId.uuidString)
            .is("deleted_at", value: nil)
            .order("updated_at", ascending: false)
            .execute()
            .value
        return dtos.map { $0.toDomain() }
    }

    func create(name: String, labelIds: [UUID], matchAll: Bool, userId: UUID) async throws {
        let dto = SavedFilterDTO(
            id: UUID(),
            user_id: userId,
            name: name,
            label_ids: labelIds,
            match_all: matchAll,
            created_at: Date(),
            updated_at: Date(),
            deleted_at: nil
        )
        _ = try await client
            .from("saved_filters")
            .upsert(dto, onConflict: "id")
            .select()
            .single()
            .execute()
            .value as SavedFilterDTO
    }

    func delete(id: UUID) async throws {
        _ = try await client
            .from("saved_filters")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func rename(id: UUID, to newName: String) async throws {
        _ = try await client
            .from("saved_filters")
            .update(["name": newName, "updated_at": Date().ISO8601Format()])
            .eq("id", value: id.uuidString)
            .execute()
    }
}


