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
    @State private var newTaskTitle: String = ""
    
    init(viewModel: TaskListViewModel, userId: UUID) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.userId = userId
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Top chrome: account + bucket picker
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Manna").style(Typography.title2).foregroundColor(Colors.onSurface)
                    Text("Signed in").style(Typography.caption).foregroundColor(Colors.success)
                }
                Spacer()
                Button("Sign out") { _Concurrency.Task { try? await authService.signOut() } }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            
            Picker("Bucket", selection: $viewModel.selectedBucket) {
                ForEach(TimeBucket.allCases.sorted { $0.sortOrder < $1.sortOrder }) { bucket in
                    Text(bucket.displayName).tag(bucket)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: viewModel.selectedBucket) { _, newValue in
                viewModel.select(bucket: newValue)
            }

            BucketHeader(bucket: viewModel.selectedBucket,
                         count: viewModel.bucketCounts[viewModel.selectedBucket] ?? 0)
            .padding(.horizontal)

            // Quick Add composer
            HStack(spacing: 8) {
                TextField("Add a task…", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { addCurrentTask() }
                Button {
                    addCurrentTask()
                } label: {
                    Text("Add")
                }
                .buttonStyle(.borderedProminent)
                .tint(Colors.primary)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)

            if viewModel.isLoading {
                ProgressView("Loading...")
                    .foregroundColor(Colors.primary)
                    .padding()
            } else if let errorMessage = viewModel.errorMessage {
                Text("❌ Error: \(errorMessage)")
                    .foregroundColor(Colors.error)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if viewModel.tasksWithLabels.isEmpty {
                VStack(spacing: 8) {
                    Text("No tasks in \(viewModel.selectedBucket.displayName)").style(Typography.body)
                    Text("Add a task to get started").style(Typography.caption).foregroundColor(Colors.onSurfaceVariant)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Colors.surface)
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.tasksWithLabels, id: \.0.id) { pair in
                            TaskCard(task: pair.0, labels: pair.1) {
                                _Concurrency.Task { await viewModel.toggleTaskCompletion(task: pair.0) }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            Spacer(minLength: 0)
        }
        .background(Colors.background)
        .task {
            await viewModel.refreshCounts()
            await viewModel.fetchTasks(in: viewModel.selectedBucket)
        }
    }
}

private extension TaskListView {
    func addCurrentTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _Concurrency.Task {
            await viewModel.addTask(title: title, description: nil, bucket: viewModel.selectedBucket)
            await viewModel.refreshCounts()
        }
        newTaskTitle = ""
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
