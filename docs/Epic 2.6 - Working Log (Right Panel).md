# Epic 2.6 - Working Log (Right Panel)

## Overview
Provide a right-side Working Log panel that automatically groups completed tasks by day and supports lightweight “Working Log Items” (notes), with filtering and Markdown export. Panel state, day collapse states, and filters persist per device. Search is case- and diacritic-insensitive. Deletion is soft by default with an optional user-triggered hard delete action in Settings.

## Goals & Non-Goals
- Goals
  - Review completed work by day
  - Capture non-task wins/context via Working Log Items
  - Quick search and date filtering; default 30-day history
  - 5s Undo window before moving completed tasks
  - Export to Markdown
- Non-Goals (MVP)
  - CSV export, analytics dashboards, sharing, auto-retention of soft-deleted items

## UX Specification
- Placement: Right-side panel toggled from board header. Persist open/closed per device.
- Day grouping: Local timezone. Headers: Today, Yesterday, then `EEE, MMM d`.
- Order: Days newest-first; within a day, newest-first by timestamp.
- Subgroups per day: Tasks and Working Log Items.
- Controls: Add Log Item, Search (title/description), Date Range (Today/7/30/Custom), Export Markdown.
- Items
  - Tasks reuse `TaskCard` with completed timestamp chip; context menu to edit `completedAt` (no future dates).
  - Working Log Items use `WorkingLogItemCard` with distinct surface and note icon; timestamp chip is `occurredAt`.
- Collapsibility: Each day section collapsible; persist per device.
- Empty states: Friendly prompt to add a Log Item or clear filters.

## Data Model
### Tasks (existing)
- Inclusion: `completedAt != null`
- Editable in panel: `completedAt` (no future dates). Editing repositions the task.

### WorkingLogItem (new)
- Fields
  - `id: UUID`
  - `userId: UUID`
  - `title: String` (required)
  - `description: String` (required)
  - `occurredAt: Date` (required)
  - `createdAt: Date`
  - `updatedAt: Date`
  - `deletedAt: Date?` (soft delete)
  - `clientGeneratedId: UUID?` (optional; offline reconciliation)
- Indexes (remote)
  - `(user_id, occurred_at DESC)`
  - `(user_id, deleted_at)`

## Database (Supabase)
```sql
-- Table
create table if not exists public.working_log_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);

-- Row level security
alter table public.working_log_items enable row level security;
create policy wl_select on public.working_log_items for select using (auth.uid() = user_id);
create policy wl_insert on public.working_log_items for insert with check (auth.uid() = user_id);
create policy wl_update on public.working_log_items for update using (auth.uid() = user_id);
create policy wl_delete on public.working_log_items for delete using (auth.uid() = user_id);

-- Updated at trigger
create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

create trigger set_wl_updated_at before update on public.working_log_items
for each row execute procedure public.set_updated_at();

-- Indexes
create index if not exists idx_wl_user_occurred_at on public.working_log_items(user_id, occurred_at desc);
create index if not exists idx_wl_user_deleted_at on public.working_log_items(user_id, deleted_at);

-- Realtime publication (if using logical replication)
alter publication supabase_realtime add table public.working_log_items;
```

## Local Storage (SwiftData)
- `WorkingLogItemEntity` mirrors remote fields, including `deletedAt`.
- Migration plan: additive; no destructive changes.
- Fetch helpers
  - `fetchRange(userId, startDate, endDate, includeDeleted: false)`
  - `search(text)` normalizing case/diacritics
  - `groupByDay(localTimeZone)`

## Repositories & DTOs
- DTO: `WorkingLogItemDTO` mapping to/from Supabase JSON (`occurred_at`, `deleted_at`, etc.).
- Local repository: `SwiftDataWorkingLogRepository`
  - create/update/delete (soft), hardDelete(id), fetchRange, search, groupByDay
- Remote repository: `SupabaseWorkingLogRepository`
  - upsert, soft delete (set `deleted_at`), hard delete (DELETE), delta pull by `updated_at`

## Sync Service
- Extend `SyncService` to handle `working_log_items` using existing delta pattern (`updated_at >= last_checkpoint - 120s`).
- Exclude `deleted_at is not null` from normal views.
- Conflict resolution: last-write-wins by server `updated_at`.
- Realtime: subscribe for hints; trigger a pull on incoming changes when foregrounded.

## UI Components
- `WorkingLogPanelView`
  - Toggle in board header; persists open state per device.
  - Sections per day with collapse state persisted.
  - Search and date range toolbar; Export.
- `WorkingLogItemCard`
  - Distinct surface token and note icon; shows title, description, occurredAt chip.
- `CompletedTaskRow` reuse of `TaskCard` with completed chip and edit `completedAt` action.

## Behaviors
- Completion flow: 5s Undo toast; on timeout, task appears under day of `completedAt`. If user toggles back before timeout, cancel move.
- Edit `completedAt`: only for completed tasks inside panel; disallow future dates; reposition on save.
- Soft delete: hides item from view; Settings hard delete action permanently removes soft-deleted items.
- Default window: show last 30 days; “Load older days” fetches previous history.
- Search: case/diacritic-insensitive over titles/descriptions for both tasks and log items.

## Export to Markdown
- Scope: current filters (date range + search) applied.
- Format example:
```
# Working Log (Sep 01, 2025 – Sep 30, 2025)

## Mon, Sep 30
### Tasks
- [10:24] Fix sync drift in labels (#123)
### Log Items
- [11:05] Release v1.3.2 — addressed crash on launch
```
- Filename: `Working-Log_YYYY-MM-DD_to_YYYY-MM-DD.md`

## Settings
- “Hard delete Working Log items” action (explicit confirmation). No auto-retention.

## Telemetry
- Events: `working_log_opened`, `working_log_day_toggled`, `working_log_item_created/edited/deleted`, `task_completed_moved_to_working_log`, `task_completed_undo`, `working_log_export_markdown`
- Properties: counts per day, date range, search length, export day span, time_to_undo

## Testing Strategy
- Unit: repositories CRUD, grouping by day, search normalization, undo timer logic, date edit validation.
- Integration: Supabase RLS, delta sync correctness, tombstones, Realtime hint path.
- UI: panel toggle, collapse persistence, create/edit/delete log item, edit completedAt, export file creation.
- Perf: 1k–5k items; pagination of older days; search debounce.
- Accessibility: VoiceOver labels, 44pt targets, AA contrast for Log Items.

## Rollout Plan
- Feature flag: enable per user for staged rollout.
- Migration: deploy DB migration in dev branch; validate; merge to prod.
- Docs: update roadmap and this epic doc; add “What’s New” notes.
- Telemetry review after 1 week; iterate on search/indexing if needed.

## Tasks Breakdown
1. DB migration + RLS + indexes + publication
2. SwiftData entity + migration + predicates
3. DTOs + repositories (local/remote)
4. SyncService integration + tests
5. Panel UI + day sections + item cards
6. Completion Undo flow + date edit
7. Settings hard delete action
8. Export Markdown
9. Telemetry events + properties
10. Tests (unit/integration/UI) + a11y + perf polishing

## Definition of Done
- Panel provides 30-day default view with collapse per device, search/date filtering.
- Tasks auto-move with 5s undo; `completedAt` editable in panel; validation enforced.
- Working Log Items CRUD with soft delete; Settings hard delete action works.
- Sync solid; RLS/Realtime verified; export works; tests green; telemetry capturing.
