import Foundation
import SwiftData

@Model
final class RecurrenceEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var taskTemplateId: UUID
    var ruleJSON: Data // Encoded RecurrenceRule
    var status: String // "active" | "paused"
    var lastGeneratedAt: Date?
    var nextScheduledAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), userId: UUID, taskTemplateId: UUID, ruleJSON: Data, status: String = "active", lastGeneratedAt: Date? = nil, nextScheduledAt: Date? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.taskTemplateId = taskTemplateId
        self.ruleJSON = ruleJSON
        self.status = status
        self.lastGeneratedAt = lastGeneratedAt
        self.nextScheduledAt = nextScheduledAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class RecurrenceInstanceEntity {
    @Attribute(.unique) var id: UUID
    var recurrenceId: UUID
    var taskId: UUID
    var scheduledFor: Date
    var generatedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), recurrenceId: UUID, taskId: UUID, scheduledFor: Date, generatedAt: Date = Date(), createdAt: Date = Date(), updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.recurrenceId = recurrenceId
        self.taskId = taskId
        self.scheduledFor = scheduledFor
        self.generatedAt = generatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}


