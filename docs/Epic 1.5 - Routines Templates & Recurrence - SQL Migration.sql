-- Templates table
create table if not exists templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  description text,
  labels_default jsonb not null default '[]',
  checklist_default jsonb not null default '[]',
  default_bucket text not null default 'ROUTINES',
  default_due_time time,
  priority int,
  default_duration_min int,
  status text not null default 'draft',
  version int not null default 1,
  end_after_count int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Recurrence rules table
create table if not exists recurrence_rules (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references templates(id) on delete cascade,
  rule jsonb not null,
  timezone text not null default 'UTC',
  starts_on date not null,
  ends_on date
);

-- Series table (one-to-one with template)
create table if not exists series (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references templates(id) on delete cascade,
  owner_id uuid not null,
  starts_on date not null,
  ends_on date,
  timezone text not null default 'UTC',
  status text not null default 'active',
  last_generated_at timestamptz,
  interval_weeks int not null default 1,
  anchor_weekday int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index if not exists uq_series_template on series(template_id);

-- Task alterations
alter table if exists tasks
  add column if not exists template_id uuid,
  add column if not exists series_id uuid,
  add column if not exists occurrence_date date,
  add column if not exists exception_mask jsonb not null default '{}'::jsonb;

create index if not exists idx_tasks_series_occurrence on tasks(series_id, occurrence_date);
create index if not exists idx_tasks_template on tasks(template_id);

-- Optional: RLS policies (owner isolation) — adapt to your RLS framework
-- alter table templates enable row level security;
-- create policy tpl_own on templates for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- alter table series enable row level security;
-- create policy ser_own on series for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Touch updated_at triggers (if not already present)
-- create trigger trg_templates_updated_at before update on templates for each row execute function touch_updated_at();
-- create trigger trg_series_updated_at before update on series for each row execute function touch_updated_at();


-- Reconciliation helper (one-off): merge duplicate ROUTINES roots by title per user
do $$
declare r record;
begin
  for r in
    select user_id, title
    from tasks
    where bucket_key = 'ROUTINES' and parent_task_id is null and deleted_at is null
    group by user_id, title
    having count(*) > 1
  loop
    with roots as (
      select id, created_at
      from tasks
      where user_id = r.user_id and bucket_key = 'ROUTINES' and parent_task_id is null and deleted_at is null and title = r.title
      order by created_at asc
    ), kept as (
      select id from roots limit 1
    )
    update tasks t
    set parent_task_id = (select id from kept),
        occurrence_date = coalesce(occurrence_date, (t.due_at at time zone 'UTC')::date),
        updated_at = now()
    where t.user_id = r.user_id
      and t.bucket_key = 'ROUTINES'
      and t.parent_task_id is null
      and t.deleted_at is null
      and t.title = r.title
      and t.id <> (select id from kept);

    update tasks
    set due_at = null,
        updated_at = now()
    where id = (select id from (
      select id from tasks where user_id = r.user_id and bucket_key = 'ROUTINES' and parent_task_id is null and deleted_at is null and title = r.title order by created_at asc limit 1
    ) s);
  end loop;
end $$;
