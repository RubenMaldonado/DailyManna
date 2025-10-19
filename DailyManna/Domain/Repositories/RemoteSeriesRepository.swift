import Foundation

protocol RemoteSeriesRepository {
    func upsert(_ series: Series) async throws -> Series
    func fetchByTemplateId(_ templateId: UUID) async throws -> Series?
    func softDelete(id: UUID) async throws
}


