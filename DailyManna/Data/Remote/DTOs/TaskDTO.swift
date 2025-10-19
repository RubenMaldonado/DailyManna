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
    let position: Double?
    let parent_task_id: UUID?
    let template_id: UUID?
    let series_id: UUID?
    let title: String
    let description: String?
    let due_at: Date?
    let due_has_time: Bool?
    let occurrence_date: Date?
    let recurrence_rule: String?
    let is_completed: Bool
    let completed_at: Date?
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
    let exception_mask: [String]?
    
    static func from(domain task: Task) -> TaskDTO {
        // Guard: ROUTINES cannot have due_at unless it is a child (has parent_task_id)
        let normalizedDueAt: Date? = {
            if task.bucketKey == .routines && task.parentTaskId == nil {
                Logger.shared.info("Normalizing ROUTINES root task: clearing due_at to satisfy constraint", category: .data)
                return nil
            }
            return task.dueAt
        }()
        return TaskDTO(
            id: task.id,
            user_id: task.userId,
            bucket_key: task.bucketKey.rawValue,
            position: task.position,
            parent_task_id: task.parentTaskId,
            template_id: task.templateId,
            series_id: task.seriesId,
            title: task.title,
            description: task.description,
            due_at: normalizedDueAt,
            due_has_time: task.dueHasTime,
            occurrence_date: task.occurrenceDate,
            recurrence_rule: task.recurrenceRule,
            is_completed: task.isCompleted,
            completed_at: task.completedAt,
            created_at: task.createdAt,
            updated_at: task.updatedAt,
            deleted_at: task.deletedAt,
            exception_mask: task.exceptionMask != nil ? Array(task.exceptionMask!) : nil
        )
    }
    
    func toDomain() -> Task {
        return Task(
            id: id,
            userId: user_id,
            bucketKey: TimeBucket(rawValue: bucket_key) ?? .thisWeek,
            position: position ?? 0,
            parentTaskId: parent_task_id,
            templateId: template_id,
            seriesId: series_id,
            title: title,
            description: description,
            dueAt: due_at,
            dueHasTime: due_has_time ?? true,
            occurrenceDate: occurrence_date,
            recurrenceRule: recurrence_rule,
            // priority/reminders remain local-only until backend columns exist
            exceptionMask: exception_mask != nil ? Set(exception_mask!) : nil,
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

    private enum CodingKeys: String, CodingKey {
        case id, user_id, bucket_key, position, parent_task_id, template_id, series_id, title, description, due_at, due_has_time, occurrence_date, recurrence_rule, is_completed, completed_at, created_at, updated_at, deleted_at, exception_mask
    }

    init(
        id: UUID,
        user_id: UUID,
        bucket_key: String,
        position: Double?,
        parent_task_id: UUID?,
        template_id: UUID?,
        series_id: UUID?,
        title: String,
        description: String?,
        due_at: Date?,
        due_has_time: Bool?,
        occurrence_date: Date?,
        recurrence_rule: String?,
        is_completed: Bool,
        completed_at: Date?,
        created_at: Date,
        updated_at: Date,
        deleted_at: Date?,
        exception_mask: [String]?
    ) {
        self.id = id
        self.user_id = user_id
        self.bucket_key = bucket_key
        self.position = position
        self.parent_task_id = parent_task_id
        self.template_id = template_id
        self.series_id = series_id
        self.title = title
        self.description = description
        self.due_at = due_at
        self.due_has_time = due_has_time
        self.occurrence_date = occurrence_date
        self.recurrence_rule = recurrence_rule
        self.is_completed = is_completed
        self.completed_at = completed_at
        self.created_at = created_at
        self.updated_at = updated_at
        self.deleted_at = deleted_at
        self.exception_mask = exception_mask
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        user_id = try c.decode(UUID.self, forKey: .user_id)
        bucket_key = try c.decode(String.self, forKey: .bucket_key)
        position = try c.decodeIfPresent(Double.self, forKey: .position)
        parent_task_id = try c.decodeIfPresent(UUID.self, forKey: .parent_task_id)
        template_id = try c.decodeIfPresent(UUID.self, forKey: .template_id)
        series_id = try c.decodeIfPresent(UUID.self, forKey: .series_id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        due_at = try c.decodeIfPresent(Date.self, forKey: .due_at)
        due_has_time = try c.decodeIfPresent(Bool.self, forKey: .due_has_time)
        if let od = try? c.decodeIfPresent(Date.self, forKey: .occurrence_date) {
            occurrence_date = od
        } else if let odStr = try? c.decode(String.self, forKey: .occurrence_date) {
            // Support Postgres date (YYYY-MM-DD) for occurrence_date
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            occurrence_date = df.date(from: odStr)
        } else {
            occurrence_date = nil
        }
        recurrence_rule = try c.decodeIfPresent(String.self, forKey: .recurrence_rule)
        is_completed = try c.decode(Bool.self, forKey: .is_completed)
        completed_at = try c.decodeIfPresent(Date.self, forKey: .completed_at)
        created_at = try c.decode(Date.self, forKey: .created_at)
        updated_at = try c.decode(Date.self, forKey: .updated_at)
        deleted_at = try c.decodeIfPresent(Date.self, forKey: .deleted_at)
        // exception_mask may be stored as [] or {} in Postgres jsonb; interpret {} as empty list
        if let arr = try? c.decodeIfPresent([String].self, forKey: .exception_mask) {
            exception_mask = arr
        } else if let dict = try? c.decodeIfPresent([String: Bool].self, forKey: .exception_mask) {
            exception_mask = Array(dict.keys)
        } else if let dict = try? c.decodeIfPresent([String: String].self, forKey: .exception_mask) {
            exception_mask = Array(dict.keys)
        } else {
            exception_mask = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(user_id, forKey: .user_id)
        try c.encode(bucket_key, forKey: .bucket_key)
        try c.encodeIfPresent(position, forKey: .position)
        try c.encodeIfPresent(parent_task_id, forKey: .parent_task_id)
        try c.encodeIfPresent(template_id, forKey: .template_id)
        try c.encodeIfPresent(series_id, forKey: .series_id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(due_at, forKey: .due_at)
        try c.encodeIfPresent(due_has_time, forKey: .due_has_time)
        if let od = occurrence_date {
            // Encode as date-only string to match Postgres date type
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            try c.encode(df.string(from: od), forKey: .occurrence_date)
        }
        try c.encodeIfPresent(recurrence_rule, forKey: .recurrence_rule)
        try c.encode(is_completed, forKey: .is_completed)
        try c.encodeIfPresent(completed_at, forKey: .completed_at)
        try c.encode(created_at, forKey: .created_at)
        try c.encode(updated_at, forKey: .updated_at)
        try c.encodeIfPresent(deleted_at, forKey: .deleted_at)
        try c.encodeIfPresent(exception_mask, forKey: .exception_mask)
    }
}
