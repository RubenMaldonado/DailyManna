# Daily Manna - Development Roadmap & Epic Prioritization

## Overview

This document outlines a prioritized, iterative development approach for Daily Manna, focusing on delivering value incrementally while building a robust foundation for future enhancements. The roadmap is structured around epics that can be developed, tested, and released independently, following the principle of "working software over comprehensive documentation."

## Development Philosophy

**Iterative Approach**: Start simple, validate early, iterate quickly
- **Phase 0**: Foundation & Infrastructure
- **Phase 1**: Core MVP with Essential Features
- **Phase 2**: Enhanced User Experience
- **Phase 3**: Advanced Features & Polish

---

## Phase 0: Foundation & Infrastructure (Weeks 1-3)

### Epic 0.1: Project Architecture Setup | COMPLETED
**Priority**: Critical
**Estimated Effort**: 1 week
**Goal**: Establish scalable, maintainable codebase structure

**User Stories**:
- As a developer, I need a modular project structure that supports future scaling
- As a developer, I need clear separation of concerns between UI, domain, and data layers

**Acceptance Criteria**:
- [x] Refactor existing Xcode project into modular packages:
  - `App` (main target)
  - `Domain` (pure Swift business logic)
  - `Data` (SwiftData models and repositories)
  - `DesignSystem` (UI components and tokens)
  - `Features` (feature-specific UI modules)
- [x] Implement Repository pattern with protocols
- [x] Set up dependency injection container
- [x] Create basic logging and error handling infrastructure

### Epic 0.2: Supabase Integration & Authentication | COMPLETED
**Priority**: Critical
**Estimated Effort**: 1.5 weeks
**Goal**: Connect app to Supabase backend with secure authentication

**User Stories**:
- As a user, I can sign in with Apple to access my tasks securely
- As a user, I can sign in with Google as an alternative authentication method
- As a developer, I need secure session management and token refresh

**Acceptance Criteria**:
- [x] Set up Supabase project with development environment
- [x] Implement database schema as defined in data model
- [x] Create RLS policies for user isolation
- [x] Integrate Supabase Swift SDK
- [x] Implement Sign in with Apple
- [x] Implement Google OAuth
- [x] Set up secure session management with Keychain
- [x] Create authentication state management

### Epic 0.3: Swift Data Models & Local Storage | COMPLETED
**Priority**: Critical
**Estimated Effort**: 1 week
**Goal**: Establish local-first data foundation with SwiftData

**User Stories**:
- As a developer, I need SwiftData models that mirror the server schema
- As a user, my app should work offline and sync when connected

**Acceptance Criteria**:
- [x] Replace existing `Item` model with proper domain models:
  - `Task` model with all required fields
  - `Label` model
  - `TimeBucket` model (seeded data)
- [x] Implement SwiftData migrations strategy
- [x] Add sync metadata fields (remoteID, updatedAt, deletedAt)
- [x] Create basic repository implementations for local storage
- [x] Implement UUID generation for offline-first approach

### Epic 0.4: Supabase MCP Server Integration | COMPLETED
**Priority**: High
**Estimated Effort**: 0.5–1 week
**Goal**: Enable AI-assisted development by integrating the official Supabase MCP server so we can design/modify database schema, manage projects/branches, run SQL, fetch config, and automate Supabase tasks directly from Cursor.

