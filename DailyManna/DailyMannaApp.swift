//
//  DailyMannaApp.swift
//  DailyManna
//
//  Created by Ruben Maldonado Tena on 8/24/25.
//  Updated by Daily Manna Architecture on 8/25/25.
//

import SwiftUI
import SwiftData

@main
struct DailyMannaApp: App {
    @StateObject private var authService: AuthenticationService
    
    init() {
        // Initialize stored properties first
        // Temporarily bootstrap with a placeholder; will assign real instance after DI setup
        _authService = StateObject(wrappedValue: AuthenticationService())
        
        // Now safe to use self
        configureDependencies()
        configureDesignSystem()
        
        do {
            let service = try Dependencies.shared.resolve(type: AuthenticationService.self)
            _authService = StateObject(wrappedValue: service)
        } catch {
            fatalError("Failed to resolve AuthenticationService: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch authService.authState {
                case .unauthenticated, .error:
                    SignInView()
                case .authenticating:
                    LoadingView()
                case .authenticated(let user):
                    makeTaskListView(for: user)
                        .environmentObject(authService)
                }
            }
            .task {
                await authService.runAuthLifecycle()
                 #if canImport(UIKit)
                NotificationRouter.shared.register()
                #endif
            }
        }
        .modelContainer(getModelContainer())
    }
    
    private func configureDependencies() {
        do {
            try Dependencies.shared.configure()
            Logger.shared.info("App dependencies configured successfully", category: .general)
        } catch {
            Logger.shared.fault("Failed to configure dependencies", category: .general, error: error)
            fatalError("Failed to configure dependencies: \(error)")
        }
    }
    
    private func configureDesignSystem() {
        // Configure any global UI appearance here if needed
        Logger.shared.info("Design system configured", category: .ui)
    }
    
    private func getModelContainer() -> ModelContainer {
        do {
            let dataContainer = try Dependencies.shared.resolve(type: DataContainer.self)
            return dataContainer.modelContainer
        } catch {
            Logger.shared.fault("Failed to resolve DataContainer", category: .data, error: error)
            fatalError("Failed to resolve DataContainer: \(error)")
        }
    }
    
    private func makeTaskListView(for user: User) -> some View {
        do {
            let taskUseCases = try Dependencies.shared.resolve(type: TaskUseCases.self)
            let labelUseCases = try Dependencies.shared.resolve(type: LabelUseCases.self)
            let syncService = try Dependencies.shared.resolve(type: SyncService.self)
            let viewModel = TaskListViewModel(
                taskUseCases: taskUseCases,
                labelUseCases: labelUseCases,
                userId: user.id,
                syncService: syncService
            )
            return AnyView(TaskListView(viewModel: viewModel, userId: user.id))
        } catch {
            Logger.shared.fault("Failed to resolve dependencies for TaskListView", category: .ui, error: error)
            return AnyView(Text("Error: \(error.localizedDescription)"))
        }
    }
}
