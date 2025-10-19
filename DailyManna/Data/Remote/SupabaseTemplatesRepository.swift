import Foundation
import Supabase

final class SupabaseTemplatesRepository: RemoteTemplatesRepository {
    private let client: SupabaseClient
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) { self.client = client }
    
    func upsert(_ template: Template) async throws -> Template {
        let dto = TemplateDTO.from(domain: template)
        let response: TemplateDTO = try await client
            .from("templates")
            .upsert(dto, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
        return response.toDomain()
    }
    
    func fetch(id: UUID) async throws -> Template? {
        do {
            let dto: TemplateDTO = try await client
                .from("templates")
                .select("*")
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            return dto.toDomain()
        } catch {
            if let e = error as? PostgrestError, e.code == "PGRST116" { return nil }
            throw error
        }
    }
    
    func list(ownerId: UUID) async throws -> [Template] {
        let dtos: [TemplateDTO] = try await client
            .from("templates")
            .select("*")
            .eq("owner_id", value: ownerId.uuidString)
            .execute()
            .value
        return dtos.map { $0.toDomain() }
    }
    
    func softDelete(id: UUID) async throws {
        let _: TemplateDTO = try await client
            .from("templates")
            .update(["deleted_at": Date()])
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }
}


