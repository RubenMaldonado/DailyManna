import Foundation

final class TemplatesUseCases {
    private let local: TemplatesRepository
    private let remote: RemoteTemplatesRepository?

    init(local: TemplatesRepository, remote: RemoteTemplatesRepository? = nil) {
        self.local = local
        self.remote = remote
    }

    func list(ownerId: UUID) async throws -> [Template] { try await local.list(ownerId: ownerId) }
    func get(id: UUID, ownerId: UUID) async throws -> Template? { try await local.get(id: id, ownerId: ownerId) }

    func create(_ template: Template) async throws {
        try await local.create(template)
        if let remoteRepo = remote {
            _ = try? await remoteRepo.upsert(template)
        }
    }

    func update(_ template: Template) async throws {
        // Load old for diff
        guard let existing = try await local.get(id: template.id, ownerId: template.ownerId) else {
            try await local.update(template)
            return
        }
        try await local.update(template)
        // Propagate changes to occurrences (today forward, non-completed)
        let prop = TemplatePropagationService()
        await prop.propagateTemplateEdit(ownerId: template.ownerId, old: existing, new: template, effectiveFrom: Date())
        if let remoteRepo = remote {
            _ = try? await remoteRepo.upsert(template)
        }
    }

    func delete(id: UUID, ownerId: UUID) async throws {
        try await local.delete(id: id, ownerId: ownerId)
        // Remote soft-delete would be handled by a status or deleted_at once added
    }

    func refreshFromRemoteIfNeeded(ownerId: UUID) async {
        guard let remoteRepo = remote else { return }
        do {
            let remoteTemplates = try await remoteRepo.list(ownerId: ownerId)
            // Upsert locally to ensure parity on new devices (iOS cold start)
            for tpl in remoteTemplates {
                if let existing = try? await local.get(id: tpl.id, ownerId: ownerId) {
                    // Only apply remote if it is newer than local to avoid clobbering fresh local edits
                    if tpl.updatedAt > existing.updatedAt {
                        try? await local.update(tpl)
                    }
                } else {
                    try? await local.create(tpl)
                }
            }
        } catch {
            Logger.shared.error("Failed remote refresh for templates", category: .sync, error: error)
        }
    }
}


