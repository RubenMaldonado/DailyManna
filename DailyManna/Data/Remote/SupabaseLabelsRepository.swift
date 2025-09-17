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
    private var labelsChannel: RealtimeChannelV2?
    private var labelsChangesTask: _Concurrency.Task<Void, Never>?
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) {
        self.client = client
    }
    
    func createLabel(_ label: Label) async throws -> Label {
        let dto = LabelDTO.from(domain: label)
        
        // Upsert with ON CONFLICT (user_id,name) to revive tombstoned row and update color/name
        // Use primary key upsert to avoid dependency on a composite unique constraint
        let response: LabelDTO = try await client
            .from("labels")
            .upsert(dto, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
        
        Logger.shared.info("Created label remotely: \(label.id)", category: .data)
        return response.toDomain()
    }
    
    func fetchLabels(since lastSync: Date? = nil) async throws -> [Label] {
        let pageSize = 500
        var all: [Label] = []
        var cursor = lastSync
        var isFirstPage = true
        while true {
            var qFilter = client
                .from("labels")
                .select("*")
            if let cursorDate = cursor {
                let iso = cursorDate.ISO8601Format()
                qFilter = isFirstPage ? qFilter.gte("updated_at", value: iso) : qFilter.gt("updated_at", value: iso)
            }
            let qOrdered = qFilter.order("updated_at", ascending: true).limit(pageSize)
            let page: [LabelDTO] = try await qOrdered.execute().value
            if page.isEmpty { break }
            all.append(contentsOf: page.map { $0.toDomain() })
            if page.count < pageSize { break }
            cursor = page.last?.updated_at
            isFirstPage = false
        }
        Logger.shared.info("Fetched (paged) \(all.count) labels since \(lastSync?.description ?? "beginning")", category: .data)
        return all
    }

    func fetchLabel(id: UUID) async throws -> Label? {
        do {
            let dto: LabelDTO = try await client
                .from("labels")
                .select("*")
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            return dto.toDomain()
        } catch {
            if let supaError = error as? PostgrestError, supaError.code == "PGRST116" {
                return nil
            }
            throw error
        }
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

    // MARK: - Task Labels (junction)
    func link(_ link: TaskLabelLink) async throws {
        // Use primary key upsert to avoid dependency on composite unique constraints
        let dto = TaskLabelLinkDTO.from(domain: link)
        let _: [TaskLabelLinkDTO] = try await client
            .from("task_labels")
            .upsert(dto, onConflict: "id")
            .select()
            .execute()
            .value
    }

    func unlink(taskId: UUID, labelId: UUID) async throws {
        _ = try await client
            .from("task_labels")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("task_id", value: taskId.uuidString)
            .eq("label_id", value: labelId.uuidString)
            .execute()
    }

    func fetchTaskLabelLinks(since lastSync: Date?) async throws -> [TaskLabelLink] {
        var query = client
            .from("task_labels")
            .select("*")
        if let lastSync { query = query.gte("updated_at", value: lastSync.ISO8601Format()) }
        let response: [TaskLabelLinkDTO] = try await query.execute().value
        return response.map { $0.toDomain() }
    }
    
    // MARK: - Realtime (targeted upserts)
    func startRealtime(userId: UUID) async throws {
        Logger.shared.info("Realtime start requested for labels (user: \(userId))", category: .data)
        let channel = client.channel("dm_labels_\(userId.uuidString)")
        self.labelsChannel = channel
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "labels", filter: .eq("user_id", value: userId.uuidString))
        do {
            try await channel.subscribeWithError()
        } catch {
            Logger.shared.error("Realtime subscribe failed (labels)", category: .data, error: error)
        }
        labelsChangesTask?.cancel()
        labelsChangesTask = _Concurrency.Task<Void, Never> { @MainActor in
            for await event in changes {
                if let idString = event.record?["id"] as? String, let id = UUID(uuidString: idString) {
                    let action = event.type.rawValue
                    NotificationCenter.default.post(name: Notification.Name("dm.remote.labels.changed.targeted"), object: nil, userInfo: ["id": id, "action": action])
                } else {
                    NotificationCenter.default.post(name: Notification.Name("dm.remote.labels.changed"), object: nil)
                }
            }
        }
    }
    
    func stopRealtime() async {
        Logger.shared.info("Realtime stop requested for labels", category: .data)
        labelsChangesTask?.cancel()
        labelsChangesTask = nil
        _ = labelsChannel
        labelsChannel = nil
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
