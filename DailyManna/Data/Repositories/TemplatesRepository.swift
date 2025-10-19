import Foundation

protocol TemplatesRepository {
    func list(ownerId: UUID) async throws -> [Template]
    func get(id: UUID, ownerId: UUID) async throws -> Template?
    func create(_ template: Template) async throws
    func update(_ template: Template) async throws
    func delete(id: UUID, ownerId: UUID) async throws
}


