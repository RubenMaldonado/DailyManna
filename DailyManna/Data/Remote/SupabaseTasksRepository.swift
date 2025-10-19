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
    // Realtime moved to RealtimeCoordinator
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) {
        self.client = client
    }
    
    func createTask(_ task: Task) async throws -> Task {
        let dto = TaskDTO.from(domain: task)
        
        // Detect ROUTINES root templates (partial unique index exists server-side)
        let isRoutinesTemplate = dto.bucket_key == "ROUTINES" && dto.parent_task_id == nil
        let response: TaskDTO
        do {
            if isRoutinesTemplate {
                // Use plain insert; partial unique index cannot be targeted via onConflict columns in PostgREST
                response = try await client
                    .from("tasks")
                    .insert(dto)
                    .select()
                    .single()
                    .execute()
                    .value
            } else {
                // Non-templates: safe to upsert on primary key id
                response = try await client
                    .from("tasks")
                    .upsert(dto, onConflict: "id")
                    .select()
                    .single()
                    .execute()
                    .value
            }
        } catch {
            // Reconciliation path: if unique constraint still triggers (e.g., race), fetch the existing row
            if let pgError = error as? PostgrestError,
               pgError.message.contains("duplicate key value violates unique constraint"),
               isRoutinesTemplate {
                // Attempt to fetch by user + ROUTINES + root + active + exact title match
                if let existing: TaskDTO = try? await client
                    .from("tasks")
                    .select("*")
                    .eq("user_id", value: dto.user_id.uuidString)
                    .eq("bucket_key", value: "ROUTINES")
                    .is("parent_task_id", value: nil)
                    .is("deleted_at", value: nil)
                    .eq("title", value: dto.title)
                    .single()
                    .execute()
                    .value {
                    Logger.shared.info("Reconciled duplicate ROUTINES template by fetching existing row for title=\(dto.title)", category: .data)
                    return existing.toDomain()
                }
                // Fallback: try case-insensitive match
                if let existing: TaskDTO = try? await client
                    .from("tasks")
                    .select("*")
                    .eq("user_id", value: dto.user_id.uuidString)
                    .eq("bucket_key", value: "ROUTINES")
                    .is("parent_task_id", value: nil)
                    .is("deleted_at", value: nil)
                    .ilike("title", pattern: dto.title)
                    .single()
                    .execute()
                    .value {
                    Logger.shared.info("Reconciled duplicate ROUTINES template by ILIKE title match title=\(dto.title)", category: .data)
                    return existing.toDomain()
                }
            }
            // If decoding failed due to shape mismatch, try fetching by id as a fallback
            if (error as NSError).domain == NSCocoaErrorDomain || String(describing: error).contains("in the correct format") {
                if let fetched: TaskDTO = try? await client
                    .from("tasks")
                    .select("*")
                    .eq("id", value: dto.id.uuidString)
                    .single()
                    .execute()
                    .value {
                    Logger.shared.info("Recovered from create deserialization by fetching row id=\(dto.id)", category: .data)
                    return fetched.toDomain()
                }
            }
            throw error
        }
        
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
            var qFilter = client
                .from("tasks")
                .select("*")
            if let cursorDate = cursor {
                let iso = cursorDate.ISO8601Format()
                qFilter = isFirstPage ? qFilter.gte("updated_at", value: iso) : qFilter.gt("updated_at", value: iso)
            }
            let q = qFilter.order("updated_at", ascending: true).limit(pageSize)
            let page: [TaskDTO] = try await q.execute().value
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
            var qFilter = client
                .from("tasks")
                .select("*")
            if let cursorDate = cursor {
                let iso = cursorDate.ISO8601Format()
                qFilter = isFirstPage ? qFilter.gte("updated_at", value: iso) : qFilter.gt("updated_at", value: iso)
            }
            if let bucketKey { qFilter = qFilter.eq("bucket_key", value: bucketKey) }
            if let dueBy { qFilter = qFilter.lte("due_at", value: dueBy.ISO8601Format()) }
            qFilter = qFilter.is("deleted_at", value: nil)
            let q = qFilter.order("updated_at", ascending: true).limit(pageSize)
            let page: [TaskDTO] = try await q.execute().value
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
        
        let response: TaskDTO
        do {
            response = try await client
                .from("tasks")
                .update(dto)
                .eq("id", value: task.id.uuidString)
                .select()
                .single()
                .execute()
                .value
        } catch {
            // If decoding failed due to shape mismatch, fetch the row by id and proceed
            if (error as NSError).domain == NSCocoaErrorDomain || String(describing: error).contains("in the correct format") {
                if let fetched: TaskDTO = try? await client
                    .from("tasks")
                    .select("*")
                    .eq("id", value: dto.id.uuidString)
                    .single()
                    .execute()
                    .value {
                    Logger.shared.info("Recovered from update deserialization by fetching row id=\(dto.id)", category: .data)
                    return fetched.toDomain()
                }
            }
            throw error
        }
        
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
            .order("id", ascending: true)
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
                // Make per-row failures non-fatal to allow pull to proceed
                if let pgError = error as? PostgrestError,
                   pgError.message.contains("violates check constraint \"chk_routines_due_requires_parent\"") {
                    Logger.shared.error("Skipping task due to routines due/parent constraint id=\(task.id) title=\(task.title)", category: .data, error: error)
                    continue
                }
                if let pgError = error as? PostgrestError,
                   pgError.message.contains("duplicate key value violates unique constraint") {
                    Logger.shared.error("Failed to sync (duplicate) id=\(task.id) title=\(task.title)", category: .data, error: error)
                    continue
                }
                Logger.shared.error("Failed to sync task id=\(task.id) title=\(task.title)", category: .data, error: error)
                continue
            }
        }
        
        Logger.shared.info("Synced \(syncedTasks.count) tasks", category: .data)
        return syncedTasks
    }
    
    // Realtime removed from repository; handled by RealtimeCoordinator
    
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

// MARK: - Realtime helpers
// No private realtime helpers needed
