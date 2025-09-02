import Foundation

public struct Recurrence: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let userId: UUID
    public let taskTemplateId: UUID
    public var rule: RecurrenceRule
    public var status: String // active|paused
    public var lastGeneratedAt: Date?
    public var nextScheduledAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), userId: UUID, taskTemplateId: UUID, rule: RecurrenceRule, status: String = "active", lastGeneratedAt: Date? = nil, nextScheduledAt: Date? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.taskTemplateId = taskTemplateId
        self.rule = rule
        self.status = status
        self.lastGeneratedAt = lastGeneratedAt
        self.nextScheduledAt = nextScheduledAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}


