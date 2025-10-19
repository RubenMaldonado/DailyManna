import Foundation

protocol SeriesRepository {
    func list(ownerId: UUID) async throws -> [Series]
    func getByTemplateId(_ templateId: UUID, ownerId: UUID) async throws -> Series?
    func create(_ series: Series) async throws
    func update(_ series: Series) async throws
    func delete(id: UUID, ownerId: UUID) async throws
}


