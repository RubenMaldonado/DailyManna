## Feature — Routines Templates & Recurrence (Draft)

### 1) Goal
Enable users to define reusable routine templates managed in the Routines bucket. Generate weekly occurrences that adopt template defaults, allow one-off exceptions, and propagate template edits to all non-completed occurrences from today forward, without touching completed work.

### 2) Core Decisions
- Templates live in Routines (last board column). Occurrences default to Routines but can be moved elsewhere; moved fields become exceptions.
- One series per template.
- Propagation applies to all non-completed occurrences; completed tasks are never mutated by default.
- Generation window: weekly (next 7 days), “today forward” only (overdue open items are not auto-updated unless explicitly chosen by user action).
- Timezone: user’s local timezone (per-user), not per-series.
- Checklist: default unchecked per occurrence.
- End conditions: support end on date and end after N occurrences.
- No “clone to standalone” — occurrences remain associated with their template/series.

### 3) Concepts
- Template: Definition of a routine (title, description, labels, checklist defaults, default bucket, default time, priority, duration).
- Recurrence Rule: Weekly-oriented schedule (presets + advanced); interval, day-of-week, end date, end after N.
- Series: The active stream of occurrences derived from a template and its rule (one-to-one with template).
- Occurrence: Concrete task instance generated into the Routines bucket by default (can be moved).
- Exception: Field-level divergence for a single occurrence (e.g., changed title, bucket, labels) that protects that field from future propagation.
- Propagation Scope: Template edits apply to all non-completed occurrences from today forward, skipping fields overridden by exceptions.

### 4) UX
#### 4.1 Routines Bucket (Last Column)
- Sections: Templates, Upcoming (next 7 days)
- Occurrence item chips: “From Template: {name}”; show “Exception” chip when any field differs. Quick actions: View Template, Make Exception (field-level), Reapply Field, Skip Next (if next scheduled)

#### 4.2 Templates Section
- List: name, recurrence summary, next run (within 7-day preview), status (active/paused), remaining (for end-after-N)
- Actions: Edit, Pause/Resume, Duplicate, Archive

#### 4.3 Template Editor
- Fields: Title, Description, Labels, Checklist (default checks), Default bucket (fixed to Routines; visually indicated), Default time, Priority, Duration
- Recurrence: Presets (Daily, Weekdays, Weekly), Advanced (every N weeks + day-of-week), End on date, End after N
- Preview: Next 7 occurrences (dates/times in user’s timezone)
- Save: Activate (creates/updates single series), Pause

#### 4.4 Edit Propagation Dialog
- Copy: “Apply changes to all non-completed occurrences from today forward?”
- Impact: “Will update X non-completed occurrences. Completed tasks and field exceptions won’t change.”

#### 4.5 Exceptions UX
- Editing a field on an occurrence marks that field as an exception. A subtle hint appears: “Field customized. Reapply template?” with per-field reset option.

### 5) Behavior & Rules
#### 5.1 Generation
- Weekly rolling generation: fill missing occurrences for next 7 days only, respecting starts_on/ends_on/end-after-N.
- Default bucket for newly generated: Routines. If user moves an occurrence, the bucket field becomes an exception for that occurrence.

#### 5.2 Propagation
- On template edit: compute changed fields; apply to all non-completed occurrences from today forward. Skip any fields listed as exceptions on each occurrence.
- Completed occurrences are never modified by default.

#### 5.3 Series Controls
- Pause/Resume series: pausing stops generation; existing tasks remain. “Skip Next” advances next occurrence once.
- End-after-N: show remaining count; series auto-archives once count is exhausted.

### 6) Data Model (Proposed Additions)
- templates
  - id uuid (PK), owner_id uuid, name text, description text, labels_default jsonb, checklist_default jsonb,
    default_bucket text (always "ROUTINES" for now), default_due_time time, priority int, default_duration_min int,
    status text (draft/active/paused/archived), version int, created_at, updated_at, end_after_count int null

- recurrence_rules
  - id uuid (PK), template_id uuid (FK → templates), rule jsonb (weekly-oriented RRULE-like), timezone text (derived from user),
    starts_on date, ends_on date null

- series
  - id uuid (PK), template_id uuid (unique, one-to-one), owner_id uuid, starts_on date, ends_on date null,
    status text (active/paused), last_generated_at timestamptz

- tasks (additions)
  - template_id uuid null (FK → templates), series_id uuid null (FK → series), occurrence_date date null,
    exception_mask jsonb default '{}'::jsonb

Indexes:
- tasks (series_id, occurrence_date)
- tasks (template_id)
- series (template_id unique)

Integrity & RLS:
- RLS on templates, series; enforce owner consistency (series.owner_id == templates.owner_id == tasks.user_id).
- Check or constrain tasks.bucket_key ∈ {THIS_WEEK, WEEKEND, NEXT_WEEK, NEXT_MONTH, ROUTINES}; defaults for generated tasks set to ROUTINES.

