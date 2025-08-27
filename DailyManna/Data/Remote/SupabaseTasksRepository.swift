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
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) {
        self.client = client
    }
    
    func createTask(_ task: Task) async throws -> Task {
        let dto = TaskDTO.from(domain: task)
        
        let response: TaskDTO = try await client
            .from("tasks")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        
        Logger.shared.info("Created task remotely: \(task.id)", category: .data)
        return response.toDomain()
    }
    
    func fetchTasks(since lastSync: Date? = nil) async throws -> [Task] {
        var query = client
            .from("tasks")
            .select("*")
        
        if let lastSync = lastSync {
            query = query.gte("updated_at", value: lastSync.ISO8601Format())
        }
        
        let response: [TaskDTO] = try await query
            .execute()
            .value
        
        let tasks = response.map { $0.toDomain() }
        Logger.shared.info("Fetched \(tasks.count) tasks since \(lastSync?.description ?? "beginning")", category: .data)
        return tasks
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
    
    // MARK: - Realtime (no-op baseline)
    func startRealtime(userId: UUID) async throws {
        // In Epic 1.3 baseline, we enable Realtime at the table level in Studio.
        // Here we could subscribe to postgres_changes. Left as no-op stub.
        Logger.shared.info("Realtime start requested for tasks (user: \(userId))", category: .data)
    }
    
    func stopRealtime() async {
        Logger.shared.info("Realtime stop requested for tasks", category: .data)
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
