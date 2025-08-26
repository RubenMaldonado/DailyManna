//
//  TaskDTO.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

struct TaskDTO: Codable {
    let id: UUID
    let user_id: UUID
    let bucket_key: String
    let parent_task_id: UUID?
    let title: String
    let description: String?
    let due_at: Date?
    let recurrence_rule: String?
    let is_completed: Bool
    let completed_at: Date?
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
    
    static func from(domain task: Task) -> TaskDTO {
        return TaskDTO(
            id: task.id,
            user_id: task.userId,
            bucket_key: task.bucketKey.rawValue,
            parent_task_id: task.parentTaskId,
            title: task.title,
            description: task.description,
            due_at: task.dueAt,
            recurrence_rule: task.recurrenceRule,
            is_completed: task.isCompleted,
            completed_at: task.completedAt,
            created_at: task.createdAt,
            updated_at: task.updatedAt,
            deleted_at: task.deletedAt
        )
    }
    
    func toDomain() -> Task {
        return Task(
            id: id,
            userId: user_id,
            bucketKey: TimeBucket(rawValue: bucket_key) ?? .thisWeek,
            parentTaskId: parent_task_id,
            title: title,
            description: description,
            dueAt: due_at,
            recurrenceRule: recurrence_rule,
            isCompleted: is_completed,
            completedAt: completed_at,
            createdAt: created_at,
            updatedAt: updated_at,
            deletedAt: deleted_at,
            version: 1,
            remoteId: id,
            needsSync: false
        )
    }
}
