//
//  RealtimeCoordinator.swift
//  DailyManna
//
//  Centralizes Supabase Realtime subscriptions and exposes typed AsyncStreams
//  for tasks and labels. Keeps concurrency concerns out of repository files.
//

import Foundation
import Supabase

enum ChangeAction: String { case upsert, delete, unknown }

struct TaskChange { let id: UUID?, action: ChangeAction }
struct LabelChange { let id: UUID?, action: ChangeAction }
struct TemplateChange { let id: UUID?, action: ChangeAction }
struct SeriesChange { let id: UUID?, action: ChangeAction }

actor RealtimeCoordinator {
    private let client: SupabaseClient
    private var tasksChannel: RealtimeChannelV2?
    private var labelsChannel: RealtimeChannelV2?
    private var templatesChannel: RealtimeChannelV2?
    private var seriesChannel: RealtimeChannelV2?

    private typealias AsyncTask = _Concurrency.Task<Void, Never>
    private var tasksConsumer: AsyncTask?
    private var labelsConsumer: AsyncTask?
    private var templatesConsumer: AsyncTask?
    private var seriesConsumer: AsyncTask?

    private var taskStreamContinuation: AsyncStream<TaskChange>.Continuation?
    private var labelStreamContinuation: AsyncStream<LabelChange>.Continuation?
    private var templateStreamContinuation: AsyncStream<TemplateChange>.Continuation?
    private var seriesStreamContinuation: AsyncStream<SeriesChange>.Continuation?

    init(client: SupabaseClient = SupabaseConfig.shared.client) {
        self.client = client
    }

    // Public streams
    private(set) lazy var taskChanges: AsyncStream<TaskChange> = {
        let (stream, continuation) = AsyncStream<TaskChange>.makeStream()
        taskStreamContinuation = continuation
        return stream
    }()

    private(set) lazy var labelChanges: AsyncStream<LabelChange> = {
        let (stream, continuation) = AsyncStream<LabelChange>.makeStream()
        labelStreamContinuation = continuation
        return stream
    }()

    private(set) lazy var templateChanges: AsyncStream<TemplateChange> = {
        let (stream, continuation) = AsyncStream<TemplateChange>.makeStream()
        templateStreamContinuation = continuation
        return stream
    }()

    private(set) lazy var seriesChanges: AsyncStream<SeriesChange> = {
        let (stream, continuation) = AsyncStream<SeriesChange>.makeStream()
        seriesStreamContinuation = continuation
        return stream
    }()

    func start(for userId: UUID) async {
        await startTasks(userId: userId)
        await startLabels(userId: userId)
        await startTemplates(userId: userId)
        await startSeries(userId: userId)
    }

    func stop() async {
        tasksConsumer?.cancel(); tasksConsumer = nil
        labelsConsumer?.cancel(); labelsConsumer = nil
        templatesConsumer?.cancel(); templatesConsumer = nil
        seriesConsumer?.cancel(); seriesConsumer = nil
        tasksChannel = nil
        labelsChannel = nil
        templatesChannel = nil
        seriesChannel = nil
    }

    // MARK: - Private
    private func startTasks(userId: UUID) async {
        let channel = client.channel("dm_tasks_\(userId.uuidString)")
        tasksChannel = channel
        let changes = channel.postgresChange(Supabase.AnyAction.self, schema: "public", table: "tasks", filter: .eq("user_id", value: userId.uuidString))
        _ = try? await channel.subscribeWithError()
        tasksConsumer?.cancel()
        tasksConsumer = AsyncTask { [weak self] in await self?.consumeTaskEvents(changes) }
    }

    private func startLabels(userId: UUID) async {
        let channel = client.channel("dm_labels_\(userId.uuidString)")
        labelsChannel = channel
        let changes = channel.postgresChange(Supabase.AnyAction.self, schema: "public", table: "labels", filter: .eq("user_id", value: userId.uuidString))
        _ = try? await channel.subscribeWithError()
        labelsConsumer?.cancel()
        labelsConsumer = AsyncTask { [weak self] in await self?.consumeLabelEvents(changes) }
    }

    private func startTemplates(userId: UUID) async {
        let channel = client.channel("dm_templates_\(userId.uuidString)")
        templatesChannel = channel
        let changes = channel.postgresChange(Supabase.AnyAction.self, schema: "public", table: "templates", filter: .eq("owner_id", value: userId.uuidString))
        _ = try? await channel.subscribeWithError()
        templatesConsumer?.cancel()
        templatesConsumer = AsyncTask { [weak self] in await self?.consumeTemplateEvents(changes) }
    }

    private func startSeries(userId: UUID) async {
        let channel = client.channel("dm_series_\(userId.uuidString)")
        seriesChannel = channel
        let changes = channel.postgresChange(Supabase.AnyAction.self, schema: "public", table: "series", filter: .eq("owner_id", value: userId.uuidString))
        _ = try? await channel.subscribeWithError()
        seriesConsumer?.cancel()
        seriesConsumer = AsyncTask { [weak self] in await self?.consumeSeriesEvents(changes) }
    }

    // We intentionally avoid accessing SDK-internal payload fields.
    // If the SDK exposes typed payloads in this environment, we can revisit.

    // MARK: - Consumers
    private func consumeTaskEvents(_ changes: AsyncStream<Supabase.AnyAction>) async {
        for await _ in changes {
            // Yield a generic hint (no id) to trigger a debounced delta pull.
            taskStreamContinuation?.yield(TaskChange(id: nil, action: .unknown))
        }
    }

    private func consumeLabelEvents(_ changes: AsyncStream<Supabase.AnyAction>) async {
        for await _ in changes {
            labelStreamContinuation?.yield(LabelChange(id: nil, action: .unknown))
        }
    }

    private func consumeTemplateEvents(_ changes: AsyncStream<Supabase.AnyAction>) async {
        for await _ in changes {
            templateStreamContinuation?.yield(TemplateChange(id: nil, action: .unknown))
        }
    }

    private func consumeSeriesEvents(_ changes: AsyncStream<Supabase.AnyAction>) async {
        for await _ in changes {
            seriesStreamContinuation?.yield(SeriesChange(id: nil, action: .unknown))
        }
    }
}


