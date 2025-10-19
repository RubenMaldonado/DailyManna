import Foundation
import SwiftData

actor SwiftDataTemplatesRepository: TemplatesRepository {
    private let modelContext: ModelContext
    
    /// Create a repository whose ModelContext is bound to this actor's executor
    init(modelContainer: ModelContainer) {
        let ctx = ModelContext(modelContainer)
        ctx.autosaveEnabled = true
        self.modelContext = ctx
    }
    
    func list(ownerId: UUID) async throws -> [Template] {
        let descriptor = FetchDescriptor<TemplateEntity>(predicate: #Predicate { $0.ownerId == ownerId && $0.deletedAt == nil })
        return try modelContext.fetch(descriptor).map { $0.toDomainModel() }
    }
    
    func get(id: UUID, ownerId: UUID) async throws -> Template? {
        let descriptor = FetchDescriptor<TemplateEntity>(predicate: #Predicate { $0.id == id && $0.ownerId == ownerId && $0.deletedAt == nil })
        return try modelContext.fetch(descriptor).first?.toDomainModel()
    }
    
    func create(_ template: Template) async throws {
        let entity = TemplateEntity(from: template)
        modelContext.insert(entity)
        try modelContext.save()
    }
    
    func update(_ template: Template) async throws {
        let descriptor = FetchDescriptor<TemplateEntity>(predicate: #Predicate { $0.id == template.id })
        guard let entity = try modelContext.fetch(descriptor).first else { throw DataError.notFound("Template not found") }
        entity.update(from: template)
        try modelContext.save()
    }
    
    func delete(id: UUID, ownerId: UUID) async throws {
        let descriptor = FetchDescriptor<TemplateEntity>(predicate: #Predicate { $0.id == id && $0.ownerId == ownerId })
        guard let entity = try modelContext.fetch(descriptor).first else { throw DataError.notFound("Template not found") }
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try modelContext.save()
    }
}

private extension TemplateEntity {
    func toDomainModel() -> Template {
        let labels: [UUID] = {
            guard let data = labelsDefaultJSON else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }()
        let checklist: [String] = {
            guard let data = checklistDefaultJSON else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }()
        let components: DateComponents? = {
            if let h = defaultDueHour, let m = defaultDueMinute { return DateComponents(hour: h, minute: m) }
            return nil
        }()
        return Template(
            id: id,
            ownerId: ownerId,
            name: name,
            description: templateDescription,
            labelsDefault: labels,
            checklistDefault: checklist,
            defaultBucket: TimeBucket(rawValue: defaultBucket) ?? .routines,
            defaultDueTime: components,
            priority: TaskPriority(rawValue: priorityRaw) ?? .normal,
            defaultDurationMinutes: defaultDurationMinutes,
            status: status,
            version: version,
            endAfterCount: endAfterCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
    
    func update(from domain: Template) {
        self.ownerId = domain.ownerId
        self.name = domain.name
        self.templateDescription = domain.description
        self.labelsDefaultJSON = try? JSONEncoder().encode(domain.labelsDefault)
        self.checklistDefaultJSON = try? JSONEncoder().encode(domain.checklistDefault)
        self.defaultBucket = domain.defaultBucket.rawValue
        self.defaultDueHour = domain.defaultDueTime?.hour
        self.defaultDueMinute = domain.defaultDueTime?.minute
        self.priorityRaw = domain.priority.rawValue
        self.defaultDurationMinutes = domain.defaultDurationMinutes
        self.status = domain.status
        self.version = domain.version
        self.endAfterCount = domain.endAfterCount
        self.updatedAt = domain.updatedAt
        self.deletedAt = domain.deletedAt
    }
    
    convenience init(from domain: Template) {
        self.init(
            id: domain.id,
            ownerId: domain.ownerId,
            name: domain.name,
            templateDescription: domain.description,
            labelsDefaultJSON: try? JSONEncoder().encode(domain.labelsDefault),
            checklistDefaultJSON: try? JSONEncoder().encode(domain.checklistDefault),
            defaultBucket: domain.defaultBucket.rawValue,
            defaultDueHour: domain.defaultDueTime?.hour,
            defaultDueMinute: domain.defaultDueTime?.minute,
            priorityRaw: domain.priority.rawValue,
            defaultDurationMinutes: domain.defaultDurationMinutes,
            status: domain.status,
            version: domain.version,
            endAfterCount: domain.endAfterCount,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            deletedAt: domain.deletedAt
        )
    }
}


