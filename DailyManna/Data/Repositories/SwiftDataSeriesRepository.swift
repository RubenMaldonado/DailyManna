import Foundation
import SwiftData

actor SwiftDataSeriesRepository: SeriesRepository {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func list(ownerId: UUID) async throws -> [Series] {
        let descriptor = FetchDescriptor<SeriesEntity>(predicate: #Predicate { $0.ownerId == ownerId && $0.deletedAt == nil })
        return try modelContext.fetch(descriptor).map { $0.toDomainModel() }
    }
    
    func getByTemplateId(_ templateId: UUID, ownerId: UUID) async throws -> Series? {
        let descriptor = FetchDescriptor<SeriesEntity>(predicate: #Predicate { $0.templateId == templateId && $0.ownerId == ownerId && $0.deletedAt == nil })
        return try modelContext.fetch(descriptor).first?.toDomainModel()
    }
    
    func create(_ series: Series) async throws {
        let entity = SeriesEntity(from: series)
        modelContext.insert(entity)
        try modelContext.save()
    }
    
    func update(_ series: Series) async throws {
        let descriptor = FetchDescriptor<SeriesEntity>(predicate: #Predicate { $0.id == series.id })
        guard let entity = try modelContext.fetch(descriptor).first else { throw DataError.notFound("Series not found") }
        entity.update(from: series)
        try modelContext.save()
    }
    
    func delete(id: UUID, ownerId: UUID) async throws {
        let descriptor = FetchDescriptor<SeriesEntity>(predicate: #Predicate { $0.id == id && $0.ownerId == ownerId })
        guard let entity = try modelContext.fetch(descriptor).first else { throw DataError.notFound("Series not found") }
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try modelContext.save()
    }
}

private extension SeriesEntity {
    func toDomainModel() -> Series {
        let rule: RecurrenceRule? = {
            guard let data = ruleJSON else { return nil }
            return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
        }()
        return Series(
            id: id,
            templateId: templateId,
            ownerId: ownerId,
            startsOn: startsOn,
            endsOn: endsOn,
            timezoneIdentifier: timezoneIdentifier,
            status: status,
            lastGeneratedAt: lastGeneratedAt,
            intervalWeeks: intervalWeeks,
            anchorWeekday: anchorWeekday,
            rule: rule,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
    
    func update(from domain: Series) {
        self.templateId = domain.templateId
        self.ownerId = domain.ownerId
        self.startsOn = domain.startsOn
        self.endsOn = domain.endsOn
        self.timezoneIdentifier = domain.timezoneIdentifier
        self.status = domain.status
        self.lastGeneratedAt = domain.lastGeneratedAt
        self.intervalWeeks = domain.intervalWeeks
        self.anchorWeekday = domain.anchorWeekday
        self.updatedAt = domain.updatedAt
        self.deletedAt = domain.deletedAt
        self.ruleJSON = try? JSONEncoder().encode(domain.rule)
    }
    
    convenience init(from domain: Series) {
        self.init(
            id: domain.id,
            templateId: domain.templateId,
            ownerId: domain.ownerId,
            startsOn: domain.startsOn,
            endsOn: domain.endsOn,
            timezoneIdentifier: domain.timezoneIdentifier,
            status: domain.status,
            lastGeneratedAt: domain.lastGeneratedAt,
            intervalWeeks: domain.intervalWeeks,
            anchorWeekday: domain.anchorWeekday,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            deletedAt: domain.deletedAt,
            ruleJSON: try? JSONEncoder().encode(domain.rule)
        )
    }
}


