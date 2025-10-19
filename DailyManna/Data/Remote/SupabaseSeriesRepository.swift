import Foundation
import Supabase

final class SupabaseSeriesRepository: RemoteSeriesRepository {
    private let client: SupabaseClient
    
    init(client: SupabaseClient = SupabaseConfig.shared.client) { self.client = client }
    
    func upsert(_ series: Series) async throws -> Series {
        let dto = SeriesDTO.from(domain: series)
        let response: SeriesDTO = try await client
            .from("series")
            .upsert(dto, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
        return response.toDomain()
    }
    
    func fetchByTemplateId(_ templateId: UUID) async throws -> Series? {
        do {
            let dto: SeriesDTO = try await client
                .from("series")
                .select("*")
                .eq("template_id", value: templateId.uuidString)
                .single()
                .execute()
                .value
            return dto.toDomain()
        } catch {
            if let e = error as? PostgrestError, e.code == "PGRST116" { return nil }
            throw error
        }
    }
    
    func softDelete(id: UUID) async throws {
        let _: SeriesDTO = try await client
            .from("series")
            .update(["deleted_at": Date()])
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }
}


