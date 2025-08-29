-- Epic 2.1: Labels & Filtering — Supabase Migration (Postgres)
-- Idempotent + upgrade-safe migration. Handles both fresh installs and projects that
-- already created tables without tombstones/timestamps/PK shape.

-- Prereq: UUID generator for surrogate ids
create extension if not exists pgcrypto;

-- 1) labels table
create table if not exists public.labels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  name text not null,
  -- normalized key for case-insensitive uniqueness
  name_key text generated always as (lower(trim(name))) stored,
  color text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- 1a) If table existed already, ensure required columns are present
alter table if exists public.labels
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists name_key text generated always as (lower(trim(name))) stored;

-- Unique (user_id, name) for active labels only (allow reuse when a label is tombstoned)
-- Enforce global uniqueness using normalized key (no partial index, supports upsert)
do $$
begin
  if exists (
    select 1 from pg_indexes
    where schemaname='public' and indexname='uniq_labels_user_name_active'
  ) then
    drop index public.uniq_labels_user_name_active;
  end if;
  if not exists (
    select 1
    from information_schema.table_constraints
    where table_schema='public' and table_name='labels' and constraint_name='labels_user_id_name_key'
  ) then
    alter table public.labels add constraint labels_user_id_name_key unique (user_id, name_key);
  end if;
end $$;

-- 2) task_labels junction table (soft-delete capable)
create table if not exists public.task_labels (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  label_id uuid not null references public.labels(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- 2a) If table existed already with a composite PK and without tombstones/timestamps,
-- bring it to the expected shape.
alter table if exists public.task_labels
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists id uuid default gen_random_uuid();

-- Switch primary key to surrogate id if needed
do $$
declare
  pk_name text;
begin
  select tc.constraint_name into pk_name
  from information_schema.table_constraints tc
  where tc.table_schema='public' and tc.table_name='task_labels' and tc.constraint_type='PRIMARY KEY'
  limit 1;

  if pk_name is not null then
    -- Only drop if PK is not already on id
    if not exists (
      select 1 from information_schema.key_column_usage k
      where k.constraint_name = pk_name and k.table_schema='public' and k.table_name='task_labels' and k.column_name='id'
    ) then
      execute 'alter table public.task_labels drop constraint ' || quote_ident(pk_name);
    end if;
  end if;

  -- Ensure PK on id
  if not exists (
    select 1
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
    where tc.table_schema='public' and tc.table_name='task_labels' and tc.constraint_type='PRIMARY KEY' and kcu.column_name='id'
  ) then
    alter table public.task_labels add constraint task_labels_pkey primary key (id);
  end if;
end $$;

-- Enforce one active link per (task,label), while allowing reinsertion after soft-delete
-- Replace partial unique index with full unique constraint to support ON CONFLICT
do $$
begin
  if exists (select 1 from pg_indexes where schemaname='public' and indexname='uniq_task_labels_active') then
    drop index public.uniq_task_labels_active;
  end if;
  begin
    alter table public.task_labels add constraint task_labels_task_id_label_id_key unique (task_id, label_id);
  exception when duplicate_object then null; end;
end $$;

-- Helpful indexes for queries
create index if not exists idx_labels_user_updated on public.labels (user_id, updated_at);
create index if not exists idx_task_labels_task on public.task_labels (task_id);
create index if not exists idx_task_labels_label on public.task_labels (label_id);
create index if not exists idx_task_labels_user on public.task_labels (user_id);

-- 3) updated_at touch trigger (shared)
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
begin
  create trigger trg_labels_updated_at
  before update on public.labels
  for each row execute function public.touch_updated_at();
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create trigger trg_task_labels_updated_at
  before update on public.task_labels
  for each row execute function public.touch_updated_at();
exception
  when duplicate_object then null;
end $$;

-- 4) RLS policies
alter table public.labels enable row level security;
alter table public.task_labels enable row level security;

do $$
begin
  create policy labels_owner on public.labels
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create policy task_labels_owner on public.task_labels
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());
exception
  when duplicate_object then null;
end $$;

-- 5) Realtime publication
do $$
begin
  alter publication supabase_realtime add table public.labels;
exception when duplicate_object then null; end $$;

do $$
begin
  alter publication supabase_realtime add table public.task_labels;
exception when duplicate_object then null; end $$;

-- Done.


