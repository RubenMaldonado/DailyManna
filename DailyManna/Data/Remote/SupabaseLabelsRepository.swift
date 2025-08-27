//
//  SupabaseLabelsRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Supabase

final class SupabaseLabelsRepository: RemoteLabelsRepository {
    private let client: SupabaseClient
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) {
        self.client = client
    }
    
    func createLabel(_ label: Label) async throws -> Label {
        let dto = LabelDTO.from(domain: label)
        
        let response: LabelDTO = try await client
            .from("labels")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        
        Logger.shared.info("Created label remotely: \(label.id)", category: .data)
        return response.toDomain()
    }
    
    func fetchLabels(since lastSync: Date? = nil) async throws -> [Label] {
        var query = client
            .from("labels")
            .select("*")
        
        if let lastSync = lastSync {
            query = query.gte("updated_at", value: lastSync.ISO8601Format())
        }
        
        let response: [LabelDTO] = try await query
            .execute()
            .value
        
        let labels = response.map { $0.toDomain() }
        Logger.shared.info("Fetched \(labels.count) labels since \(lastSync?.description ?? "beginning")", category: .data)
        return labels
    }
    
    func updateLabel(_ label: Label) async throws -> Label {
        let dto = LabelDTO.from(domain: label)
        
        let response: LabelDTO = try await client
            .from("labels")
            .update(dto)
            .eq("id", value: label.id.uuidString)
            .select()
            .single()
            .execute()
            .value
        
        Logger.shared.info("Updated label remotely: \(label.id)", category: .data)
        return response.toDomain()
    }
    
    func deleteLabel(id: UUID) async throws {
        try await client
            .from("labels")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("id", value: id.uuidString)
            .execute()
        
        Logger.shared.info("Deleted label remotely: \(id)", category: .data)
    }
    
    func syncLabels(_ labels: [Label]) async throws -> [Label] {
        var syncedLabels: [Label] = []
        
        for label in labels {
            do {
                let syncedLabel: Label
                if label.remoteId == nil {
                    // Create new label
                    syncedLabel = try await createLabel(label)
                } else {
                    // Update existing label
                    syncedLabel = try await updateLabel(label)
                }
                syncedLabels.append(syncedLabel)
            } catch {
                Logger.shared.error("Failed to sync label \(label.id)", category: .data, error: error)
                throw error
            }
        }
        
        Logger.shared.info("Synced \(syncedLabels.count) labels", category: .data)
        return syncedLabels
    }
    
    // MARK: - Realtime (no-op baseline)
    func startRealtime(userId: UUID) async throws {
        Logger.shared.info("Realtime start requested for labels (user: \(userId))", category: .data)
    }
    
    func stopRealtime() async {
        Logger.shared.info("Realtime stop requested for labels", category: .data)
    }
    
    func deleteAll(for userId: UUID) async throws {
        try await client
            .from("labels")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("user_id", value: userId.uuidString)
            .execute()
        Logger.shared.info("Bulk deleted labels remotely for user: \(userId)", category: .data)
    }
}
