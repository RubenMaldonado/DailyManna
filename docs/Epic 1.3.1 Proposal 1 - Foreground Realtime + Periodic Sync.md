## Proposal 1 — Foreground Realtime + Periodic Sync (Supabase Setup Guide)

This guide explains every step to enable reliable foreground sync using Supabase Realtime, delta pulls, and periodic/activation sync triggers.

### Prerequisites
- Supabase project created and reachable.
- `tasks` and `labels` tables provisioned as per Epic 1.1 (with `updated_at` trigger and RLS owner policy).
- App configured with Supabase URL and Anon key in `Supabase-Config.plist`.

### 1) Verify schema (SQL)

Run in Supabase SQL editor:

```sql
-- tasks essential columns
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'tasks'
order by ordinal_position;

-- labels essential columns
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'labels'
order by ordinal_position;

-- triggers for updated_at
select tgname, pg_get_triggerdef(t.oid)
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
where c.relname in ('tasks','labels') and not t.tgisinternal;

-- RLS policies
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename in ('tasks','labels');

-- helpful indexes
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename in ('tasks','labels');
```

Expectations:
- `updated_at` trigger exists on both tables (or `updated_at` is reliably set server-side on updates).
- RLS policy ensures only owner (`user_id = auth.uid()`) can read/write their rows.
- Index on `(user_id, updated_at)` exists for fast delta reads.

### 2) Enable Realtime for tables

- In Supabase Studio → Realtime → Tables:
  - Toggle ON for `public.tasks` and `public.labels`.
  - Scope: `INSERT`, `UPDATE`, `DELETE`.
  - Confirm it shows “Realtime enabled” next to both tables.

Notes:
- Realtime respects RLS. With owner policy, only the authenticated user will receive their own changes.

### 3) Authentication configuration

- Studio → Authentication → URL Configuration:
  - Add the app callback URL (matches `SupabaseConfig.shared.redirectToURL`, e.g., `com.rubentena.DailyManna://auth-callback`).
- Studio → Project Settings → API:
  - Copy `Project URL` and `anon` key and ensure they match your `Supabase-Config.plist`.

### 4) Delta pull behavior (server clock as truth)

The app:
- Pulls with `updated_at >= lastCheckpoint - 120 seconds` to cover clock skew/missed events.
- Updates checkpoints to the max server `updated_at` seen after each pull.

Server expectations:
- `updated_at` is updated server-side on every mutation. If not, ensure the `touch_updated_at` trigger is in place on both tables:

```sql
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
begin
  create trigger trg_tasks_updated_at before update on public.tasks
  for each row execute function public.touch_updated_at();
exception when duplicate_object then null; end $$;

do $$
begin
  create trigger trg_labels_updated_at before update on public.labels
  for each row execute function public.touch_updated_at();
exception when duplicate_object then null; end $$;
```

### 5) RLS policy (owner-only access)

Ensure both tables have owner policies:

```sql
alter table public.tasks enable row level security;
do $$
begin
  create policy task_owner on public.tasks
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;

alter table public.labels enable row level security;
do $$
begin
  create policy label_owner on public.labels
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;
```

### 6) Testing checklist

1) Realtime smoke test
```sql
-- Insert a task for your authenticated user (replace UUID)
insert into public.tasks (user_id, bucket_key, title, is_completed)
values ('<AUTH_UID>', 'THIS_WEEK', 'Realtime test', false);
```
- Expect: App (foreground) refreshes within ~1s (debounce window), or at worst the next 60s periodic sync.

2) Delta pull
```sql
update public.tasks set title = 'Delta test', updated_at = now()
where user_id = '<AUTH_UID>'
order by updated_at desc limit 1;
```
- Expect: Device receives update quickly via realtime or on next activation/periodic.

3) Tombstone visibility
```sql
update public.tasks set deleted_at = now() where user_id = '<AUTH_UID>' and deleted_at is null limit 1;
```
- Expect: Item disappears (soft-deleted) after next pull.

### 7) Troubleshooting

- Not receiving changes:
  - Verify Realtime toggled ON for both tables.
  - Confirm you’re logged in and `auth.uid()` matches `user_id` of inserted rows.
  - Check RLS policies; owner policy must allow SELECT/UPDATE on your rows.
- Deltas not returning rows:
  - Verify `updated_at` advances on updates.
  - Check your checkpoint and confirm the overlap window.
- Slow queries:
  - Ensure `(user_id, updated_at)` index exists.
  - Confirm filters also exclude `deleted_at` when needed.

### 8) Security considerations

- Keep using Anon key in the client.
- Do not expose service role key in the app; use it only in trusted environments (e.g., Edge Functions).
- RLS must remain enabled and correct to prevent data leakage across users.

### 9) Optional enhancements

- Add targeted upserts on realtime events to avoid full delta pulls.
- Introduce silent push (APNs) via Supabase Edge Functions to nudge background devices.


