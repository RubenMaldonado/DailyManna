//
//  SettingsView.swift
//  DailyManna
//
//  Debug/testing utilities: bulk delete and sample data generation
//

import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isWorking: Bool = false
    @Published var statusMessage: String? = nil
    @Published var featureSubtasksEnabled: Bool = true
    // Removed rich text feature flag
    
    private let tasksRepository: TasksRepository
    private let labelsRepository: LabelsRepository
    private let remoteTasksRepository: RemoteTasksRepository
    private let remoteLabelsRepository: RemoteLabelsRepository
    private let syncService: SyncService
    private let recurrenceUseCases: RecurrenceUseCases = try! Dependencies.shared.resolve(type: RecurrenceUseCases.self)
    #if DEBUG
    @Published var isSoakRunning: Bool = false
    private var soakHarness: SoakTestHarness? = nil
    #endif
    
    let userId: UUID
    
    init(tasksRepository: TasksRepository,
         labelsRepository: LabelsRepository,
         remoteTasksRepository: RemoteTasksRepository,
         remoteLabelsRepository: RemoteLabelsRepository,
         syncService: SyncService,
         userId: UUID) {
        self.tasksRepository = tasksRepository
        self.labelsRepository = labelsRepository
        self.remoteTasksRepository = remoteTasksRepository
        self.remoteLabelsRepository = remoteLabelsRepository
        self.syncService = syncService
        self.userId = userId
    }
    
    func deleteAllData() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Deleting…"
        do {
            // Local
            try await labelsRepository.deleteAll(for: userId)
            try await tasksRepository.deleteAll(for: userId)
            // Remote (soft-delete)
            try await remoteLabelsRepository.deleteAll(for: userId)
            try await remoteTasksRepository.deleteAll(for: userId)
            // Sync to reconcile
            await syncService.sync(for: userId)
            statusMessage = "All data deleted"
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
        }
        isWorking = false
    }
    
    func generateSamples() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Generating…"
        do {
            let device = currentDeviceName()
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let stamp = formatter.string(from: now)
            
            for bucket in TimeBucket.allCases {
                let t = Task(
                    userId: userId,
                    bucketKey: bucket,
                    title: "Sample (\(device)) @ \(stamp)",
                    description: Bool.random() ? "Debug seed" : nil,
                    dueAt: Bool.random() ? Calendar.current.date(byAdding: .day, value: Int.random(in: 0...7), to: now) : nil,
                    recurrenceRule: nil,
                    isCompleted: false
                )
                // Local create; will be marked needsSync by use cases/repo
                try await tasksRepository.createTask(t)
            }
            // Kick a sync
            await syncService.sync(for: userId)
            statusMessage = "Samples created"
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
        }
        isWorking = false
    }

    func backfillRoutinesToRecurrences() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Backfilling…"
        do {
            // Convert all tasks in ROUTINES bucket to daily recurrences at 8:00 by default
            let tasks = try await tasksRepository.fetchTasks(for: userId, in: .routines)
            for t in tasks where t.deletedAt == nil {
                let rule = RecurrenceRule(freq: .daily, interval: 1, time: "08:00")
                let rec = Recurrence(userId: userId, taskTemplateId: t.id, rule: rule)
                try? await recurrenceUseCases.create(rec)
            }
            statusMessage = "Backfill complete"
        } catch {
            statusMessage = "Backfill failed: \(error.localizedDescription)"
        }
        isWorking = false
    }

    /// Clears local SwiftData (tasks, labels, junctions) and checkpoints, then performs a pull-only sync
    func resetLocalToServer() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Resetting local store…"
        do {
            try await labelsRepository.deleteAll(for: userId)
            try await tasksRepository.deleteAll(for: userId)
            try await syncService.resetSyncState(for: userId)
            await syncService.sync(for: userId)
            statusMessage = "Local store reset — pulled from server"
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
        }
        isWorking = false
    }
    
    private func currentDeviceName() -> String {
        #if os(iOS)
        return "iOS"
        #else
        return "macOS"
        #endif
    }

    #if DEBUG
    func setSoak(enabled: Bool) {
        guard enabled != isSoakRunning else { return }
        do {
            if enabled {
                let deps = Dependencies.shared
                let harness = SoakTestHarness(
                    userId: userId,
                    syncService: try deps.resolve(type: SyncService.self),
                    taskUseCases: try deps.resolve(type: TaskUseCases.self),
                    labelUseCases: try deps.resolve(type: LabelUseCases.self)
                )
                self.soakHarness = harness
                harness.start()
                isSoakRunning = true
            } else {
                soakHarness?.stop()
                soakHarness = nil
                isSoakRunning = false
            }
        } catch {
            Logger.shared.error("Failed to toggle soak harness", category: .ui, error: error)
        }
    }
    #endif
}

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthenticationService
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(get: { UserDefaults.standard.string(forKey: "appearance") ?? "system" }, set: { UserDefaults.standard.set($0, forKey: "appearance") })) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Features") {
                    Toggle("Enable Subtasks & Rich Descriptions", isOn: $viewModel.featureSubtasksEnabled)
                }
                #if DEBUG
                Section("Testing") {
                    Toggle(
                        "Soak test: background activity",
                        isOn: Binding(
                            get: { viewModel.isSoakRunning },
                            set: { newValue in viewModel.setSoak(enabled: newValue) }
                        )
                    )
                }
                #endif
                Section("Reminders") {
                    Toggle("Due date notifications", isOn: Binding(get: { UserDefaults.standard.bool(forKey: "dueNotificationsEnabled") }, set: { UserDefaults.standard.set($0, forKey: "dueNotificationsEnabled") }))
                    if #available(iOS 15.0, *) {
                        Button("Request Permission") {
                            _Concurrency.Task { await NotificationsManager.requestAuthorizationIfNeeded() }
                        }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                    }
                }
                Section("Account") {
                    Button("Sign out") { _Concurrency.Task { try? await authService.signOut() } }
                        .buttonStyle(SecondaryButtonStyle(size: .small))
                }
                Section("Danger Zone") {
                    Button(role: .destructive) {
                        _Concurrency.Task { await viewModel.deleteAllData() }
                    } label: {
                        Text("Delete ALL data (local + Supabase)")
                    }
                    .buttonStyle(DestructiveButtonStyle())
                    .disabled(viewModel.isWorking)

                    Button {
                        _Concurrency.Task { await viewModel.resetLocalToServer() }
                    } label: {
                        Text("Reset LOCAL to SERVER (pull-only)")
                    }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                    .disabled(viewModel.isWorking)
                }
                Section("Generators") {
                    Button {
                        _Concurrency.Task { await viewModel.generateSamples() }
                    } label: {
                        Text("Generate sample tasks (one per bucket)")
                    }
                    .buttonStyle(PrimaryButtonStyle(size: .small))
                    .disabled(viewModel.isWorking)
                    Button {
                        _Concurrency.Task { await viewModel.backfillRoutinesToRecurrences() }
                    } label: {
                        Text("Backfill Routines → Recurrences")
                    }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                    .disabled(viewModel.isWorking)
                }
                Section("Labels") {
                    LabelManagementInlineView(userId: viewModel.userId)
                }
                if let status = viewModel.statusMessage {
                    Section("Status") { Text(status) }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.buttonStyle(SecondaryButtonStyle(size: .small)) }
                #else
                ToolbarItem(placement: .automatic) { Button("Done") { dismiss() }.buttonStyle(SecondaryButtonStyle(size: .small)) }
                #endif
            }
        }
    }
}