### 7) Sync & Offline
- Client-driven generation in the Sync layer to preserve offline behavior and deterministic merges.
- Realtime on templates/series/tasks to coalesce into a delta pull [[Supabase Realtime via MCP, see project setup]].
- Conflict policy: last-writer-wins for scalar fields; exceptions always win over propagation unless the user explicitly re-applies the template on that field.

### 8) Algorithms (High-Level)
#### 8.1 Weekly Generator (run post-sync and on activation)
1) For each active series: compute schedule within [today, today+7]
2) For each date in that window without an instance: generate a task in Routines with template defaults
3) Update last_generated_at; if end-after-N is defined, decrement remaining and pause/archive when exhausted

#### 8.2 Template Edit Propagation
1) Compute field diff vs previous template version; bump template.version
2) Select tasks where series_id = series.id AND is_completed = false AND occurrence_date >= today
3) For each task: apply only changed fields not present in exception_mask; set propagated_at (implicit via updated_at)

#### 8.3 Occurrence Exception Handling
- On any user edit to a field, add that field key to exception_mask for that occurrence.
- “Reapply Template” removes field key(s) from exception_mask and reapplies template value(s).

### 9) Acceptance Criteria
- Templates managed inside Routines; occurrences default to Routines; can be moved, creating an exception on bucket.
- Weekly generation ensures next 7 days are present; “Skip Next” works.
- Propagation edits affect only non-completed tasks from today forward; exceptions and completed tasks remain untouched.
- End conditions (date or N) honored; remaining count shown; auto-archive at completion.
- Timezone: user’s local timezone used for generation and preview.

### 10) Performance & Limits
- Only generate within 7-day windows; lazy-generate beyond that on demand.
- Batch updates on propagation to avoid UI jank; progress feedback if >100 updates.
- Indexes for series lookups and weekly queries.

### 11) Accessibility & Copy
- Badges have VoiceOver labels: “From Template {name}”, “Has exceptions: {fields}”.
- Dialog copy is concise and descriptive; buttons are large and accessible.

### 12) Instrumentation
- Metrics: template usage, exceptions per field, pause/resume frequency, adherence (completed vs generated), remaining count trends.

### 13) Implementation Notes (Client)
- UI: Routines column adds Templates subsection and Upcoming 7-day view.
- ViewModel: surface series/template data and per-field exception state.
- Sync: hook weekly generator after each successful sync and on app activation.
- Local-first: write to SwiftData first; reconcile via periodic sync + Realtime.

### 14) Implementation Notes (Server/Supabase)
- Schema: add templates, recurrence_rules, series; ALTER tasks to add template_id, series_id, occurrence_date, exception_mask.
- RLS: owner-based policies for templates/series; ensure tasks.owner_id matches series.owner_id via constraints or triggers.
- Realtime: include templates, series, tasks in publication; app coalesces changes into delta pulls [[Realtime setup is already in place in this project]].

### 15) Migration Strategy (High-Level)
1) Deploy new schema (add tables/columns, indexes, RLS). Do not drop existing recurrence rows yet.
2) Backfill templates from existing recurrence templates (parent task referenced by Recurrence.taskTemplateId). Default template fields sourced from the parent task; set default bucket to ROUTINES; infer labels/checklist defaults from parent.
3) Create one series per template; set starts_on from existing data (e.g., min(nextScheduledAt, today)), ends_on from rule if any; timezone from user.
4) For each generated child task historically: set template_id, series_id, occurrence_date (date of due_at). Leave bucket as-is; bucket differences count as field exceptions implicitly on future propagation.
5) Switch generation to weekly (today→+7) and “today forward” propagation; completed tasks never mutated. Keep catch-up for missed upcoming dates only.
6) Mark legacy recurrence fields as deprecated; later cleanup after confidence period.

### 16) Testing Plan
- Unit: schedule computation, weekly window, exception_mask behavior, end-after-N, “today forward” filter.
- Integration: backfill migration produces correct template/series links; propagation updates only non-completed from today forward; completed remain intact.
- UI: Templates list, editor, exceptions chips, Reapply field, Skip Next.

### 17) Risks & Mitigations
- Risk: Propagation could inadvertently change exceptions. Mitigation: field-level mask guarantees protection; gated behind confirmation dialog with impact summary.
- Risk: Timezone drift across devices. Mitigation: normalize on user local TZ; preview uses device TZ; schedule stored as local-time semantic with TZ.
- Risk: Data bloat. Mitigation: generate only 7 days; archive series at end.

---
This spec aligns with the app’s foreground realtime + periodic sync strategy and Supabase RLS setup already in use.

