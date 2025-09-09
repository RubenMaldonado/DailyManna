//
//  WorkingLogRepository.swift
//  DailyManna
//
//  Repository protocols for Working Log (local + remote)
//

import Foundation

public protocol WorkingLogRepository: Sendable {
    // CRUD
    func create(_ item: WorkingLogItem) async throws
    func update(_ item: WorkingLogItem) async throws
    func deleteSoft(id: UUID) async throws
    func deleteHard(id: UUID) async throws
    func fetch(by id: UUID) async throws -> WorkingLogItem?
    func fetchRange(userId: UUID, startDate: Date, endDate: Date) async throws -> [WorkingLogItem]
    func search(userId: UUID, text: String, startDate: Date?, endDate: Date?) async throws -> [WorkingLogItem]
    func purgeSoftDeleted(olderThan date: Date) async throws
    func fetchNeedingSync(for userId: UUID) async throws -> [WorkingLogItem]
}

public protocol RemoteWorkingLogRepository: Sendable {
    func upsert(_ item: WorkingLogItem) async throws -> WorkingLogItem
    func softDelete(id: UUID) async throws
    func hardDelete(id: UUID) async throws
    func fetchItems(since lastSync: Date?) async throws -> [WorkingLogItem]
    // Realtime hooks (no-op baseline)
    func startRealtime(userId: UUID) async throws
    func stopRealtime() async
}


