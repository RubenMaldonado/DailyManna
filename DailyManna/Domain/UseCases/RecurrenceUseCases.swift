import Foundation

public final class RecurrenceUseCases {
    private let local: RecurrencesRepository
    private let remote: SupabaseRecurrencesRepository
    private let engine = RecurrenceEngine()

    public init(local: RecurrencesRepository, remote: SupabaseRecurrencesRepository) {
        self.local = local
        self.remote = remote
    }

    public func list(for userId: UUID) async throws -> [Recurrence] { try await local.list(for: userId) }
    public func getByTaskTemplateId(_ taskId: UUID, userId: UUID) async throws -> Recurrence? { try await local.getByTaskTemplateId(taskId, userId: userId) }

    public func create(_ recurrence: Recurrence) async throws {
        Logger.shared.info("Create recurrence for template=\(recurrence.taskTemplateId)", category: .domain)
        try await local.create(recurrence)
        _ = try? await remote.upsert(recurrence)
    }

    public func update(_ recurrence: Recurrence) async throws {
        Logger.shared.info("Update recurrence id=\(recurrence.id) status=\(recurrence.status)", category: .domain)
        try await local.update(recurrence)
        _ = try? await remote.upsert(recurrence)
    }

    public func delete(id: UUID) async throws {
        Logger.shared.info("Delete recurrence id=\(id)", category: .domain)
        try await local.delete(id: id)
        try? await remote.softDelete(id: id)
    }

    public func nextOccurrence(from anchor: Date, rule: RecurrenceRule) -> Date? {
        engine.nextOccurrence(from: anchor, rule: rule)
    }
}


