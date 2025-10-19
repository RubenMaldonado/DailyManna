import Foundation

protocol RemoteTemplatesRepository {
    func upsert(_ template: Template) async throws -> Template
    func fetch(id: UUID) async throws -> Template?
    func list(ownerId: UUID) async throws -> [Template]
    func softDelete(id: UUID) async throws
}


