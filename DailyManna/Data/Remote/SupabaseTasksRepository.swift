//
//  SupabaseTasksRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Supabase

final class SupabaseTasksRepository: RemoteTasksRepository {
    private let client: SupabaseClient
    private var tasksChannel: RealtimeChannelV2?
    private var tasksChangesTask: _Concurrency.Task<Void, Never>?
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) {
        self.client = client
    }
    
    func createTask(_ task: Task) async throws -> Task {
        let dto = TaskDTO.from(domain: task)
        
        let response: TaskDTO = try await client
            .from("tasks")
            // Use primary key upsert to avoid duplicate key errors when a task
            // with the same id was previously created (e.g., after retries)
            .upsert(dto, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
        
        Logger.shared.info("Created task remotely: \(task.id)", category: .data)
        return response.toDomain()
    }
    
    func fetchTask(id: UUID) async throws -> Task? {
        do {
            let dto: TaskDTO = try await client
                .from("tasks")
                .select("*")
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            return dto.toDomain()
        } catch {
            // If not found, return nil; otherwise, propagate
            if let supaError = error as? PostgrestError, supaError.code == "PGRST116" { // No rows
                return nil
            }
            throw error
        }
    }
    
    func fetchTasks(since lastSync: Date? = nil) async throws -> [Task] {
        let pageSize = 500
        var all: [Task] = []
        var cursor = lastSync
        var isFirstPage = true
        while true {
            var query = client
                .from("tasks")
                .select("*")
                .order("updated_at", ascending: true)
                .limit(pageSize)
            if let cursorDate = cursor {
                let iso = cursorDate.ISO8601Format()
                query = isFirstPage ? query.gte("updated_at", value: iso) : query.gt("updated_at", value: iso)
            }
            let page: [TaskDTO] = try await query.execute().value
            if page.isEmpty { break }
            all.append(contentsOf: page.map { $0.toDomain() })
            if page.count < pageSize { break }
            cursor = page.last?.updated_at
            isFirstPage = false
        }
        Logger.shared.info("Fetched (paged) \(all.count) tasks since \(lastSync?.description ?? "beginning")", category: .data)
        return all
    }
    
    func fetchTasks(since lastSync: Date?, bucketKey: String?, dueBy: Date?) async throws -> [Task] {
        let pageSize = 500
        var all: [Task] = []
        var cursor = lastSync
        var isFirstPage = true
        while true {
            var query = client
                .from("tasks")
                .select("*")
                .order("updated_at", ascending: true)
                .limit(pageSize)
            if let cursorDate = cursor {
                let iso = cursorDate.ISO8601Format()
                query = isFirstPage ? query.gte("updated_at", value: iso) : query.gt("updated_at", value: iso)
            }
            if let bucketKey { query = query.eq("bucket_key", value: bucketKey) }
            if let dueBy { query = query.lte("due_at", value: dueBy.ISO8601Format()) }
            query = query.is("deleted_at", value: nil)
            let page: [TaskDTO] = try await query.execute().value
            if page.isEmpty { break }
            all.append(contentsOf: page.map { $0.toDomain() })
            if page.count < pageSize { break }
            cursor = page.last?.updated_at
            isFirstPage = false
        }
        Logger.shared.info("Fetched (paged ctx) \(all.count) tasks since=\(lastSync?.description ?? "nil") bucket=\(bucketKey ?? "nil") dueBy=\(dueBy?.description ?? "nil")", category: .data)
        return all
    }
    
    func updateTask(_ task: Task) async throws -> Task {
        let dto = TaskDTO.from(domain: task)
        
        let response: TaskDTO = try await client
            .from("tasks")
            .update(dto)
            .eq("id", value: task.id.uuidString)
            .select()
            .single()
            .execute()
            .value
        
        Logger.shared.info("Updated task remotely: \(task.id)", category: .data)
        return response.toDomain()
    }
    
    func deleteTask(id: UUID) async throws {
        try await client
            .from("tasks")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("id", value: id.uuidString)
            .execute()
        
        Logger.shared.info("Deleted task remotely: \(id)", category: .data)
    }
    
    func fetchTasksForBucket(_ bucketKey: String) async throws -> [Task] {
        let response: [TaskDTO] = try await client
            .from("tasks")
            .select("*")
            .eq("bucket_key", value: bucketKey)
            .is("deleted_at", value: nil)
            .order("position", ascending: true)
            .order("created_at", ascending: true)
            .execute()
            .value
        
        let tasks = response.map { $0.toDomain() }
        Logger.shared.info("Fetched \(tasks.count) tasks for bucket: \(bucketKey)", category: .data)
        return tasks
    }
    
    func syncTasks(_ tasks: [Task]) async throws -> [Task] {
        var syncedTasks: [Task] = []
        
        for task in tasks {
            do {
                let syncedTask: Task
                if task.remoteId == nil {
                    // Create new task
                    syncedTask = try await createTask(task)
                } else {
                    // Update existing task
                    syncedTask = try await updateTask(task)
                }
                syncedTasks.append(syncedTask)
            } catch {
                Logger.shared.error("Failed to sync task \(task.id)", category: .data, error: error)
                throw error
            }
        }
        
        Logger.shared.info("Synced \(syncedTasks.count) tasks", category: .data)
        return syncedTasks
    }
    
    // MARK: - Realtime (targeted upserts)
    func startRealtime(userId: UUID) async throws {
        Logger.shared.info("Realtime start requested for tasks (user: \(userId))", category: .data)
        // Subscribe to table changes for hinting sync using RealtimeChannelV2 async stream API
        let channel = client.channel("dm_tasks_\(userId.uuidString)")
        self.tasksChannel = channel
        // postgresChange returns an async stream immediately; no need to await its creation
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "tasks", filter: .eq("user_id", value: userId.uuidString))
        do {
            try await channel.subscribeWithError()
        } catch {
            Logger.shared.error("Realtime subscribe failed", category: .data, error: error)
        }
        // Consume the async stream and post targeted notifications including id + action
        tasksChangesTask?.cancel()
        tasksChangesTask = _Concurrency.Task<Void, Never> { @MainActor in
            for await event in changes {
                // Expect payloads to include primary key `id` and `updated_at`
                if let idString = event.record?["id"] as? String, let id = UUID(uuidString: idString) {
                    let action = event.type.rawValue
                    let userInfo: [AnyHashable: Any] = [
                        "id": id,
                        "action": action
                    ]
                    NotificationCenter.default.post(name: Notification.Name("dm.remote.tasks.changed.targeted"), object: nil, userInfo: userInfo)
                } else {
                    // Fallback to coarse hint if payload missing
                    NotificationCenter.default.post(name: Notification.Name("dm.remote.tasks.changed"), object: nil)
                }
            }
        }
    }
    
    func stopRealtime() async {
        Logger.shared.info("Realtime stop requested for tasks", category: .data)
        tasksChangesTask?.cancel()
        tasksChangesTask = nil
        // Best-effort unsubscribe if available
        _ = tasksChannel
        tasksChannel = nil
    }
    
    func deleteAll(for userId: UUID) async throws {
        // Soft-delete all tasks by setting deleted_at where user_id matches
        try await client
            .from("tasks")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("user_id", value: userId.uuidString)
            .execute()
        Logger.shared.info("Bulk deleted tasks remotely for user: \(userId)", category: .data)
    }
}
