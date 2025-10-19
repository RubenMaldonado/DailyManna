import Foundation

/// Applies template edits to non-completed occurrences from today forward, skipping fields in exceptionMask
actor TemplatePropagationService {
    func propagateTemplateEdit(ownerId: UUID, old: Template, new: Template, effectiveFrom: Date) async {
        let deps = Dependencies.shared
        guard let tasksRepo = try? deps.resolve(type: TasksRepository.self) else { return }
        let taskUC = try? TaskUseCases(
            tasksRepository: deps.resolve(type: TasksRepository.self),
            labelsRepository: deps.resolve(type: LabelsRepository.self)
        )
        // Compute changed fields
        var changed: Set<String> = []
        if old.name != new.name { changed.insert("title") }
        if old.description != new.description { changed.insert("description") }
        if old.priority != new.priority { changed.insert("priority") }
        if old.labelsDefault != new.labelsDefault { changed.insert("labels") }
        if changed.isEmpty { return }

        // Fetch all tasks for owner; filter by templateId, non-completed, occurrenceDate >= effectiveFrom
        guard let allTasks = try? await tasksRepo.fetchTasks(for: ownerId, in: nil) else { return }
        let startOfDay = Calendar.current.startOfDay(for: effectiveFrom)
        let candidates = allTasks.filter { task in
            task.templateId == new.id && task.isCompleted == false && (task.occurrenceDate ?? Date.distantPast) >= startOfDay
        }
        for var task in candidates {
            // Respect exceptionMask per field
            let mask = task.exceptionMask ?? []
            if changed.contains("title") && mask.contains("title") == false { task.title = new.name }
            if changed.contains("description") && mask.contains("description") == false { task.description = new.description }
            if changed.contains("priority") && mask.contains("priority") == false { task.priority = new.priority }
            // Never mutate completed; we filtered earlier
            do { try await tasksRepo.updateTask(task) } catch { continue }
            // Labels propagation (overwrite to template defaults if not excepted)
            if changed.contains("labels") && mask.contains("labels") == false, let uc = taskUC {
                let labelIds = Set(new.labelsDefault)
                try? await uc.setLabels(for: task.id, to: labelIds, userId: ownerId)
            }
        }
    }
}


