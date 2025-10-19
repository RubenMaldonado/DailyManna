import Foundation
import SwiftData

@Model
final class SeriesEntity {
    @Attribute(.unique) var id: UUID
    var templateId: UUID
    var ownerId: UUID
    var startsOn: Date
    var endsOn: Date?
    var timezoneIdentifier: String
    var status: String
    var lastGeneratedAt: Date?
    var intervalWeeks: Int
    var anchorWeekday: Int?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var ruleJSON: Data?

    init(
        id: UUID = UUID(),
        templateId: UUID,
        ownerId: UUID,
        startsOn: Date,
        endsOn: Date? = nil,
        timezoneIdentifier: String,
        status: String = "active",
        lastGeneratedAt: Date? = nil,
        intervalWeeks: Int = 1,
        anchorWeekday: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        ruleJSON: Data? = nil
    ) {
        self.id = id
        self.templateId = templateId
        self.ownerId = ownerId
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.timezoneIdentifier = timezoneIdentifier
        self.status = status
        self.lastGeneratedAt = lastGeneratedAt
        self.intervalWeeks = intervalWeeks
        self.anchorWeekday = anchorWeekday
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.ruleJSON = ruleJSON
    }
}


