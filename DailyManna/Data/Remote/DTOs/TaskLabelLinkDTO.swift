//
//  TaskLabelLinkDTO.swift
//  DailyManna
//
//  Created for Epic 2.1 (Labels & Filtering)
//

import Foundation

struct TaskLabelLinkDTO: Codable {
    let id: UUID
    let task_id: UUID
    let label_id: UUID
    let user_id: UUID
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?

    static func from(domain link: TaskLabelLink) -> TaskLabelLinkDTO {
        TaskLabelLinkDTO(
            id: link.id,
            task_id: link.taskId,
            label_id: link.labelId,
            user_id: link.userId,
            created_at: link.createdAt,
            updated_at: link.updatedAt,
            deleted_at: link.deletedAt
        )
    }

    func toDomain() -> TaskLabelLink {
        TaskLabelLink(
            id: id,
            taskId: task_id,
            labelId: label_id,
            userId: user_id,
            createdAt: created_at,
            updatedAt: updated_at,
            deletedAt: deleted_at,
            needsSync: false,
            remoteId: id,
            version: 1
        )
    }
}


