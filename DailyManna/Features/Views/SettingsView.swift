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
    @Published var isPresentingConflictSheet: Bool = false
    @Published var conflictCandidates: [Task] = []
    @Published var allNeedingSync: [Task] = []
    @Published var includeAllNeedingSync: Bool = false
    // Removed rich text feature flag
    
    private let tasksRepository: TasksRepository
    private let labelsRepository: LabelsRepository
    private let remoteTasksRepository: RemoteTasksRepository
    private let remoteLabelsRepository: RemoteLabelsRepository
    private let syncService: SyncService
    private let workingLogRepository: WorkingLogRepository = try! Dependencies.shared.resolve(type: WorkingLogRepository.self)
    private let remoteWorkingLogRepository: RemoteWorkingLogRepository = try! Dependencies.shared.resolve(type: RemoteWorkingLogRepository.self)
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

    func findSyncConflictCandidates() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            // Gather local items that are likely to fail push
            let needing = try await tasksRepository.fetchTasksNeedingSync(for: userId)
            let active = needing.filter { $0.deletedAt == nil }
            allNeedingSync = active.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let routinesRoots = active.filter { $0.bucketKey == .routines && $0.parentTaskId == nil }

            // Root with dueAt present violates chk_routines_due_requires_parent
            var offenders: [UUID: Task] = [:]
            for t in routinesRoots where t.dueAt != nil { offenders[t.id] = t }

            // Duplicate roots by title (keep oldest per normalized title)
            let groupsByTitle: [String: [Task]] = Dictionary(grouping: routinesRoots) { t in t.title.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            for (_, group) in groupsByTitle {
                if group.count > 1 {
                    let sorted = group.sorted { $0.createdAt < $1.createdAt }
                    for dup in sorted.dropFirst() { offenders[dup.id] = dup }
                }
            }

            // Duplicate roots by templateId (keep oldest per template). Build groups separately to avoid Optional key
            var templateGroups: [UUID: [Task]] = [:]
            for t in routinesRoots {
                if let tid = t.templateId { templateGroups[tid, default: []].append(t) }
            }
            for (_, group) in templateGroups where group.count > 1 {
                let sorted = group.sorted { $0.createdAt < $1.createdAt }
                for dup in sorted.dropFirst() { offenders[dup.id] = dup }
            }

            conflictCandidates = Array(offenders.values).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            isPresentingConflictSheet = true
        } catch {
            statusMessage = "Failed to scan conflicts: \(error.localizedDescription)"
        }
    }

    func deleteConflictCandidates() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Cleaning up…"
        let base = conflictCandidates
        let extra = includeAllNeedingSync ? allNeedingSync : []
        // Combine unique by id
        var seen: Set<UUID> = []
        let combined = (base + extra).filter { t in
            if seen.contains(t.id) { return false }
            seen.insert(t.id)
            return true
        }
        let toDelete = combined
        conflictCandidates = []
        allNeedingSync = []
        includeAllNeedingSync = false
        isPresentingConflictSheet = false
        do {
            for task in toDelete {
                // Best-effort remote soft delete (ignore if not present)
                try? await remoteTasksRepository.deleteTask(id: task.id)
                // Local soft delete
                try await tasksRepository.deleteTask(by: task.id)
            }
            // Trigger a sync to finalize
            await syncService.sync(for: userId)
            statusMessage = "Deleted \(toDelete.count) conflicted tasks"
        } catch {
            statusMessage = "Cleanup failed: \(error.localizedDescription)"
        }
        isWorking = false
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

    func hardDeleteWorkingLogItemsPermanently() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Hard deleting Working Log items…"
        do {
            // Fetch soft-deleted items and delete them hard both locally and remotely
            // Since local repo does not expose fetching soft-deleted directly, we use purge path after remote delete by time horizon
            // For safety, delete remotely any items marked deleted locally
            let needingSync = try await workingLogRepository.fetchNeedingSync(for: userId)
            for item in needingSync where item.deletedAt != nil {
                try await remoteWorkingLogRepository.hardDelete(id: item.id)
                try await workingLogRepository.deleteHard(id: item.id)
            }
            // As a catch-all, purge any remaining soft-deleted older than now
            try await workingLogRepository.purgeSoftDeleted(olderThan: Date())
            statusMessage = "Working Log items hard-deleted"
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
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
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("dueNotificationsEnabled") private var dueNotificationsEnabled: Bool = false
    @AppStorage("completionHapticEnabled") private var completionHapticEnabled: Bool = true
    @AppStorage("completionSoundEnabled") private var completionSoundEnabled: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Features") {
                    NavigationLink("Keyboard Shortcuts") { KeyboardShortcutsView() }
                }
                Section("Feedback") {
                    Toggle("Completion haptic", isOn: $completionHapticEnabled)
                    Toggle("Completion sound", isOn: $completionSoundEnabled)
                        .tint(Colors.warning)
                        .accessibilityHint("Plays a subtle tone when marking a task complete")
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
                    Toggle("Due date notifications", isOn: $dueNotificationsEnabled)
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
                    Button {
                        _Concurrency.Task { await viewModel.findSyncConflictCandidates() }
                    } label: {
                        Text("Find sync-conflicted ROUTINES roots…")
                    }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                    .disabled(viewModel.isWorking)

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

                    Button(role: .destructive) {
                        _Concurrency.Task { await viewModel.hardDeleteWorkingLogItemsPermanently() }
                    } label: {
                        Text("Hard delete soft-deleted Working Log items")
                    }
                    .buttonStyle(DestructiveButtonStyle())
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
            .sheet(isPresented: $viewModel.isPresentingConflictSheet) {
                ConflictCleanupSheet(viewModel: viewModel)
            }
        }
    }
}

