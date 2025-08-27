-- Epic 1.1: Time Buckets — Supabase Migration (Postgres)
-- Idempotent migration to create and seed time_buckets, enforce tasks.bucket_key constraint,
-- and add helpful indexes aligned with the Architecture Review.

-- 1) time_buckets table (stable keys)
create table if not exists public.time_buckets (
  key text primary key,
  name text not null
);

-- 2) Seed five fixed buckets (idempotent)
insert into public.time_buckets(key, name) values
  ('THIS_WEEK','This Week'),
  ('WEEKEND','Weekend'),
  ('NEXT_WEEK','Next Week'),
  ('NEXT_MONTH','Next Month'),
  ('ROUTINES','Routines')
on conflict (key) do nothing;

-- 3) Ensure tasks table exists with required columns (abridged). Adjust as needed if already present.
-- Note: If your schema already has tasks, skip this block or tailor ALTER TABLE statements accordingly.
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  bucket_key text not null,
  parent_task_id uuid null references public.tasks(id) on delete cascade,
  title text not null,
  description text,
  due_at timestamptz,
  recurrence_rule text,
  is_completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- 4) Enforce bucket_key references allowed values via FK to time_buckets
do $$
begin
  alter table public.tasks
    add constraint tasks_bucket_key_fkey
    foreign key (bucket_key) references public.time_buckets(key);
exception
  when duplicate_object then null;
end $$;

-- 5) Touch updated_at trigger (idempotent)
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
begin
  create trigger trg_tasks_updated_at
  before update on public.tasks
  for each row execute function public.touch_updated_at();
exception
  when duplicate_object then null;
end $$;

-- 6) RLS (ensure enabled and policy present). Adjust if already configured.
alter table public.tasks enable row level security;
do $$
begin
  create policy task_owner on public.tasks
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());
exception
  when duplicate_object then null;
end $$;

-- 7) Helpful indexes for sync and list views (idempotent)
create index if not exists idx_tasks_user_updated on public.tasks (user_id, updated_at);
create index if not exists idx_tasks_user_bucket on public.tasks (user_id, bucket_key, is_completed, due_at);

-- Done.


