### Epic 2.9 — Next Week (Mon–Sun), Weekend split, Auto‑Bucketing incl. Next Month

#### Executive summary
Elevate planning by making `Next Week` a seven‑day, sectioned view; keep `This Week` split from `Weekend` for clarity; auto‑assign buckets from `dueAt` (including `NEXT_MONTH`), ensure cross‑device consistency with server logic, highlight cross‑appearances/duplicates to prompt decisions, and run a one‑time server migration to normalize existing data.

---

### Scope
- **This Week**: Mon–Fri sections. Overdue (incomplete) appears in Today only.
- **Weekend**: “This Weekend” only (upcoming Sat/Sun of the current week).
- **Next Week**: Mon–Sun sections for the week starting next Monday.
- **Unplanned (Next Week)**: tasks with `bucket_key = NEXT_WEEK` and `dueAt = NULL` render under an Unplanned section.
- **Auto‑bucketing on create/update**:
  - Mon–Fri (current week) → `THIS_WEEK`
  - Sat/Sun (current week) → `WEEKEND`
  - Mon–Sun (next week) → `NEXT_WEEK`
  - After next Sunday → `NEXT_MONTH`
  - `dueAt = NULL` → user must choose a bucket (save blocked otherwise)
- **Cross‑appearance**:
  - Week views include tasks by due date even if assigned to a different bucket; apply a distinct background to highlight this status.
  - Exception: current week Sat/Sun tasks show only in `Weekend` (not duplicated in `This Week`).
  - In `All Buckets`, duplicates are allowed and highlighted similarly.
- **Drag behavior**:
  - Drag between days (Next Week) reschedules `dueAt` to target day.
  - Drag within a day reorders only.
  - Drag into Unplanned (Next Week) clears `dueAt` and keeps `bucket_key = NEXT_WEEK`.
- **Monday flip**: server‑driven reassignment `NEXT_WEEK → THIS_WEEK` when due dates roll into the current week (user‑local time).

Out of scope: changing This Week to include weekends; weekend beyond the immediate upcoming; NLP changes.

---

### Product rules
- **Week boundaries**: Monday 00:00 to Sunday 23:59:59 in user’s local timezone.
- **This Week**: Mon–Fri; Today also shows overdue; no weekend days.
- **Weekend**: upcoming Sat/Sun of the current week only.
- **Next Week**: seven sections (Mon–Sun) starting next Monday; no “Today” label.
- **Auto‑bucketing**: applied on create and update; server is source of truth; client enforces as guard.
- **Bucket required**: no task can be saved without a bucket.
- **Cross‑appearance highlight**: distinct, subtle background from the design system to prompt user attention/decision.

---

### User stories
- As a user, I see `Next Week` as seven day sections (Mon–Sun) with headers like “Tue, Sep 16”.
- As a user, undated tasks assigned to `Next Week` appear under “Unplanned”.
- As a user, saving a task auto‑assigns the correct bucket per due date (including `NEXT_MONTH`).
- As a user, on Monday, tasks previously in `Next Week` that now fall into the current week move to `This Week` automatically.
- As a user, if a task’s due date matches a week view but is assigned elsewhere, I still see it there with a highlighted background.

---

### Acceptance criteria
- **Next Week (list & board)**:
  - Exactly seven sections for next Monday → next Sunday.
  - Group items by start‑of‑day equality; exclude completed and overdue.
  - Show Unplanned only if `bucket_key = NEXT_WEEK` and `dueAt IS NULL`.
- **Weekend**:
  - Shows only upcoming Saturday and Sunday (current week).
  - Tasks due on Sat/Sun appear only here; not duplicated in `This Week`.
- **Auto‑bucketing (create/update)**:
  - Mon–Fri this week → `THIS_WEEK`
  - Sat/Sun this week → `WEEKEND`
  - Next Mon–Sun → `NEXT_WEEK`
  - After next Sunday → `NEXT_MONTH`
  - If `dueAt IS NULL`: bucket must be chosen; otherwise validation blocks save.
- **Monday flip**:
  - Server job moves eligible tasks from `NEXT_WEEK` to `THIS_WEEK` using user‑local time windows; idempotent.
