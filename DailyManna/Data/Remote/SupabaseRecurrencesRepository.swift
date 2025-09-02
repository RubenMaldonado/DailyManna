import Foundation
import Supabase

final class SupabaseRecurrencesRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient = SupabaseConfig.shared.client) { self.client = client }

    struct RecurrenceDTO: Codable {
        let id: UUID
        let user_id: UUID
        let task_template_id: UUID
        let rule: RecurrenceRule
        let status: String
        let last_generated_at: Date?
        let next_scheduled_at: Date?
        let created_at: Date
        let updated_at: Date
        let deleted_at: Date?

        func toDomain() -> Recurrence {
            Recurrence(id: id, userId: user_id, taskTemplateId: task_template_id, rule: rule, status: status, lastGeneratedAt: last_generated_at, nextScheduledAt: next_scheduled_at, createdAt: created_at, updatedAt: updated_at, deletedAt: deleted_at)
        }
    }

    func list(for userId: UUID) async throws -> [Recurrence] {
        let dtos: [RecurrenceDTO] = try await client
            .from("recurrences")
            .select("*")
            .eq("user_id", value: userId.uuidString)
            .is("deleted_at", value: nil)
            .execute()
            .value
        return dtos.map { $0.toDomain() }
    }

    func upsert(_ recurrence: Recurrence) async throws -> Recurrence {
        let dto = RecurrenceDTO(id: recurrence.id, user_id: recurrence.userId, task_template_id: recurrence.taskTemplateId, rule: recurrence.rule, status: recurrence.status, last_generated_at: recurrence.lastGeneratedAt, next_scheduled_at: recurrence.nextScheduledAt, created_at: recurrence.createdAt, updated_at: recurrence.updatedAt, deleted_at: recurrence.deletedAt)
        let value: RecurrenceDTO = try await client
            .from("recurrences")
            .upsert(dto, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
        return value.toDomain()
    }

    func softDelete(id: UUID) async throws {
        _ = try await client
            .from("recurrences")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("id", value: id.uuidString)
            .execute()
    }
}


