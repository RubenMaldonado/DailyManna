## Implementation Plan — Routines Templates & Recurrence

This plan delivers the feature described in `Feature - Routines Templates & Recurrence.md`, including schema migration, data backfill, client changes, UI, sync logic, testing, and rollout.

### 0) Guiding Constraints
- Weekly generation window (today → +7 days). “Today forward” on propagation.
- One series per template. Default bucket for generated tasks is `ROUTINES`.
- Completed tasks are never mutated by propagation.
- Timezone: user’s local timezone.

### 1) Database (Supabase) — Schema Migration
1.1 Create tables
- `templates` (see spec): versioned template defaults, end_after_count
- `recurrence_rules` (weekly-oriented rule json), `series` (one-to-one with template)

1.2 Alter `tasks`
- Add columns: `template_id uuid null`, `series_id uuid null`, `occurrence_date date null`, `exception_mask jsonb not null default '{}'::jsonb`

1.3 Integrity & RLS
- Owner RLS on `templates`, `series` (policy: `owner_id = auth.uid()`).
- Constraint/triggers to ensure `tasks.user_id = series.owner_id` when `series_id` is set; `series.template_id` must belong to same owner.
- Keep existing tasks RLS intact.

1.4 Indexes
- `create index on tasks(series_id, occurrence_date)`
- `create index on tasks(template_id)`
- `create unique index on series(template_id)`

1.5 Realtime publication
- Add `templates`, `series` to the existing publication so the app receives change hints.

Deliverable: SQL migration file in `docs/` and applied via Supabase MCP after cost confirmation [[uses existing MCP workflow]].

### 2) Data Backfill Procedure
2.1 Inventory legacy recurrence
- Read all `Recurrence` rows; group by `taskTemplateId`.

2.2 Create `templates`
- For each unique `taskTemplateId`:
  - Load parent template task (title, description, labels).
  - Create a `template` with defaults (default_bucket = `ROUTINES`; infer default_due_time from parent’s typical due time if present; priority/duration from task if modeled; labels/checklist defaults from task if present).

2.3 Create `series`
- One `series` per `template` with `starts_on = min(today, nextScheduledAt ?? today)`, `status` from legacy recurrence, `ends_on` if derivable from rule.

2.4 Map rule to `recurrence_rules`
- Persist weekly rule JSON (interval, weekday); timezone from user profile.

2.5 Link historical instances
- For each child task with `parentTaskId == taskTemplateId`:
  - Set `template_id`, `series_id`, `occurrence_date = date(due_at)`.
  - Do not change `bucket_key`; if not `ROUTINES`, accept as-is. Future propagation treats bucket as changed only when edited again; optional: pre-populate `exception_mask.bucket` for tasks in the next 7 days to avoid unintended bucket resets.

2.6 Validation
- Sanity checks: counts per template; random samples verifying links; ensure completed tasks unaffected.

Deliverable: Backfill script run from the app (admin mode) or SQL/Edge function; dry-run first, then apply.

### 3) Client — Domain & Data Layer
3.1 Domain models
- Add `Template`, `Series`, `TemplateVersion` (if needed), and update `Task` with optional `templateId`, `seriesId`, `occurrenceDate`, `exceptionMask` (domain type with field keys).

3.2 SwiftData models
- Add `TemplateEntity`, `SeriesEntity`; extend `TaskEntity` with new columns; migration step to evolve schema.

3.3 Repositories
- Define `TemplatesRepository`, `SeriesRepository`, update `TasksRepository` to support new columns and weekly queries by `series_id` and date window.
- Supabase transport: endpoints for CRUD on `templates`/`series`; typed mapping.

3.4 Use cases
- `TemplatesUseCases`: create/update, version bump, propagate edits.
- `SeriesUseCases`: pause/resume, skip next, compute next 7 days (delegates to engine), generation bookkeeping.

3.5 Recurrence Engine
- Extend to compute day-of-week windows and next-7 schedule respecting starts/ends/end-after-N in user’s timezone.

### 4) Client — Sync & Generation
4.1 Weekly generator
- After every successful sync and on scene activation, for each active series:
  - Compute days in [today, today+7].
  - For each missing date, create a task in `ROUTINES` with template defaults; set `templateId`, `seriesId`, `occurrenceDate`.
  - Advance `last_generated_at` and decrement remaining for end-after-N; auto-archive when done.

4.2 Propagation path
- On template edit:
  - Compute diff vs previous version.
  - Query tasks where `seriesId = series.id AND isCompleted = false AND occurrenceDate >= today`.
  - For each, apply diff only to fields not in `exceptionMask`; write updates.

4.3 Legacy coexistence & flag
- Feature flag protects new generator and propagation code. During rollout, if a task is already linked to a `series`, skip legacy catch-up.

### 5) UI — Routines Column & Editor
5.1 Routines column
- Add Templates subsection: list templates (name, rule summary, next run in 7-day preview, status, remaining).
- Add Upcoming (7-day) grouping rendering tasks with chips: “From Template {name}”, “Exception”.

5.2 Template Editor
- Screen for creating/editing templates: fields from spec, recurrence presets, end-after-N, preview next 7.
- Save triggers propagation dialog with impact summary.

5.3 Task row affordances
- Quick actions: View Template, Make Exception (toggle per-field), Reapply Field, Skip Next (if next occurrence).

### 6) Testing
6.1 Unit tests
- Recurrence engine next-7; “today forward” filters; end-after-N; exception masking; propagation skipping completed.

6.2 Integration tests
- Backfill correctness: links from legacy recurrence → template/series; weekly generator idempotency; propagation respects masks.

6.3 UI tests
- Templates list/editor flows; exception chip behaviors; Skip Next and Pause/Resume.

### 7) Rollout & Ops
7.1 Feature flag
- Gate generator/propagation and new UI. Ship dark-launched; enable for internal builds first.

7.2 Telemetry
- Log counts: generated instances per day, propagation updates, exception frequency, end-after-N remaining.

7.3 Migration sequence
- Apply schema (Supabase), release app with backfill module behind an internal toggle, run backfill for test accounts, verify, then run for all users.
- Enable new generator/propagation for a subset, then 100%. Keep legacy code for one release as fallback.

7.4 Cleanup
- After confidence period, remove legacy recurrence generation and entities; optionally drop deprecated columns (e.g., `tasks.recurrence_rule`).

### 8) Tasks & Estimates (high-level)
- DB schema & RLS: 0.5–1d
- Backfill tool & dry-run: 1–2d
- Domain + repositories + SwiftData migration: 1–2d
- Weekly generator + propagation logic: 1–2d
- UI (Templates, Editor, chips, actions): 2–3d
- Tests (unit, integration, UI): 1–2d
- Rollout, telemetry, cleanup: 0.5–1d

### 9) Risks
- Mis-propagation: mitigated by exception_mask and explicit impact dialog.
- TZ inconsistencies: centralize TZ computation; add tests.
- Data bloat: limited by next-7 generation; archive series at end.

---
Deliverables in this plan will be committed incrementally with feature flags and verified via existing realtime + periodic sync pipeline.

