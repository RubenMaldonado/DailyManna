import Foundation

final class SeriesUseCases {
    private let local: SeriesRepository
    private let remote: RemoteSeriesRepository?

    init(local: SeriesRepository, remote: RemoteSeriesRepository? = nil) {
        self.local = local
        self.remote = remote
    }

    func list(ownerId: UUID) async throws -> [Series] { try await local.list(ownerId: ownerId) }
    func getByTemplateId(_ templateId: UUID, ownerId: UUID) async throws -> Series? { try await local.getByTemplateId(templateId, ownerId: ownerId) }
    func create(_ series: Series) async throws {
        try await local.create(series)
        if let remoteRepo = remote { _ = try? await remoteRepo.upsert(series) }
    }
    func update(_ series: Series) async throws {
        try await local.update(series)
        if let remoteRepo = remote { _ = try? await remoteRepo.upsert(series) }
    }
    func delete(id: UUID, ownerId: UUID) async throws { try await local.delete(id: id, ownerId: ownerId) }
}


