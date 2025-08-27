## Release Notes — v1.3-sync

### Highlights
- Foreground realtime + periodic sync across iOS and macOS
- Delta pull with 120s overlap, per-user checkpoints
- Offline-first writes with `needsSync` flags and retries
- UI syncing indicator and auto-refresh after sync completes
- Debug Settings: bulk delete (local + Supabase) and sample data generator

### Details
- Sync orchestration
  - Push local mutations; pull deltas using server `updated_at`.
  - Overlap window heals clock skew; checkpoints set to max server timestamp.
  - Initial sync on first load; activation sync when app becomes active; periodic sync every 60s.
  - Exponential backoff with jitter for robustness.
- Data layer
  - SwiftData entities carry `remoteId`, `needsSync`, `deletedAt`.
  - Repos mark local writes for sync and bump `updatedAt`.
  - Targeted queries for items needing sync.
- Remote layer
  - Supabase repositories handle CRUD, delta fetch, and bulk soft-delete.
  - Realtime hooks scaffolded; foreground start invoked.
- UI
  - Sync status row and manual “Sync now” button.
  - Automatic list refresh upon successful sync.
  - Debug-only Settings sheet for test actions.

### Supabase
- Ensure `public.tasks` and `public.labels` are added to `supabase_realtime` publication.
- RLS owner policies present; `updated_at` triggers active.
- Helpful indexes are in place for delta and lists.

### Known follow-ups
- Wire postgres_changes events to targeted upserts.
- Optional: silent push (APNs) via Edge Functions for background freshness.