private struct ConflictCleanupSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Delete conflicted ROUTINES roots?")
                .style(Typography.title3)
                .foregroundColor(Colors.onSurface)
            Toggle("Also include all local tasks pending sync (force delete)", isOn: $viewModel.includeAllNeedingSync)
                .tint(Colors.warning)
                .padding(.bottom, Spacing.xSmall)
            if viewModel.conflictCandidates.isEmpty == false {
                Text("These tasks appear to be conflicting roots and will be deleted:")
                    .style(Typography.body)
                    .foregroundColor(Colors.onSurfaceVariant)
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        ForEach(viewModel.conflictCandidates, id: \.id) { t in
                            Text("• \(t.title)")
                                .style(Typography.body)
                                .foregroundColor(Colors.onSurface)
                        }
                    }
                }
                .frame(maxHeight: 240)
            } else {
                Text("No detected ROUTINES root conflicts.")
                    .style(Typography.body)
                    .foregroundColor(Colors.onSurfaceVariant)
            }
            if viewModel.includeAllNeedingSync && viewModel.allNeedingSync.isEmpty == false {
                Divider()
                Text("Additionally deleting all local tasks pending sync:")
                    .style(Typography.body)
                    .foregroundColor(Colors.onSurfaceVariant)
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        ForEach(viewModel.allNeedingSync, id: \.id) { t in
                            Text("• \(t.title)")
                                .style(Typography.body)
                                .foregroundColor(Colors.onSurface)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                Button(deleteButtonTitle, role: .destructive) {
                    _Concurrency.Task { await viewModel.deleteConflictCandidates() }
                    dismiss()
                }
                .buttonStyle(DestructiveButtonStyle())
                .disabled(totalDeleteCount == 0)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }
    private var totalDeleteCount: Int {
        var ids: Set<UUID> = []
        for t in viewModel.conflictCandidates { ids.insert(t.id) }
        if viewModel.includeAllNeedingSync {
            for t in viewModel.allNeedingSync { ids.insert(t.id) }
        }
        return ids.count
    }
    private var deleteButtonTitle: String {
        "Delete \(totalDeleteCount)"
    }
}


