//
//  RemoteLabelsRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

protocol RemoteLabelsRepository {
    func createLabel(_ label: Label) async throws -> Label
    /// Fetch a single label by id from the remote store
    func fetchLabel(id: UUID) async throws -> Label?
    func fetchLabels(since lastSync: Date?) async throws -> [Label]
    func updateLabel(_ label: Label) async throws -> Label
    func deleteLabel(id: UUID) async throws
    func syncLabels(_ labels: [Label]) async throws -> [Label]
    func fetchTaskLabelLinks(since lastSync: Date?) async throws -> [TaskLabelLink]
    // Realtime hooks removed; handled by RealtimeCoordinator
    /// Bulk soft-delete all user labels remotely (testing convenience)
    func deleteAll(for userId: UUID) async throws

    // MARK: - Task-Label Links
    func link(_ link: TaskLabelLink) async throws
    func unlink(taskId: UUID, labelId: UUID) async throws
}
