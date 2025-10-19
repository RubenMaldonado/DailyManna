//
//  DataContainer.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation
import SwiftData

/// Data layer errors
enum DataError: Error, LocalizedError {
    case initializationFailed(String)
    case notFound(String)
    case invalidOperation(String)
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message): return "Data initialization failed: \(message)"
        case .notFound(let message): return "Data not found: \(message)"
        case .invalidOperation(let message): return "Invalid data operation: \(message)"
        }
    }
}

/// Manages the SwiftData ModelContainer and provides access to repository implementations
final class DataContainer {
    let modelContainer: ModelContainer
    private let _tasksRepository: SwiftDataTasksRepository
    private let _labelsRepository: SwiftDataLabelsRepository
    private let _syncStateStore: SyncStateStore
    private let _workingLogRepository: SwiftDataWorkingLogRepository
    
    init() throws {
        let schema = Schema([
            TaskEntity.self,
            LabelEntity.self,
            TaskLabelEntity.self,
            TimeBucketEntity.self,
            SyncStateEntity.self,
            SavedFilterEntity.self,
            RecurrenceEntity.self,
            RecurrenceInstanceEntity.self,
            WorkingLogItemEntity.self,
            TemplateEntity.self,
            SeriesEntity.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If schema changed incompatibly (e.g., added properties), SwiftData may fail to open the store.
            // As a recovery in development builds, wipe the Application Support store and retry.
            #if DEBUG
            let fm = FileManager.default
            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                try? fm.removeItem(at: appSupport)
                try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
                do {
                    self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                } catch {
                    throw DataError.initializationFailed("Failed to create ModelContainer after reset: \(error.localizedDescription)")
                }
            } else {
                throw DataError.initializationFailed("Failed to create ModelContainer and could not access Application Support: \(error.localizedDescription)")
            }
            #else
            throw DataError.initializationFailed("Failed to create ModelContainer: \(error.localizedDescription)")
            #endif
        }
        
        // Use a dedicated bootstrap context for one-time setup (seeding/migrations)
        let bootstrapContext = ModelContext(modelContainer)
        bootstrapContext.autosaveEnabled = true
        // Seed fixed time buckets idempotently
        do {
            let bucketDescriptor = FetchDescriptor<TimeBucketEntity>()
            let existing = try bootstrapContext.fetch(bucketDescriptor)
            if existing.isEmpty {
                let buckets: [(String, String)] = [
                    (TimeBucket.thisWeek.rawValue, TimeBucket.thisWeek.displayName),
                    (TimeBucket.weekend.rawValue, TimeBucket.weekend.displayName),
                    (TimeBucket.nextWeek.rawValue, TimeBucket.nextWeek.displayName),
                    (TimeBucket.nextMonth.rawValue, TimeBucket.nextMonth.displayName),
                    (TimeBucket.routines.rawValue, TimeBucket.routines.displayName)
                ]
                for (key, name) in buckets {
                    bootstrapContext.insert(TimeBucketEntity(key: key, name: name))
                }
                try bootstrapContext.save()
            }
        } catch {
            // Seeding is best-effort; ignore if model not available
        }
        // Run lightweight data migrations (idempotent)
        DataMigration.runMigrations(modelContext: bootstrapContext)
        
        // IMPORTANT: Do not share a single ModelContext across multiple actors.
        // Create one context per repository actor to avoid concurrent access crashes.
        let syncStateContext = ModelContext(modelContainer)
        syncStateContext.autosaveEnabled = true
        // Templates/Tasks/Labels/WorkingLog repos manage their own contexts bound to their actors
        let seriesContext = ModelContext(modelContainer)
        seriesContext.autosaveEnabled = true

        // Initialize repositories with their own contexts
        self._tasksRepository = SwiftDataTasksRepository(modelContainer: modelContainer)
        self._labelsRepository = SwiftDataLabelsRepository(modelContainer: modelContainer)
        self._syncStateStore = SyncStateStore(modelContext: syncStateContext)
        self._workingLogRepository = SwiftDataWorkingLogRepository(modelContainer: modelContainer)
        self._templatesRepository = SwiftDataTemplatesRepository(modelContainer: modelContainer)
        self._seriesRepository = SwiftDataSeriesRepository(modelContext: seriesContext)
    }
    
    /// Private initializer for test containers
    private init(isInMemory: Bool) throws {
        let schema = Schema([
            TaskEntity.self,
            LabelEntity.self,
            TaskLabelEntity.self,
            SyncStateEntity.self,
            SavedFilterEntity.self,
            RecurrenceEntity.self,
            RecurrenceInstanceEntity.self,
            WorkingLogItemEntity.self,
            TemplateEntity.self,
            SeriesEntity.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isInMemory,
            allowsSave: true
        )
        
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            throw DataError.initializationFailed("Failed to create ModelContainer: \(error.localizedDescription)")
        }
        
        // Create isolated contexts per repository for tests as well
        let syncStateContext = ModelContext(modelContainer)
        syncStateContext.autosaveEnabled = true
        let seriesContext = ModelContext(modelContainer)
        seriesContext.autosaveEnabled = true
        
        // Initialize repositories
        self._tasksRepository = SwiftDataTasksRepository(modelContainer: modelContainer)
        self._labelsRepository = SwiftDataLabelsRepository(modelContainer: modelContainer)
        self._syncStateStore = SyncStateStore(modelContext: syncStateContext)
        self._workingLogRepository = SwiftDataWorkingLogRepository(modelContainer: modelContainer)
        self._templatesRepository = SwiftDataTemplatesRepository(modelContainer: modelContainer)
        self._seriesRepository = SwiftDataSeriesRepository(modelContext: seriesContext)
    }
    
    /// Creates a test container with in-memory storage
    static func test() throws -> DataContainer {
        return try DataContainer(isInMemory: true)
    }
    
    // MARK: - Repository Access
    
    var tasksRepository: TasksRepository {
        return _tasksRepository
    }
    
    var labelsRepository: LabelsRepository {
        return _labelsRepository
    }
    
    var syncStateStore: SyncStateStore {
        return _syncStateStore
    }
    
    var workingLogRepository: WorkingLogRepository {
        return _workingLogRepository
    }
    
    // New repositories
    private let _templatesRepository: SwiftDataTemplatesRepository
    private let _seriesRepository: SwiftDataSeriesRepository
    
    var templatesRepository: TemplatesRepository { _templatesRepository }
    var seriesRepository: SeriesRepository { _seriesRepository }
}