- **Cross‑appearance**:
  - Week views include due‑date‑matching tasks from other buckets; apply highlight when `assignedBucket != renderedWeek`.
  - `All Buckets` allows duplicates; highlight duplicates similarly.
- **Time events**:
  - On app foreground/timezone change, recompute sections/grouping and run a client flip check.

---

### UX
- **Headers**: localized “EEE, MMM d” (e.g., “Tue, Sep 16”).
- **Highlight**: use an attention‑container background token consistent with the current DS; rounded corners, accessible contrast.
- **Unplanned**: titled “Unplanned”; hidden if empty.
- **Empty days**: understated “No tasks scheduled”.

---

### Data & technical plan

#### Client (Swift)
- **`WeekPlanner`**
  - Add helpers for next‑week range (Mon–Sun) and “this weekend” (Sat/Sun current week).
  - Add `buildNextWeekSections(for:) -> [WeekdaySection]` returning seven sections.
- **`TaskListViewModel`**
  - Add `nextWeekSections: [WeekdaySection]` and `tasksByNextWeekDayKey: [String: [(Task, [Label])]]`.
  - Derive Next Week grouping: Mon–Sun; exclude overdue; add Unplanned logic for undated `NEXT_WEEK` tasks.
  - Auto‑bucketing guard in create/update flows (defensive mirroring of server rules).
  - Cross‑appearance filters in week views; highlight when `task.bucketKey` differs from rendered week bucket.
  - Foreground/timezone observers recompute and run a client flip check.
- **Views**
  - Create `NextWeekSectionsListView` (list mode) and `InlineNextWeekColumn` (board mode) mirroring `ThisWeek` patterns with 7 sections + Unplanned + drag.
  - Weekend view shows only Sat/Sun current week.
  - Apply highlight styling for cross‑appearance and duplicates (including `All Buckets`).

#### Server (Supabase)
- **Persist timezone**: `public.user_settings(user_id uuid primary key, timezone text not null default 'UTC')`.
- **Auto‑bucketing trigger** (insert/update of `due_at` on `public.tasks`):
  - Compute user‑local week boundaries via `AT TIME ZONE`.
  - Set `bucket_key` to `THIS_WEEK`, `WEEKEND`, `NEXT_WEEK`, or `NEXT_MONTH` per rules.
  - Enforce bucket presence when `due_at IS NULL`.
- **Monday flip**: Edge Function (service role) runs hourly; for users whose local time is Monday 00:00–03:00, update tasks `NEXT_WEEK → THIS_WEEK` where `due_at` falls in current week range.
  - Alternative: `pg_cron` daily job; Edge Function preferred for per‑user window and observability.
- **Indexes**: consider `create index on public.tasks(due_at)` and `create index on public.tasks(bucket_key)`; maintain RLS permitting only owner access; Edge Function uses service role.

#### One‑time migration
- After deploying `user_settings`, trigger, and Edge Function:
  - Backfill `user_settings.timezone` from client on next sign‑in (default to UTC if unknown).
  - Normalize existing tasks’ `bucket_key` from `due_at` using user timezone.
  - For tasks with `due_at IS NULL` and missing/invalid `bucket_key`, set `bucket_key = NEXT_MONTH` to satisfy “bucket required”.

#### Sync & perf
- Client sends user timezone during auth/bootstrap.
- Foreground sync re‑derives sections and re‑requests view context.
- If filtering locally becomes heavy, add repository queries by date range across buckets.

---

### Supabase implementation details (SQL sketches)

