//
//  SyncService.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import Combine

@MainActor
final class SyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?
    
    private let localTasksRepository: TasksRepository
    private let remoteTasksRepository: RemoteTasksRepository
    private let localLabelsRepository: LabelsRepository
    private let remoteLabelsRepository: RemoteLabelsRepository
    
    init(
        localTasksRepository: TasksRepository,
        remoteTasksRepository: RemoteTasksRepository,
        localLabelsRepository: LabelsRepository,
        remoteLabelsRepository: RemoteLabelsRepository
    ) {
        self.localTasksRepository = localTasksRepository
        self.remoteTasksRepository = remoteTasksRepository
        self.localLabelsRepository = localLabelsRepository
        self.remoteLabelsRepository = remoteLabelsRepository
    }
    
    private var periodicCancellable: AnyCancellable?
    
    /// Performs a full bidirectional sync for a specific user
    func sync(for userId: UUID) async {
        guard !isSyncing else {
            Logger.shared.info("Sync already in progress, skipping", category: .sync)
            return
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            Logger.shared.info("Starting sync operation", category: .sync)
            
            // Sync tasks
            try await syncTasks(userId: userId)
            
            // Sync labels
            try await syncLabels(userId: userId)
            
            lastSyncDate = Date()
            Logger.shared.info("Sync completed successfully", category: .sync)
            
        } catch {
            Logger.shared.error("Sync failed", category: .sync, error: error)
            syncError = error
        }
        
        isSyncing = false
    }
    
    /// Syncs tasks bidirectionally
    private func syncTasks(userId: UUID) async throws {
        // 1. Push local changes to remote
        let localTasks = try await localTasksRepository.fetchTasks(for: userId, in: nil)
        let tasksNeedingSync = localTasks.filter { $0.needsSync }
        
        if !tasksNeedingSync.isEmpty {
            Logger.shared.info("Pushing \(tasksNeedingSync.count) local task changes", category: .sync)
            let syncedTasks = try await remoteTasksRepository.syncTasks(tasksNeedingSync)
            
            // Update local tasks with remote data
            for syncedTask in syncedTasks {
                var updatedTask = syncedTask
                updatedTask.needsSync = false
                try await localTasksRepository.updateTask(updatedTask)
            }
        }
        
        // 2. Pull remote changes
        let remoteTasks = try await remoteTasksRepository.fetchTasks(since: lastSyncDate)
        
        if !remoteTasks.isEmpty {
            Logger.shared.info("Pulling \(remoteTasks.count) remote task changes", category: .sync)
            
            for remoteTask in remoteTasks {
                do {
                    // Check if task exists locally
                    if let existingTask = try await localTasksRepository.fetchTask(by: remoteTask.id) {
                        // Apply conflict resolution (last-write-wins for now)
                        if remoteTask.updatedAt > existingTask.updatedAt {
                            var taskToUpdate = remoteTask
                            taskToUpdate.needsSync = false
                            try await localTasksRepository.updateTask(taskToUpdate)
                        }
                    } else {
                        // Create new local task
                        var newTask = remoteTask
                        newTask.needsSync = false
                        try await localTasksRepository.createTask(newTask)
                    }
                } catch {
                    Logger.shared.error("Failed to sync task \(remoteTask.id)", category: .sync, error: error)
                }
            }
        }
    }
    
    /// Syncs labels bidirectionally
    private func syncLabels(userId: UUID) async throws {
        // 1. Push local changes to remote
        let localLabels = try await localLabelsRepository.fetchLabels(for: userId)
        let labelsNeedingSync = localLabels.filter { $0.needsSync }
        
        if !labelsNeedingSync.isEmpty {
            Logger.shared.info("Pushing \(labelsNeedingSync.count) local label changes", category: .sync)
            let syncedLabels = try await remoteLabelsRepository.syncLabels(labelsNeedingSync)
            
            // Update local labels with remote data
            for syncedLabel in syncedLabels {
                var updatedLabel = syncedLabel
                updatedLabel.needsSync = false
                try await localLabelsRepository.updateLabel(updatedLabel)
            }
        }
        
        // 2. Pull remote changes
        let remoteLabels = try await remoteLabelsRepository.fetchLabels(since: lastSyncDate)
        
        if !remoteLabels.isEmpty {
            Logger.shared.info("Pulling \(remoteLabels.count) remote label changes", category: .sync)
            
            for remoteLabel in remoteLabels {
                do {
                    // Check if label exists locally
                    if let existingLabel = try await localLabelsRepository.fetchLabel(by: remoteLabel.id) {
                        // Apply conflict resolution (last-write-wins for now)
                        if remoteLabel.updatedAt > existingLabel.updatedAt {
                            var labelToUpdate = remoteLabel
                            labelToUpdate.needsSync = false
                            try await localLabelsRepository.updateLabel(labelToUpdate)
                        }
                    } else {
                        // Create new local label
                        var newLabel = remoteLabel
                        newLabel.needsSync = false
                        try await localLabelsRepository.createLabel(newLabel)
                    }
                } catch {
                    Logger.shared.error("Failed to sync label \(remoteLabel.id)", category: .sync, error: error)
                }
            }
        }
    }
    
    /// Performs initial sync for a user
    func performInitialSync(for userId: UUID) async {
        Logger.shared.info("Performing initial sync", category: .sync)
        await sync(for: userId)
    }
    
    /// Schedules periodic sync
    func startPeriodicSync(for userId: UUID, intervalSeconds: TimeInterval = 60) {
        periodicCancellable?.cancel()
        periodicCancellable = Timer.publish(every: intervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                _Concurrency.Task { await self.sync(for: userId) }
            }
    }
}
