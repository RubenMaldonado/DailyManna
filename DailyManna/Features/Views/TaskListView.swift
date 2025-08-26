//
//  TaskListView.swift
//  DailyManna
//
//  Epic 0.1 Infrastructure Demo View
//  Simple UI to demonstrate modular architecture works
//

import SwiftUI

/// Simple view to demonstrate Epic 0.1 architecture is working
/// This is a minimal UI focused on proving the infrastructure
struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    private let userId: UUID
    @EnvironmentObject private var authService: AuthenticationService
    
    init(viewModel: TaskListViewModel, userId: UUID) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.userId = userId
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Daily Manna")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Colors.primary)
            
            Text("Epic 0.1: Architecture Demo")
                .font(.subheadline)
                .foregroundColor(Colors.onSurfaceVariant)
            
            Divider()

            // Session banner
            VStack(spacing: 8) {
                Text("Signed in")
                    .font(.headline)
                    .foregroundColor(Colors.success)
                Text("User ID: \(userId.uuidString)")
                    .font(.caption)
                    .foregroundColor(Colors.onSurfaceVariant)
                Button("Sign out") {
                    _Concurrency.Task { try? await authService.signOut() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Colors.surface)
            .cornerRadius(12)
            
            // Architecture Status
            VStack(alignment: .leading, spacing: 12) {
                ArchitectureStatusRow(title: "✅ Domain Layer", subtitle: "Models, Use Cases, Repositories")
                ArchitectureStatusRow(title: "✅ Data Layer", subtitle: "SwiftData, Repository Implementations")
                ArchitectureStatusRow(title: "✅ Design System", subtitle: "Colors, Typography, Components")
                ArchitectureStatusRow(title: "✅ Features Layer", subtitle: "ViewModels, Views")
                ArchitectureStatusRow(title: "✅ Dependency Injection", subtitle: "Clean Architecture Setup")
                ArchitectureStatusRow(title: "✅ Error Handling", subtitle: "Logging & Error Management")
            }
            .padding()
            .background(Colors.surface)
            .cornerRadius(12)
            
            Spacer()
            
            // Simple Task Demo
            VStack(spacing: 16) {
                Text("Task System Test")
                    .font(.headline)
                
                if viewModel.isLoading {
                    ProgressView("Testing architecture...")
                        .foregroundColor(Colors.primary)
                } else if let errorMessage = viewModel.errorMessage {
                    Text("❌ Error: \(errorMessage)")
                        .foregroundColor(Colors.error)
                        .multilineTextAlignment(.center)
                } else {
                    Text("✅ Architecture working!")
                        .foregroundColor(Colors.success)
                        .font(.title2)
                    
                    Text("Found \(viewModel.tasksWithLabels.count) tasks")
                        .foregroundColor(Colors.onSurfaceVariant)
                }
                
                Button("Test Architecture") {
                    _Concurrency.Task {
                        await viewModel.fetchTasks()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Colors.primary)
            }
            .padding()
            .background(Colors.surface)
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
        .background(Colors.background)
        .task {
            await viewModel.fetchTasks()
        }
    }
}

// MARK: - Architecture Status Component
private struct ArchitectureStatusRow: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Colors.onSurface)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Colors.onSurfaceVariant)
            }
            Spacer()
        }
    }
}

#Preview {
    Text("Epic 0.1 Architecture Demo")
        .font(.title)
        .foregroundColor(Colors.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Colors.background)
}
