import Foundation
import SwiftData

protocol RecurrencesRepository: Sendable {
    func list(for userId: UUID) async throws -> [Recurrence]
    func getByTaskTemplateId(_ taskId: UUID, userId: UUID) async throws -> Recurrence?
    func create(_ recurrence: Recurrence) async throws
    func update(_ recurrence: Recurrence) async throws
    func delete(id: UUID) async throws
}

actor SwiftDataRecurrencesRepository: RecurrencesRepository {
    private let modelContext: ModelContext
    init(modelContainer: ModelContainer) {
        let ctx = ModelContext(modelContainer)
        ctx.autosaveEnabled = true
        self.modelContext = ctx
    }

    func list(for userId: UUID) async throws -> [Recurrence] {
        let descriptor = FetchDescriptor<RecurrenceEntity>(predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil })
        let entities = try modelContext.fetch(descriptor)
        return entities.compactMap { e in
            guard let rule = try? JSONDecoder().decode(RecurrenceRule.self, from: e.ruleJSON) else { return nil }
            return Recurrence(id: e.id, userId: e.userId, taskTemplateId: e.taskTemplateId, rule: rule, status: e.status, lastGeneratedAt: e.lastGeneratedAt, nextScheduledAt: e.nextScheduledAt, createdAt: e.createdAt, updatedAt: e.updatedAt, deletedAt: e.deletedAt)
        }
    }

    func create(_ recurrence: Recurrence) async throws {
        let data = try JSONEncoder().encode(recurrence.rule)
        let entity = RecurrenceEntity(id: recurrence.id, userId: recurrence.userId, taskTemplateId: recurrence.taskTemplateId, ruleJSON: data, status: recurrence.status, lastGeneratedAt: recurrence.lastGeneratedAt, nextScheduledAt: recurrence.nextScheduledAt, createdAt: recurrence.createdAt, updatedAt: recurrence.updatedAt, deletedAt: recurrence.deletedAt)
        modelContext.insert(entity)
        try modelContext.save()
    }

    func getByTaskTemplateId(_ taskId: UUID, userId: UUID) async throws -> Recurrence? {
        let descriptor = FetchDescriptor<RecurrenceEntity>(predicate: #Predicate { $0.userId == userId && $0.taskTemplateId == taskId && $0.deletedAt == nil })
        if let e = try modelContext.fetch(descriptor).first, let rule = try? JSONDecoder().decode(RecurrenceRule.self, from: e.ruleJSON) {
            return Recurrence(id: e.id, userId: e.userId, taskTemplateId: e.taskTemplateId, rule: rule, status: e.status, lastGeneratedAt: e.lastGeneratedAt, nextScheduledAt: e.nextScheduledAt, createdAt: e.createdAt, updatedAt: e.updatedAt, deletedAt: e.deletedAt)
        }
        return nil
    }

    func update(_ recurrence: Recurrence) async throws {
        let descriptor = FetchDescriptor<RecurrenceEntity>(predicate: #Predicate { $0.id == recurrence.id })
        if let e = try modelContext.fetch(descriptor).first {
            e.ruleJSON = try JSONEncoder().encode(recurrence.rule)
            e.status = recurrence.status
            e.lastGeneratedAt = recurrence.lastGeneratedAt
            e.nextScheduledAt = recurrence.nextScheduledAt
            e.updatedAt = Date()
            try modelContext.save()
        }
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<RecurrenceEntity>(predicate: #Predicate { $0.id == id })
        if let e = try modelContext.fetch(descriptor).first {
            e.deletedAt = Date()
            try modelContext.save()
        }
    }
}


