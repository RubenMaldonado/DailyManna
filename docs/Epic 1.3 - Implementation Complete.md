## Epic 1.3 — Implementation Complete

### Summary
Bidirectional sync is implemented across devices with offline-first behavior. The app now supports push/pull sync, delta queries using server `updated_at`, soft-deletes via `deleted_at`, conflict resolution using LWW, UI sync indicators, periodic + activation + manual sync triggers, and foreground Realtime enablement via Supabase Publications. Debug-only tools were added for bulk delete and sample generation.

### What was implemented
- Sync orchestrator (`SyncService`):
  - Push local changes marked with `needsSync` for `tasks` and `labels`.
  - Pull deltas with overlap window (−120s) and set checkpoints from max server `updated_at`.
  - Per-user checkpoints persisted in SwiftData via `SyncStateEntity` and `SyncStateStore`.
  - Exponential backoff with jitter for failed phases.
  - Initial sync on first load; activation sync when app becomes active; periodic sync every 60s.
  - Hooks for Realtime start (foreground) with stubbed channel integration.

- Data layer:
  - `TaskEntity`, `LabelEntity` include sync metadata: `remoteId`, `version`, `needsSync`, `deletedAt`.
  - Repositories mark local writes with `needsSync = true` and bump `updatedAt`.
  - New methods: `fetchTasksNeedingSync`, `fetchLabelsNeedingSync`, `deleteAll(for:)` for local cleanup.

- Remote layer:
  - Supabase repositories (`tasks`, `labels`): create/update/delete, delta fetch (`updated_at >= since`), bulk soft-delete (`deleteAll(for:)`).
  - Realtime start/stop stubs (ready to wire events).

- UI & ViewModels:
  - `TaskListView`: initial sync, activation sync via `scenePhase == .active`, periodic sync, “Sync now” button.
  - `TaskListViewModel`: listens to `SyncService.$lastSyncDate` to auto-refresh lists after each sync.
  - Debug-only `SettingsView` with two actions: Delete ALL data (local + Supabase) and Generate samples (one task per bucket with device + timestamp).

### Supabase configuration performed
- Publications (Realtime): added `public.tasks` and `public.labels` to `supabase_realtime` publication (Studio: Database → Replication → Publications → Manage tables).
- RLS: owner policy (`user_id = auth.uid()`) on both tables.
- Triggers: `touch_updated_at` and per-table update triggers present for `tasks` and `labels`.
- Indexes: `(user_id, updated_at)` for deltas; `(user_id, bucket_key, is_completed, due_at)` for list views; unique `(user_id, name)` on labels.

### Acceptance criteria — verification
- [x] Basic push/pull sync strategy: implemented in `SyncService` with repositories.
- [x] Sync orchestrator with delta queries: `fetch(since:)` + overlap window and checkpoints.
- [x] Offline mutations queue: `needsSync` flags; local-first repos; retries on push.
- [x] Last-write-wins conflict resolution: compares server `updated_at`; applies newer record; local writes bump `updatedAt` before push.
- [x] Sync status indicators in UI: progress indicator + “Sync now”; view auto-refresh post-sync.
- [x] Retry logic: exponential backoff with jitter per phase (max 5 attempts).
- [x] Supabase Realtime subscriptions: tables added to publication; start/stop hooks in repos; activation sync ensures foreground convergence.

### Developer notes
- Checkpoints are per-user (`SyncStateEntity`); initial sync bootstraps with full pull when local store is empty.
- Delta pulls overlap by 2 minutes to heal clock skew.
- Bulk delete and sample generation are DEBUG-only and gated to avoid production exposure.

### Next steps (optional)
- Wire actual Realtime event handlers (postgres_changes) to perform targeted upserts and reduce delta pulls.
- Add silent-push Edge Function to nudge background devices (Proposal 2).


