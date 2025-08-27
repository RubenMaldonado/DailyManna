//
//  DIContainer.swift
//  DailyManna
//
//  Created by Daily Manna Architecture on 8/25/25.
//

import Foundation

enum DIError: Error, LocalizedError {
    case dependencyNotRegistered(String)
    case invalidDependencyType(String)
    
    var errorDescription: String? {
        switch self {
        case .dependencyNotRegistered(let name): return "Dependency '\(name)' not registered."
        case .invalidDependencyType(let name): return "Registered dependency for '\(name)' has an invalid type."
        }
    }
}

/// A simple dependency injection container
final class Dependencies {
    static let shared = Dependencies()
    
    private var registrations: [String: () -> Any] = [:]
    private var singletons: [String: Any] = [:]
    
    private init() {}
    
    /// Registers a dependency resolver
    func register<Service>(type: Service.Type, _ factory: @escaping () -> Service) {
        let key = String(describing: type)
        registrations[key] = factory
        singletons.removeValue(forKey: key) // Clear singleton if re-registered
    }
    
    /// Registers a singleton dependency
    func registerSingleton<Service>(type: Service.Type, _ factory: @escaping () -> Service) {
        let key = String(describing: type)
        registrations[key] = factory
        // Singleton will be created on first resolve and cached
    }
    
    /// Resolves a dependency
    func resolve<Service>(type: Service.Type) throws -> Service {
        let key = String(describing: type)
        
        if let singleton = singletons[key] as? Service {
            return singleton
        }
        
        guard let factory = registrations[key] else {
            throw DIError.dependencyNotRegistered(key)
        }
        
        let instance = factory()
        
        if let service = instance as? Service {
            // Cache if it was registered as a singleton
            if registrations[key] != nil { // Check if it was registered with a factory (could be singleton)
                singletons[key] = instance
            }
            return service
        } else {
            throw DIError.invalidDependencyType("Expected type \(key) but got \(Swift.type(of: instance))")
        }
    }
    
    /// Configures the default dependencies for the application
    @MainActor
    func configure() throws {
        // Core Services
        registerSingleton(type: AuthenticationService.self) { AuthenticationService() }
        
        // Data Layer
        let dataContainer = try DataContainer()
        registerSingleton(type: DataContainer.self) { dataContainer }
        registerSingleton(type: TasksRepository.self) { dataContainer.tasksRepository }
        registerSingleton(type: LabelsRepository.self) { dataContainer.labelsRepository }
        registerSingleton(type: SyncStateStore.self) { dataContainer.syncStateStore }
        
        // Remote Repositories
        registerSingleton(type: RemoteTasksRepository.self) { SupabaseTasksRepository() }
        registerSingleton(type: RemoteLabelsRepository.self) { SupabaseLabelsRepository() }
        
        // Sync Service
        registerSingleton(type: SyncService.self) {
            SyncService(
                localTasksRepository: try! self.resolve(type: TasksRepository.self),
                remoteTasksRepository: try! self.resolve(type: RemoteTasksRepository.self),
                localLabelsRepository: try! self.resolve(type: LabelsRepository.self),
                remoteLabelsRepository: try! self.resolve(type: RemoteLabelsRepository.self),
                syncStateStore: try! self.resolve(type: SyncStateStore.self)
            )
        }
        
        // Domain Layer
        registerSingleton(type: TaskUseCases.self) {
            try! TaskUseCases(
                tasksRepository: self.resolve(type: TasksRepository.self),
                labelsRepository: self.resolve(type: LabelsRepository.self)
            )
        }
        registerSingleton(type: LabelUseCases.self) {
            try! LabelUseCases(
                labelsRepository: self.resolve(type: LabelsRepository.self)
            )
        }
        
        Logger.shared.info("Dependency injection configured successfully", category: .general)
    }
    
    /// Clears all registered dependencies and singletons. Useful for testing.
    func reset() {
        registrations.removeAll()
        singletons.removeAll()
    }
}
