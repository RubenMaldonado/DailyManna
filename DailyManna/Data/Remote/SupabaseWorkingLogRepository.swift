//
//  SupabaseWorkingLogRepository.swift
//  DailyManna
//
//  Remote repository for Working Log using Supabase
//

import Foundation
import Supabase

final class SupabaseWorkingLogRepository: RemoteWorkingLogRepository {
    private let client: SupabaseClient
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) {
        self.client = client
    }
    
    func upsert(_ item: WorkingLogItem) async throws -> WorkingLogItem {
        let dto = WorkingLogItemDTO.from(domain: item)
        let response: WorkingLogItemDTO = try await client
            .from("working_log_items")
            .upsert(dto, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
        return response.toDomain()
    }
    
    func softDelete(id: UUID) async throws {
        _ = try await client
            .from("working_log_items")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    func hardDelete(id: UUID) async throws {
        _ = try await client
            .from("working_log_items")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    func fetchItems(since lastSync: Date?) async throws -> [WorkingLogItem] {
        var query = client
            .from("working_log_items")
            .select("*")
        if let lastSync { query = query.gte("updated_at", value: lastSync.ISO8601Format()) }
        let response: [WorkingLogItemDTO] = try await query.execute().value
        return response.map { $0.toDomain() }
    }
    
    func startRealtime(userId: UUID) async throws {
        Logger.shared.info("Realtime start requested for working_log_items (user: \(userId))", category: .data)
    }
    
    func stopRealtime() async {
        Logger.shared.info("Realtime stop requested for working_log_items", category: .data)
    }
}