Auto‑bucketing trigger:
```sql
create or replace function public.set_bucket_from_due_at()
returns trigger as $$
declare
  tz text;
  local_due timestamp without time zone;
  local_now timestamp without time zone;
  week_monday date;
  week_friday date;
  week_saturday date;
  week_sunday date;
  next_monday date;
  next_sunday date;
begin
  if new.due_at is null then
    if new.bucket_key is null then
      raise exception 'bucket_key required when due_at is null';
    end if;
    return new;
  end if;

  select coalesce(u.timezone, 'UTC') into tz
  from public.user_settings u
  where u.user_id = new.user_id;

  local_due := (new.due_at at time zone tz);
  local_now := (now() at time zone tz);

  week_monday := (date_trunc('week', local_now + interval '1 day')::date - interval '1 day')::date;
  week_friday := (week_monday + interval '4 day')::date;
  week_saturday := (week_monday + interval '5 day')::date;
  week_sunday := (week_monday + interval '6 day')::date;

  next_monday := (week_monday + interval '7 day')::date;
  next_sunday := (week_sunday + interval '7 day')::date;

  if local_due::date between week_monday and week_friday then
    new.bucket_key := 'THIS_WEEK';
  elsif local_due::date in (week_saturday, week_sunday) then
    new.bucket_key := 'WEEKEND';
  elsif local_due::date between next_monday and next_sunday then
    new.bucket_key := 'NEXT_WEEK';
  elsif local_due::date > next_sunday then
    new.bucket_key := 'NEXT_MONTH';
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_set_bucket_from_due_at on public.tasks;
create trigger trg_set_bucket_from_due_at
before insert or update of due_at on public.tasks
for each row execute function public.set_bucket_from_due_at();
```

Scheduled Monday flip (Edge Function performs this SQL for users in Monday 00:00–03:00 local time):
```sql
update public.tasks t
set bucket_key = 'THIS_WEEK'
from public.user_settings u
where t.user_id = u.user_id
  and t.bucket_key = 'NEXT_WEEK'
  and (t.due_at at time zone u.timezone)::date between
      (date_trunc('week', (now() at time zone u.timezone) + interval '1 day')::date - interval '1 day') and
      (date_trunc('week', (now() at time zone u.timezone) + interval '1 day')::date - interval '1 day' + interval '6 day');
```

One‑time normalization migration (idempotent, simplified outline):
```sql
-- Set NEXT_MONTH for undated tasks missing bucket
update public.tasks set bucket_key = 'NEXT_MONTH'
where due_at is null and (bucket_key is null or bucket_key not in ('THIS_WEEK','WEEKEND','NEXT_WEEK','NEXT_MONTH','ROUTINES'));

-- Normalize dated tasks based on user timezone
-- (Use a joined CTE computing week bounds per user, then case on local due date)
```

---

### QA plan
- **Unit**: week range math; weekend exception; next‑week sections; NEXT_MONTH cutoff; overdue‑in‑Today only.
- **ViewModel**: auto‑bucketing guard; Unplanned grouping; cross‑appearance highlight; client flip checks.
- **UI**: headers; drag across days; drag to Unplanned clears date; highlight visibility.
- **Integration**: trigger on insert/update; scheduled flip; one‑time migration effects.
- **Perf**: verify list/board responsiveness; add indexes if needed.

---

### Analytics
- Counts of auto‑bucket assignments by category.
- Number of highlighted duplicates in week and All‑Buckets views.
- Monday flip moved count per user.

---

### Rollout
- Feature flag: `feature.nextWeekSections` enabled after QA.
- Deploy DB objects (user_settings, trigger, Edge Function), run one‑time migration, then ship client updates.

---

### Risks & mitigations
- **Timezone accuracy**: require `user_settings.timezone`; default to UTC; let client update it at sign‑in and on change.
- **Duplicate visibility**: intentional to prompt decisions; highlight explains state.
- **Flip race conditions**: run server flip outside interactive edits; client reconciles on foreground.

---

### Implementation plan & todos

#### Phase 1 — Client foundation
1) Extend `WeekPlanner` with next‑week (Mon–Sun) and this‑weekend helpers.
2) Add Next Week sections and grouping to `TaskListViewModel`.
3) Implement `NextWeekSectionsListView` and `InlineNextWeekColumn`.
4) Implement cross‑appearance filters and highlight in week and `All Buckets` views.
5) Enforce client auto‑bucketing and bucket‑required validation on create/update.

#### Phase 2 — Server consistency (Supabase)
6) Add `public.user_settings` with `timezone` and indexes.
7) Create `set_bucket_from_due_at` function and trigger on `public.tasks`.
8) Implement Edge Function for Monday flip and schedule it (hourly windowed).
9) Run one‑time migration to normalize existing `bucket_key` values.

#### Phase 3 — QA & rollout
10) Add tests: unit (dates), VM grouping, UI drag/unplanned, integration (trigger/flip).
11) Rollout behind `feature.nextWeekSections`; add analytics events; update docs.

Corresponding working todos exist in the project task list to track these steps.


