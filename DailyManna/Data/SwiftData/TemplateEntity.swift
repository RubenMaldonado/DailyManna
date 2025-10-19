import Foundation
import SwiftData

@Model
final class TemplateEntity {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID
    var name: String
    var templateDescription: String?
    var labelsDefaultJSON: Data? // [UUID]
    var checklistDefaultJSON: Data? // [String]
    var defaultBucket: String // TimeBucket rawValue
    var defaultDueHour: Int?
    var defaultDueMinute: Int?
    var priorityRaw: String
    var defaultDurationMinutes: Int?
    var status: String
    var version: Int
    var endAfterCount: Int?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        ownerId: UUID,
        name: String,
        templateDescription: String? = nil,
        labelsDefaultJSON: Data? = nil,
        checklistDefaultJSON: Data? = nil,
        defaultBucket: String = TimeBucket.routines.rawValue,
        defaultDueHour: Int? = nil,
        defaultDueMinute: Int? = nil,
        priorityRaw: String = TaskPriority.normal.rawValue,
        defaultDurationMinutes: Int? = nil,
        status: String = "draft",
        version: Int = 1,
        endAfterCount: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.templateDescription = templateDescription
        self.labelsDefaultJSON = labelsDefaultJSON
        self.checklistDefaultJSON = checklistDefaultJSON
        self.defaultBucket = defaultBucket
        self.defaultDueHour = defaultDueHour
        self.defaultDueMinute = defaultDueMinute
        self.priorityRaw = priorityRaw
        self.defaultDurationMinutes = defaultDurationMinutes
        self.status = status
        self.version = version
        self.endAfterCount = endAfterCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}


