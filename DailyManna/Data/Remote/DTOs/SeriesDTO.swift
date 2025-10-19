import Foundation

struct SeriesDTO: Codable {
    let id: UUID
    let template_id: UUID
    let owner_id: UUID
    let starts_on: Date
    let ends_on: Date?
    let timezone: String
    let status: String
    let last_generated_at: Date?
    let interval_weeks: Int?
    let anchor_weekday: Int?
    let rule: RecurrenceRule?
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
}

extension SeriesDTO {
    static func from(domain: Series) -> SeriesDTO {
        SeriesDTO(
            id: domain.id,
            template_id: domain.templateId,
            owner_id: domain.ownerId,
            starts_on: domain.startsOn,
            ends_on: domain.endsOn,
            timezone: domain.timezoneIdentifier,
            status: domain.status,
            last_generated_at: domain.lastGeneratedAt,
            interval_weeks: domain.intervalWeeks,
            anchor_weekday: domain.anchorWeekday,
            rule: domain.rule,
            created_at: domain.createdAt,
            updated_at: domain.updatedAt,
            deleted_at: domain.deletedAt
        )
    }
    
    func toDomain() -> Series {
        Series(
            id: id,
            templateId: template_id,
            ownerId: owner_id,
            startsOn: starts_on,
            endsOn: ends_on,
            timezoneIdentifier: timezone,
            status: status,
            lastGeneratedAt: last_generated_at,
            intervalWeeks: interval_weeks ?? 1,
            anchorWeekday: anchor_weekday,
            rule: rule,
            createdAt: created_at,
            updatedAt: updated_at,
            deletedAt: deleted_at
        )
    }
}


