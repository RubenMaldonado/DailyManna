//
//  TaskDraft.swift
//  DailyManna
//
//  Created for Epic 1.2
//

import Foundation

struct TaskDraft: Identifiable, Equatable {
    let id: UUID
    var userId: UUID
    var bucket: TimeBucket
    var title: String
    var description: String?
    var dueAt: Date?
    
    init(id: UUID = UUID(), userId: UUID, bucket: TimeBucket, title: String = "", description: String? = nil, dueAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.bucket = bucket
        self.title = title
        self.description = description
        self.dueAt = dueAt
    }
}

extension TaskDraft {
    init(from task: Task) {
        self.init(id: task.id, userId: task.userId, bucket: task.bucketKey, title: task.title, description: task.description, dueAt: task.dueAt)
    }
    
    func toNewTask() -> Task {
        Task(userId: userId, bucketKey: bucket, title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: description?.trimmingCharacters(in: .whitespacesAndNewlines), dueAt: dueAt)
    }
    
    func applying(to task: Task) -> Task {
        var updated = task
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.dueAt = dueAt
        updated.bucketKey = bucket
        updated.updatedAt = Date()
        return updated
    }
}


