## Epic 1.4 – Ordered Board (Drag-and-drop Reordering)

### Goals
- Reorder tasks precisely within and across buckets using drag-and-drop.
- Persist deterministic order across app sessions and devices.
- Avoid UI snap-back and animation glitches.

### Data Model
- Add `position: Double` to `Task` (domain), `TaskEntity` (SwiftData), and `TaskDTO` (remote).
- Sort by `position` ascending within `bucketKey`.
- Completed tasks are excluded from ordering calculations; completed list ordered by `completedAt` desc.

### Ordering Strategy
- New tasks appended to bottom via `nextPositionForBottom` (stride 1024).
- Reorder computes `position` = midpoint between neighbors; recompact resets positions to 1024 stride when gaps are small or after many moves.

### UI/UX (macOS 13+/iOS 16+)
- Use `.draggable` and `.dropDestination(for:)` with a `Transferable` payload.
- Compute precise insertion index via `GeometryReader` + `PreferenceKey` row frames.
- Show insertion indicator on hover; mutate model with animations disabled.

### Supabase Migration
1. Add column and index:
```
alter table public.tasks add column if not exists position double precision not null default 0;
create index if not exists tasks_user_bucket_position_idx on public.tasks (user_id, bucket_key, position asc);
```
2. Backfill per user/bucket (pseudo-SQL):
```
-- For each (user_id, bucket_key) partition, order by created_at asc
-- Assign position = row_number() * 1024 where is_completed = false and deleted_at is null
-- Completed tasks unaffected
```
3. Ensure RLS UPDATE policy covers `position` updates.

### Testing
- Drag within bucket; drag across buckets; insertion index correctness; no snap-back.
- Conflict resolution with concurrent moves; recompact idempotence.

### Done Criteria
- Visual correctness, persistence, and sync across devices verified.

