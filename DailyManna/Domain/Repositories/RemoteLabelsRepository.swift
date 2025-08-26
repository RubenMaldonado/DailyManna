//
//  RemoteLabelsRepository.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

protocol RemoteLabelsRepository {
    func createLabel(_ label: Label) async throws -> Label
    func fetchLabels(since lastSync: Date?) async throws -> [Label]
    func updateLabel(_ label: Label) async throws -> Label
    func deleteLabel(id: UUID) async throws
    func syncLabels(_ labels: [Label]) async throws -> [Label]
}
