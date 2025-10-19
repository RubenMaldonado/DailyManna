//
//  Series.swift
//  DailyManna
//
//  One-to-one series per template controlling weekly generation.
//

import Foundation

public struct Series: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public let templateId: UUID
    public let ownerId: UUID
    public var startsOn: Date // date-only semantics
    public var endsOn: Date?
    public var timezoneIdentifier: String // IANA TZ, from user
    public var status: String // active|paused
    public var lastGeneratedAt: Date?
    public var intervalWeeks: Int // weekly interval, default 1
    public var anchorWeekday: Int? // 1-7 (Calendar.current)
    public var rule: RecurrenceRule? // Optional rule for non-weekly schedules (monthly/yearly, etc.)
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
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
        rule: RecurrenceRule? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
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
        self.rule = rule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}


