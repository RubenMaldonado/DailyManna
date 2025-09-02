import Foundation

final class RecurrenceUseCases {
    private let local: RecurrencesRepository
    private let remote: SupabaseRecurrencesRepository
    private let engine = RecurrenceEngine()

    init(local: RecurrencesRepository, remote: SupabaseRecurrencesRepository) {
        self.local = local
        self.remote = remote
    }

    func list(for userId: UUID) async throws -> [Recurrence] { try await local.list(for: userId) }
    func getByTaskTemplateId(_ taskId: UUID, userId: UUID) async throws -> Recurrence? { try await local.getByTaskTemplateId(taskId, userId: userId) }

    func create(_ recurrence: Recurrence) async throws {
        Logger.shared.info("Create recurrence for template=\(recurrence.taskTemplateId)", category: .domain)
        try await local.create(recurrence)
        _ = try? await remote.upsert(recurrence)
    }

    func update(_ recurrence: Recurrence) async throws {
        Logger.shared.info("Update recurrence id=\(recurrence.id) status=\(recurrence.status)", category: .domain)
        try await local.update(recurrence)
        _ = try? await remote.upsert(recurrence)
    }

    func delete(id: UUID) async throws {
        Logger.shared.info("Delete recurrence id=\(id)", category: .domain)
        try await local.delete(id: id)
        try? await remote.softDelete(id: id)
    }

    func nextOccurrence(from anchor: Date, rule: RecurrenceRule) -> Date? {
        engine.nextOccurrence(from: anchor, rule: rule)
    }
}