**Context & Reference**:
- Supabase announcement: [Supabase MCP Server](https://supabase.com/blog/mcp-server)
- Setup guide: `docs/Epic 0.4 - Supabase MCP Setup - Cursor.md`

**User Stories**:
- As a developer, I can connect Cursor to Supabase using MCP and my PAT to automate routine backend ops.
- As a developer, I can run SQL, design tables, and manage migrations from Cursor via MCP tools.
- As a developer, I can fetch project `url` and `anon key` and generate client types through tools.
- As a developer, I can create database branches safely and switch them for development.
- As a developer, I can retrieve logs to debug integration issues without leaving Cursor.

**Acceptance Criteria**:
- [x] MCP server configured in `.cursor/mcp.json` with `@supabase/mcp-server-supabase@latest` and PAT.
- [x] PAT is stored securely and not committed; add `.gitignore`/secrets hygiene note.
- [x] Step-by-step setup doc created: `docs/Epic 0.4 - Supabase MCP Setup - Cursor.md` (Cursor on macOS) with:
  - Installing MCP server via `npx` and adding JSON.
  - Creating a Supabase Personal Access Token; scoping guidance and rotation.
  - Verifying tool discovery and a smoke test (e.g., `list_tables`, `execute_sql`).
  - Notes for Windows/Linux JSON variants.
- [x] Working examples documented for common MCP activities:
  - Design tables and track via migrations (create/alter/drop within a dev branch).
  - Execute SQL for reports and data checks (read-only and cautious writes).
  - Create and manage database branches; pause/restore projects safely.
  - Fetch project configuration (URL, anon key) for local config.
  - Retrieve logs for debugging (auth, database, realtime) during development.
  - Generate TypeScript types (for web tooling/docs).
- [x] Safety guidance included: prefer branches, avoid destructive ops in prod, confirmation prompts, rollback patterns.
- [x] "How we’ll use MCP in Daily Manna" section mapping activities to current epics (e.g., Labels schema, RLS/policies, triggers, migrations).
- [x] Cross-links added between this epic and the setup doc.

**Milestones**:
- Day 1: Configure `.cursor/mcp.json`, create PAT, verify connection; smoke-test tools.
- Day 2: Author setup guide with CLI snippets; add usage recipes for our workflow.
- Day 3: Trial-run: use MCP to inspect current schema, list tables, and export a migration diff in a dev branch. Update docs with lessons learned.

**Definition of Done**:
- MCP tools are discoverable and usable from Cursor; team can perform listed activities safely.
- Setup guide exists, is accurate, and linked from the roadmap.
- No secrets are committed; secrets guidance documented.

---

## Phase 1: Core MVP - Essential Task Management (Weeks 4-8)

### Epic 1.1: Time Buckets Foundation | COMPLETED
**Priority**: High
**Estimated Effort**: 1 week
**Goal**: Implement the core organizational structure of Daily Manna

**User Stories**:
- As a user, I can see the five fixed time buckets (THIS WEEK, WEEKEND, NEXT WEEK, NEXT MONTH, ROUTINES)
- As a user, I can view tasks organized by bucket
- As a user, I understand which bucket is for what timeframe

**Acceptance Criteria**:
- [x] Create TimeBucket enum with five fixed values
- [x] Implement bucket-based navigation UI
- [x] Design bucket header components with counts
- [x] Seed database with fixed bucket data
- [x] Create basic bucket selection UI

### Epic 1.2: Basic Task CRUD Operations | COMPLETED
**Priority**: High
**Estimated Effort**: 2 weeks
**Goal**: Users can create, read, update, and delete tasks

**User Stories**:
- As a user, I can add a new task with a title and bucket
- As a user, I can edit task details
- As a user, I can mark tasks as complete
- As a user, I can delete tasks
- As a user, I can move tasks between buckets

**Acceptance Criteria**:
- [x] Implement task creation form with bucket selection
- [x] Create task list view showing tasks by bucket
- [x] Add task editing capabilities
- [x] Implement task completion with visual feedback
- [x] Add task deletion with confirmation
- [x] Enable drag-and-drop between buckets (iOS/macOS appropriate)
- [x] Add basic task details (title, description, due date)

### Epic 1.3: Basic Sync Implementation | COMPLETED
**Priority**: High
**Estimated Effort**: 2 weeks
**Goal**: Ensure data consistency across devices
**Description**: Bidirectional sync with offline-first UX. Push local changes, pull deltas using server `updated_at` with a 120s overlap window, and persist per-user checkpoints. Triggers: initial sync after sign-in/first load, activation sync when the app becomes active, periodic sync every 60s while foregrounded, and foreground Realtime hints. Conflict resolution is last-write-wins by server time; deletions propagate via `deleted_at` tombstones. UI shows syncing status and auto-refreshes after completion. Debug-only Settings allow bulk delete (local + Supabase) and sample task generation for testing.

**User Stories**:
- As a user, changes I make on one device appear on my other devices
- As a user, I can work offline and changes sync when I reconnect
- As a user, I don't lose data due to sync conflicts

**Acceptance Criteria**:
- [x] Implement basic push/pull sync strategy (tasks and labels; tombstones via `deleted_at`)
- [x] Create sync orchestrator with delta queries (`updated_at >= last_checkpoint - 120s`)
- [x] Persist per-user checkpoints in local store (max server `updated_at`)
- [x] Handle offline mutations queue (`needsSync` flags; local-first repos)
- [x] Implement last-write-wins conflict resolution (server `updated_at` as source of truth)
- [x] Add sync status indicators in UI and auto-refresh post-sync
- [x] Create retry logic for failed syncs (exponential backoff with jitter)
- [x] Implement initial, activation, and periodic (60s) sync triggers
- [x] Enable Supabase Realtime via publication and foreground subscribe hooks
- [x] Provide debug-only Settings for bulk delete and sample data generation

### Epic 1.4: Ordered Board (Drag-and-drop Reordering)
**Priority**: Medium-High
**Estimated Effort**: 1 week
**Goal**: Precise in-bucket and cross-bucket reordering with persistent order
**Status**: COMPLETED

**User Stories**:
- As a user, I can reorder tasks within a bucket by drag-and-drop
- As a user, I can drop a task in an exact position across buckets
- As a user, new tasks appear at the bottom of a bucket
- As a user, completed tasks stay ordered by completion date

**Acceptance Criteria**:
- [x] Add `position` field and migrations (local + Supabase)
- [x] Implement precise drop index and insertion indicator
- [x] Optimistic local reorder (no implicit animations)
- [x] Persist `position` and sync changes
- [x] Recompact positions as needed (helper implemented)

**References**:
- `docs/Epic 1.4 - Ordered Board.md`
- `docs/Epic 1.4 - Ordered Board Migration.sql`

---

## Phase 2: Enhanced User Experience (Weeks 9-14)

### Epic 2.1: Labels & Filtering System
**Priority**: Medium-High
**Estimated Effort**: 2 weeks
**Goal**: Add flexible organization layer across buckets

**User Stories**:
- As a user, I can create and assign colored labels to tasks
- As a user, I can filter tasks by labels within and across buckets
- As a user, I can manage my label library

**Acceptance Criteria**:
- [x] Implement label creation and management
- [x] Add label assignment to tasks (many-to-many)
- [x] Create label filtering UI
- [x] Implement label color system
- [x] Add label chips to task display
- [x] Create saved filter views
- [x] Sync label data across devices

#### Implementation Plan
- **Database & RLS**
  - Create/verify `labels` and `task_labels` with `updated_at` triggers, tombstones, indexes, and Realtime publication.
  - Enforce `(user_id, name)` unique on active labels; simple RLS: `user_id = auth.uid()` on both tables.
  - Reference migration: `docs/Epic 2.1 - Labels & Filtering Migration.sql`.
- **Local Storage (SwiftData)**
  - Use `LabelEntity` and `TaskLabelEntity` (junction) for local-first CRUD and queries.
  - Add fetch helpers: labels for task; tasks for label(s); filter predicates for ANY/ALL.
- **Repositories & Sync**
  - Local: extend `SwiftDataLabelsRepository` with assign/unassign and query helpers.
  - Remote: extend `SupabaseLabelsRepository` and `SupabaseTasksRepository` (or a small `SupabaseTaskLabels` helper) to upsert labels and link/unlink in `task_labels`.
  - Sync: update `SyncService` to delta pull/push labels and `task_labels` with 120s overlap; debounce Realtime to a pull.
- **Design System & UI**
  - Colors: add curated label color tokens in `DesignSystem/Tokens/Colors.swift`.
  - Chips: enhance `DesignSystem/Components/LabelChip.swift` for display/interactive variants and overflow (`+N`).
  - TaskCard: render chips under title; tap-to-filter; long-press to edit labels.
  - Label Management: list, search, create, edit (name/color), delete (tombstone) with undo.
  - Assignment UI: multi-select with search and create-on-the-fly in task create/edit.
  - Filtering UI: global multi-label picker (ANY default, ALL optional), active filter bar with clear.
  - Saved Filters: SwiftData entity (`name`, `labelIDs`, `matchMode`), quick menu to apply/rename/delete.
- **Testing & Perf**
  - Unit: repository CRUD, label set union/unlink, LWW (name/color), filter predicates.
  - Integration: Supabase RLS/CRUD for labels and links, delta sync, Realtime hint path.
  - UI: label CRUD, assign/unassign, filter and saved views flows; offline-first behavior.
  - Performance: indexes validated; smooth lists at 1k–5k tasks; debounced searches.

#### Milestones (est. 2 weeks)
- Days 1–2: DB/RLS/index/Realtime verification; remote/local repos APIs; DTOs.
- Days 3–4: SwiftData queries/migrations; `SyncService` for labels + `task_labels`.
- Days 5–7: Chips, color tokens, label management, assignment UI.
- Days 8–9: Filtering + saved filters across list/board; polish.
- Day 10: Tests, perf, accessibility/haptics; docs & feature flag prep.

#### Definition of Done
- CRUD for labels with colors; assignment from task flows; chips visible in cards.
- Multi-label filtering (ANY/ALL) across `TaskListView` and `BucketBoardView`; saved filters.
- Robust delta sync + Realtime hints for labels and `task_labels`; tombstones respected.
- Tests green; no linter issues; acceptable performance and accessibility.


### Epic 2.2: Subtasks & Rich Descriptions
**Priority**: Medium
**Estimated Effort**: 1.5 weeks
**Goal**: Enable detailed task breakdown and context

**User Stories**:
- As a user, I can break large tasks into smaller subtasks
- As a user, I can add rich descriptions with formatting and links
- As a user, I can track progress on complex tasks

**Acceptance Criteria**:
- [x] Implement hierarchical task structure (parent/child)
- [x] Create subtask UI with progress indicators
- [x] Add rich text editing for descriptions (Markdown support)
- [x] Implement subtask completion logic
- [x] Add subtask drag-and-drop reordering
- [x] Sync subtask relationships

### Epic 2.3: Due Dates & Scheduling | COMPLETED
**Priority**: Medium
**Estimated Effort**: 1 week
**Goal**: Add time-specific task management within buckets

**User Stories**:
- As a user, I can set specific due dates and times for tasks
- As a user, I can see overdue tasks clearly
- As a user, I can sort tasks by due date within buckets

**Acceptance Criteria**:
- [x] Add due date/time picker to task creation/editing
- [x] Implement due date display in task lists
- [x] Create overdue task indicators
- [x] Add due date-based sorting options
- [x] Implement basic reminder system (local notifications)

### Epic 2.4: macOS-Specific Enhancements
**Priority**: Medium
**Estimated Effort**: 1.5 weeks
**Goal**: Optimize experience for macOS users

**User Stories**:
- As a macOS user, I can use keyboard shortcuts for common actions
- As a macOS user, I have right-click context menus
- As a macOS user, the app feels native to macOS

**Acceptance Criteria**:
- [ ] Implement keyboard shortcuts (⌘N for new task, etc.)
- [ ] Add context menus for tasks and buckets
- [ ] Optimize layout for macOS (menu bar, window management)
- [ ] Add Focus and tab navigation
- [ ] Implement proper macOS window restoration

### Epic 2.5: Task Composer 2.0 (Add Task Window)
**Priority**: Medium-High
**Estimated Effort**: 2 weeks
**Goal**: Redesign the add task experience as a fast, chip-driven composer (iOS + macOS), inspired by best-in-class apps while matching Daily Manna’s buckets/labels model.

**User Stories**:
- As a user, I can add a task quickly with title only and submit in one keystroke.
- As a user, I can add details inline using chips: Labels, Priority, Date/Time, Reminders, Repeat.
- As a user, I can pick the bucket (project) at the bottom with quick search and recents.
- As a macOS user, I can do everything with the keyboard (shortcuts, arrows, type-to-search).
- As a user, my draft is preserved if I close the composer accidentally.

**Acceptance Criteria**:
- [ ] New `TaskComposerView` with: Title, Description, Chips row (Labels, Priority, Date, Reminders, Repeat), Bucket picker, Cancel/Add CTA.
- [ ] Chips use presets-first popovers; advanced options inline (calendar/time, recurrence picker, reminder time).
- [ ] Keyboard shortcuts: Return submit; Cmd+Return submit; Esc cancel; 1–4 priority; arrows navigate menus.
- [ ] Draft autosave and restore; cleared on successful submit.
- [ ] Theme parity (light/dark); accessible labels and focus order.
- [ ] Telemetry: open→submit time, cancel rate, chip usage.

**Implementation Plan**
- View: Create `TaskComposerView` and base chip components (reusing existing pickers where possible).
- Data: Extend `TaskDraft` with `priority` (enum) and `reminders: [Date]` (deferred if out of scope for MVP).
- Wiring: Submit through `TaskListViewModel.save(draft:)`; post recurrence and label selections via existing NotificationCenter hooks.
- macOS: Add robust keyboard navigation and shortcuts.
- Telemetry: Instrument timings and chip selections.

**Milestones (est. 2 weeks)**
- Days 1–2: UX spec/prototype; base `TaskComposerView` with Title/Description and Date chip.
- Days 3–4: Repeat chip wired to `RecurrencePicker`; Bucket picker & CTAs; basic submit.
- Days 5–7: Labels selector integration; Priority; Reminders (basic presets).
- Days 8–9: Keyboard polish (macOS), draft autosave, telemetry, a11y pass.
- Day 10: Tests (UI + unit), docs, and rollout.

**Definition of Done**
- Composer replaces old add-task sheet; editing continues to use existing form for now.
- Submit path reliable; drafts persist; keyboard flow strong on macOS.
- Tests green; no regressions; telemetry dashboards show usage.

### Epic 2.6: Working Log (Right Panel)
**Priority**: Medium-High
**Estimated Effort**: 2 weeks
**Goal**: Provide a right-side Working Log panel that automatically groups completed tasks by day and supports lightweight “Working Log Items” (notes), with filtering and Markdown export.

**User Stories**:
- As a user, I can open a right-side Working Log panel to review my day.
- As a user, when I mark a task complete, it moves to the Working Log after a 5s Undo window.
- As a user, I can add/edit/delete non-task Working Log Items (title, description, date required).
- As a user, I can search titles/descriptions and filter by date range (default last 30 days).
- As a user, I can edit a completed task’s completion date inside the Working Log.
- As a user, I can collapse older days and persist collapse per device.
- As a user, I can export a date range of my Working Log to Markdown.

**Acceptance Criteria**:
- Right-side panel toggles from the board header; open/closed state persists per device.
- Completed tasks appear grouped by local day using `completedAt`; items newest-first.
- 5s Undo toast on completion; no Undo → task appears; Undo → task reverts and does not appear.
- Working Log Items require title, description, date; appear only in Working Log with distinct styling.
- Search matches case/diacritic-insensitive across titles/descriptions for tasks and log items.
- Default view shows last 30 days; user can load older or set custom range.
- Editing `completedAt` allowed only for completed tasks and only inside the Working Log; future dates disallowed.
- Deleting a Working Log Item performs soft delete; Settings offers a user-triggered hard delete for soft-deleted items.
- Export produces Markdown grouped by day with separate Task and Log Item sections and timestamps.

**Implementation Plan**
- Database & RLS
  - Add `working_log_items` table: `id uuid pk`, `user_id uuid`, `title text`, `description text`, `occurred_at timestamptz`, `created_at timestamptz default now()`, `updated_at timestamptz default now()`, `deleted_at timestamptz null`.
  - RLS: enable; policy `user_id = auth.uid()` for select/insert/update/delete; soft delete sets `deleted_at`.
  - Indexes: `(user_id, occurred_at desc)`, `(user_id, deleted_at)`; updated_at trigger; Realtime publication enabled.
- Local Storage (SwiftData)
  - Create `WorkingLogItemEntity` mirroring remote fields including `deletedAt` tombstone.
  - Migration to add entity; helpers for grouping by local day.
- Repositories & Sync
  - Local: `SwiftDataWorkingLogRepository` with CRUD, soft delete, hard delete.
  - Remote: `SupabaseWorkingLogRepository` with DTOs and delta upsert; exclude `deleted_at` by default.
  - Sync: extend `SyncService` to push/pull `working_log_items`; include tasks’ `completedAt` in grouping; last-write-wins.
- UI
  - Panel: `WorkingLogPanelView` docked right of board; header toggle in board header; per-device open state.
  - Sections: day headers (Today/Yesterday/Weekday, Mon DD), collapsible with persisted state.
  - Items: reuse `TaskCard` for tasks; `WorkingLogItemCard` for notes with distinct surface color and note icon.
  - Controls: Add Log Item, search (title+description), date range (Today/7/30/Custom), Export Markdown.
  - Edit `completedAt` for completed tasks via context menu/detail within panel; validate non-future.
- Behavior
  - Completion: 5s Undo toast; on timeout, move task to Working Log; cancel if toggled back before timeout.
  - Deletion: soft delete by default; Settings provides user-controlled hard delete action.
- Settings
  - Add “Hard delete Working Log items” action with confirmation; no auto-retention.
- Telemetry
  - Events: `working_log_opened`, `working_log_day_toggled`, `working_log_item_created/edited/deleted`, `task_completed_moved_to_working_log`, `task_completed_undo`, `working_log_export_markdown`.
- Testing & Perf
  - Unit: repos CRUD, grouping, search normalization, undo behavior, date edit validation.
  - Integration: RLS policies, delta sync, Realtime hints; pagination for >30 days.
  - UI: panel interactions, collapse persistence, export.

**Milestones (est. 2 weeks)**
- Days 1–2: DB schema/RLS/index/realtime plan; SwiftData entity/migration; DTOs.
- Days 3–4: Repositories (local/remote); SyncService delta; tests.
- Days 5–7: Panel UI, day sections, search/date filters, item cards.
- Days 8–9: Completion Undo flow; edit `completedAt` UI; Settings hard delete.
- Day 10: Export Markdown; telemetry; perf/accessibility pass; docs & feature flag.

**Definition of Done**
- Panel shipped with 30-day default view, collapse per device, search/date filters.
- Tasks auto-move with 5s undo; `completedAt` editable only in panel; validation enforced.
- Working Log Items CRUD with soft delete; optional hard delete from Settings.
- Sync, RLS, and Realtime verified; export to Markdown works; tests green; docs published.

---

## Phase 3: Advanced Features & Polish (Weeks 15-20)

### Epic 3.1: Routines & Recurrence | COMPLETED
**Priority**: Medium
**Estimated Effort**: 2 weeks
**Goal**: Implement sophisticated recurring task management

**User Stories**:
- As a user, I can create recurring tasks with various patterns
- As a user, completing a recurring task generates the next instance
- As a user, I can manage my routine tasks effectively

**Acceptance Criteria**:
- [x] Implement recurrence rule parsing and storage (Swift + Supabase JSON rules)
- [x] Create next-instance generation logic (complete-to-generate-next + catch-up)
- [x] Build recurring task UI with pattern selection (Daily, Weekdays, Weekly, Monthly-day)
- [x] Add routine-specific actions (Pause/Resume, Skip next, Generate now)
- [x] Implement recurrence sync and idempotency (pull + catch-up; local-first create/update)

### Epic 3.2: Widgets & App Intents
**Priority**: Medium
**Estimated Effort**: 1.5 weeks
**Goal**: Extend app presence beyond main interface

**User Stories**:
- As a user, I can see my tasks in widgets on home screen/desktop
- As a user, I can add tasks via Siri or Shortcuts
- As a user, I can quickly check my progress without opening the app

**Acceptance Criteria**:
- [ ] Create small/medium/large widget variants
- [ ] Implement App Intents for Siri integration
- [ ] Add Shortcuts support for task creation
- [ ] Create interactive widget actions (mark complete)
- [ ] Optimize widget performance and updates

### Epic 3.3: Search & Command Palette
**Priority**: Medium
**Estimated Effort**: 1 week
**Goal**: Enable quick task discovery and actions

**User Stories**:
- As a user, I can search across all my tasks quickly
- As a user, I can use a command palette for quick actions
- As a user, I can find tasks by content, labels, or bucket

**Acceptance Criteria**:
- [ ] Implement full-text search across tasks
- [ ] Create command palette UI (⌘K on macOS)
- [ ] Add search filters and suggestions
- [ ] Integrate with Spotlight on macOS
- [ ] Add recent items and smart suggestions

### Epic 3.4: Performance & Polish
**Priority**: Medium
**Estimated Effort**: 1.5 weeks
**Goal**: Optimize performance and add final polish

**User Stories**:
- As a user with many tasks, the app remains responsive
- As a user, interactions feel smooth and delightful
- As a user, error states are handled gracefully

**Acceptance Criteria**:
- [ ] Optimize list performance for large datasets
- [ ] Add smooth animations and micro-interactions
- [ ] Implement proper error handling and retry logic
- [ ] Add empty states and loading skeletons
- [ ] Performance testing and optimization
- [ ] Final accessibility audit and improvements

---

## Future Considerations (Post-MVP)

### Phase 4: Advanced Features
- **Epic 4.1**: Natural Language Processing for task input
- **Epic 4.2**: Collaboration features (shared buckets/tasks)
- **Epic 4.3**: Analytics and insights
- **Epic 4.4**: Liquid Glass backend migration preparation

### Phase 5: Platform Expansion
- **Epic 5.1**: Apple Watch companion app
- **Epic 5.2**: iPad-specific optimizations
- **Epic 5.3**: Apple Vision Pro exploration

---

## Success Metrics

### Phase 0-1 Success Criteria:
- [ ] User can create, complete, and sync tasks across devices
- [ ] Authentication works reliably
- [ ] App works offline with proper sync
- [ ] Basic time bucket organization is intuitive

### Phase 2-3 Success Criteria:
- [ ] Users actively use labels for organization
- [ ] Subtasks improve task completion rates
- [ ] macOS users adopt keyboard shortcuts
- [ ] App feels polished and production-ready

## Risk Mitigation

1. **Sync Complexity**: Start with simple last-write-wins, iterate to handle edge cases
2. **Performance**: Implement pagination and lazy loading early
3. **User Adoption**: Focus on core value proposition (time buckets) before adding complexity
4. **Platform Differences**: Design mobile-first, enhance for desktop

## Dependencies & Assumptions

- Supabase service availability and performance
- Apple's SwiftData stability and feature set
- Access to beta testing users for feedback
- Design system tokens finalized before UI implementation

---

*This roadmap is living document and should be updated based on user feedback, technical discoveries, and changing priorities.*


