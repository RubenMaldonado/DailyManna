import Foundation
@testable import DailyManna

final class FakeRemoteTasksRepository: RemoteTasksRepository {
    var created: [Task] = []
    var updated: [Task] = []
    var deleted: [UUID] = []
    var byBucket: [String: [Task]] = [:]
    var sinceResponses: [Date?: [Task]] = [:]
    var syncBehavior: (([Task]) -> [Task])?

    func createTask(_ task: Task) async throws -> Task {
        created.append(task)
        var t = task
        t.remoteId = t.remoteId ?? t.id
        t.updatedAt = task.updatedAt.addingTimeInterval(1)
        return t
    }

    func fetchTasks(since lastSync: Date?) async throws -> [Task] {
        return sinceResponses[lastSync] ?? []
    }
    func fetchTasks(since lastSync: Date?, bucketKey: String?, dueBy: Date?) async throws -> [Task] {
        // Simple passthrough ignoring context for tests
        return try await fetchTasks(since: lastSync)
    }

    func updateTask(_ task: Task) async throws -> Task {
        updated.append(task)
        var t = task
        t.updatedAt = task.updatedAt.addingTimeInterval(1)
        return t
    }

    func deleteTask(id: UUID) async throws {
        deleted.append(id)
    }

    func fetchTasksForBucket(_ bucketKey: String) async throws -> [Task] {
        return byBucket[bucketKey] ?? []
    }

    func syncTasks(_ tasks: [Task]) async throws -> [Task] {
        if let syncBehavior { return syncBehavior(tasks) }
        var results: [Task] = []
        for task in tasks {
            if task.remoteId == nil {
                let created = try await createTask(task)
                results.append(created)
            } else {
                let updated = try await updateTask(task)
                results.append(updated)
            }
        }
        return results
    }
    func startRealtime(userId: UUID) async throws {}
    func stopRealtime() async {}
    func deleteAll(for userId: UUID) async throws {}
}

final class FakeRemoteLabelsRepository: RemoteLabelsRepository {
    var created: [Label] = []
    var updated: [Label] = []
    var deleted: [UUID] = []
    var sinceResponses: [Date?: [Label]] = [:]
    var syncBehavior: (([Label]) -> [Label])?

    func createLabel(_ label: Label) async throws -> Label {
        created.append(label)
        var l = label
        l.remoteId = l.remoteId ?? l.id
        l.updatedAt = label.updatedAt.addingTimeInterval(1)
        return l
    }

    func fetchLabels(since lastSync: Date?) async throws -> [Label] {
        return sinceResponses[lastSync] ?? []
    }

    func updateLabel(_ label: Label) async throws -> Label {
        updated.append(label)
        var l = label
        l.updatedAt = label.updatedAt.addingTimeInterval(1)
        return l
    }

    func deleteLabel(id: UUID) async throws {
        deleted.append(id)
    }

    func syncLabels(_ labels: [Label]) async throws -> [Label] {
        if let syncBehavior { return syncBehavior(labels) }
        var results: [Label] = []
        for label in labels {
            if label.remoteId == nil {
                let created = try await createLabel(label)
                results.append(created)
            } else {
                let updated = try await updateLabel(label)
                results.append(updated)
            }
        }
        return results
    }
    func fetchTaskLabelLinks(since lastSync: Date?) async throws -> [TaskLabelLink] { return [] }
    func startRealtime(userId: UUID) async throws {}
    func stopRealtime() async {}
    func deleteAll(for userId: UUID) async throws {}
    func link(_ link: TaskLabelLink) async throws {}
    func unlink(taskId: UUID, labelId: UUID) async throws {}
}


final class FakeRemoteWorkingLogRepository: RemoteWorkingLogRepository {
    var upserts: [WorkingLogItem] = []
    var softDeleted: [UUID] = []
    var hardDeleted: [UUID] = []
    var sinceResponses: [Date?: [WorkingLogItem]] = [:]
    func upsert(_ item: WorkingLogItem) async throws -> WorkingLogItem {
        upserts.append(item)
        var i = item
        i.remoteId = i.remoteId ?? i.id
        i.updatedAt = item.updatedAt.addingTimeInterval(1)
        return i
    }
    func softDelete(id: UUID) async throws { softDeleted.append(id) }
    func hardDelete(id: UUID) async throws { hardDeleted.append(id) }
    func fetchItems(since lastSync: Date?) async throws -> [WorkingLogItem] { sinceResponses[lastSync] ?? [] }
    func startRealtime(userId: UUID) async throws {}
    func stopRealtime() async {}
}

