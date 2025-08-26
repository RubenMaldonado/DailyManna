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
    
    init() throws {
        let schema = Schema([
            TaskEntity.self,
            LabelEntity.self,
            TaskLabelEntity.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            throw DataError.initializationFailed("Failed to create ModelContainer: \(error.localizedDescription)")
        }
        
        let modelContext = ModelContext(modelContainer)
        // Initialize repositories
        self._tasksRepository = SwiftDataTasksRepository(modelContext: modelContext)
        self._labelsRepository = SwiftDataLabelsRepository(modelContext: modelContext)
    }
    
    /// Private initializer for test containers
    private init(isInMemory: Bool) throws {
        let schema = Schema([
            TaskEntity.self,
            LabelEntity.self,
            TaskLabelEntity.self
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
        
        let modelContext = ModelContext(modelContainer)
        // Initialize repositories
        self._tasksRepository = SwiftDataTasksRepository(modelContext: modelContext)
        self._labelsRepository = SwiftDataLabelsRepository(modelContext: modelContext)
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
}
