-- Epic 1.4: Ordered Board – Migration (Postgres / Supabase)
-- Idempotent: safe to run multiple times

-- 1) Add `position` column for ordered board
alter table public.tasks add column if not exists position double precision not null default 0;

-- 2) Index to support ordered queries by bucket
create index if not exists tasks_user_bucket_position_idx on public.tasks (user_id, bucket_key, position asc);

-- 3) Backfill incomplete tasks per (user_id, bucket_key) by created_at asc
with ranked as (
  select id,
         row_number() over(partition by user_id, bucket_key order by created_at asc) as rn
  from public.tasks
  where deleted_at is null and is_completed = false
)
update public.tasks t
set position = r.rn * 1024
from ranked r
where t.id = r.id;

-- 4) RLS: ensure UPDATE policies allow owners to modify `position`
-- If you already have a generic owner update policy, this is sufficient and no change is required:
-- create policy if not exists task_owner_update on public.tasks for update
--   using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Done.

