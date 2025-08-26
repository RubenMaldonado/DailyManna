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
}


