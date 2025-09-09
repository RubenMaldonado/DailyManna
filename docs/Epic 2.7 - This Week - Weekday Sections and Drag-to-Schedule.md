### Epic 2.7 — “This Week” bucket: Weekday sections and drag-to-schedule

#### Goal
Make the “This Week” bucket actionable by structuring tasks into weekday sections and enabling drag-and-drop to schedule tasks to specific days. Works in List and Board views. No per-weekday counts. Sections are collapsible. Single-task drag at a time.

#### Alignment with current codebase
- Buckets are first-class (`TimeBucket`) and “This Week” is already the default filter.
```12:27:DailyManna/Domain/Models/TimeBucket.swift
public enum TimeBucket: String, CaseIterable, Identifiable, Codable {
    case thisWeek = "THIS_WEEK"
    case weekend = "WEEKEND"
    case nextWeek = "NEXT_WEEK"
    case nextMonth = "NEXT_MONTH"
    case routines = "ROUTINES"
}
```
- Tasks already support `dueAt` and `dueHasTime`, which we will use to group and reschedule by weekday.
```18:26:DailyManna/Domain/Models/Task.swift
public var dueAt: Date?
public var dueHasTime: Bool = true
```
- List and Board support drag-and-drop today for reordering and bucket moves; we’ll extend to intra-bucket weekday rescheduling.
```153:201:DailyManna/Features/Views/BucketBoardView.swift
.draggable(DraggableTaskID(id: pair.0.id))
.dropDestination(for: DraggableTaskID.self) { items, location in
    // compute target index ...
}
```
```104:116:DailyManna/Features/Views/Board/InlineBoardViews.swift
.onDrop(of: [UTType.plainText], delegate: InlineColumnDropDelegate(...))
```
- Current list rendering is flat per bucket and uses existing drop logic; we’ll add weekday sections only when bucket == .thisWeek.
```333:342:DailyManna/Features/Views/TaskListView.swift
TasksListView(
    bucket: viewModel.selectedBucket,
    tasksWithLabels: viewModel.tasksWithLabels,
    ...
)
```

No backend schema changes are required. Due date updates are already part of `TaskDTO` and local `TaskEntity`.
```36:44:DailyManna/Data/Remote/DTOs/TaskDTO.swift
due_at: task.dueAt,
due_has_time: task.dueHasTime,
```

---

### Problem / Opportunity
The current “This Week” bucket aggregates tasks without daily structure. Users need a fast way to plan the week and reschedule slipping items without opening the task detail sheet.

### Objectives
- Clarity: Group tasks by weekday to create a plan-at-a-glance view.
- Speed: Drag-and-drop between weekday sections to reschedule due dates instantly.
- Focus: Only show remaining weekdays (Mon–Fri) relative to today, plus Today.
- Consistency: Identical logic for List and Board views.
- Safety: Optimistic updates with reliable sync and conflict handling.

### Out of scope (for v1)
- Per-weekday task counts (not needed).
- Multi-select drag/move (single-task only).
- Configurable workweek or weekend inclusion (weekend has its own bucket).
- Changing recurrence rules (only due dates change).

### User Stories & Acceptance Criteria

1) As a user, I see “This Week” split into actionable weekday sections
- “Today” section is always shown.
- Future sections: only remaining weekdays of the current week after today. Example: on Wednesday show “Thursday”, “Friday”.
- Weekends are excluded.
- Section headers show day name and date, e.g., “Thursday • Sep 12”.
- Completed tasks are not shown.
- Sections are collapsible via a chevron toggle; collapsed state persists per day for the current week.

2) As a user, I see overdue items in Today to triage quickly
- Today includes:
  - Tasks due today (not completed).
  - Overdue tasks with due dates before today (not completed).
- Overdue tasks display existing overdue styling.

3) As a user, I drag a task between sections to reschedule its due date
- Dragging into a weekday section sets `dueAt` to that day (local timezone), preserving time-of-day if `dueHasTime` is true; otherwise set to start-of-day.
- Dragging into “Today” sets `dueAt` to today (overdue badge clears).
- Reordering within a section does not change `dueAt`.
- Drag-and-drop supported in List and Board views for .thisWeek bucket.
- Optimistic UI: task moves immediately; due date change persists via sync, with failure rollback and error banner.
- Only a single task is moved per interaction.

4) As a user, I only see the days that matter now
- Monday: show Today (Mon) + Tue–Fri sections.
- Wednesday: show Today (Wed) + Thu–Fri sections.
- Friday: show Today only.
- On Saturday/Sunday, the “This Week” bucket shows no weekday sections (empty state) until Monday.

5) Predictable time behavior
- All calculations use device local timezone.
- Rollover at local midnight re-evaluates sections and membership.
- Due times, if present, are preserved; otherwise set to start-of-day.

### UX Specs

- List View
  - Order: Today, then remaining weekdays chronologically.
  - Each section has a sticky header with day name and date, and a chevron to collapse/expand.
  - Collapsed state: hide tasks; header remains visible.
  - Empty section state: show subtle “No tasks scheduled” placeholder; still collapsible.
  - Drag affordance on each task; clear drop-highlight on headers/sections.

- Board View
  - The “This Week” column contains stacked subsections: Today, Thu, Fri, each collapsible.
  - Drag-and-drop between subsections updates `dueAt` as above.
  - Column header remains “This Week”. No per-day counts.

- Interaction
  - Context menu on a task includes quick actions: “Schedule Today”, “Schedule Thursday”, “Schedule Friday”.
  - Keyboard (macOS/iPadOS):
    - Cmd+→ moves task to next weekday section (if any).
    - Cmd+← moves to previous weekday section (from Today: no-op).
  - Accessibility:
    - VoiceOver actions rotor: “Move to Thursday/Friday”.
    - Drop targets labeled “Schedule for Thursday”.
    - High-contrast drop target highlighting.

### Business Rules
- Scope of “This Week”
  - Includes tasks where `bucketKey == .thisWeek`.
  - Today additionally includes overdue items (`dueAt < startOfToday`) that are not completed.
- Unscheduled tasks (`dueAt == nil`) are not shown under “This Week”.
- Completed tasks are not shown.
- Recurring tasks: moving a task only updates the current instance `dueAt`; recurrence rules remain unchanged.
- Conflict resolution: if a task changes remotely during a drag, apply server merge (last-write-wins already in SyncService) and re-group locally.

### Edge Cases
- Friday shows only Today.
- Week crossing: Overdue from prior weeks appears in Today.
- Timezone changes during use: on entering foreground or timezone change notification, recompute sections and regroup.
- DST/year-end handled by `Calendar` APIs.

### Data & Technical Plan

1) Grouping utilities
- Add `WeekdaySection` model with fields: `id`, `date`, `title`, `isToday`, `isCollapsed`.
- Add `WeekPlanner` utility to compute:
  - `startOfToday`, `remainingWeekdays(Mon–Fri)` relative to today.
  - Mapping of tasks into sections: Today = due today + overdue; Others = due exactly that day.

2) ViewModel additions (`TaskListViewModel`)
- Derived state for `weekdaySections: [WeekdaySection]` when `selectedBucket == .thisWeek`.
- Map `tasksWithLabels` into `[WeekdaySection: [(Task,[Label])]]`.
- New intents:
  - `schedule(taskId: UUID, to date: Date)` → updates `dueAt` (preserve time if `dueHasTime`), optimistic update, persist via `TaskUseCases.updateTask`.
  - `moveToNextWeekday(taskId:)` and `moveToPreviousWeekday(taskId:)` for keyboard.
- Persist collapsed state per day/week in `@AppStorage` keyed by `yyyy-ww-day`.

3) List View
- Introduce `ThisWeekSectionsListView` rendered only when `selectedBucket == .thisWeek`.
- Renders sections with sticky headers, chevrons, and `dropDestination` on section containers.
- Drop handler calls `schedule(taskId:to:)` with section date.
- Reorder within section uses existing row-frame logic but does not change due date.

4) Board View
- Update `InlineBucketColumn` when `bucket == .thisWeek` to render subsections (Today + remaining weekdays) within the column.
- Add drop targets per subsection; call `schedule(taskId:to:)` accordingly.
- Preserve existing reordering logic within a subsection (no due date change).

5) Telemetry
- Events:
  - `this_week_view_shown` (view: list|board)
  - `task_rescheduled_drag` (from_day, to_day)
  - `task_rescheduled_quick_action` (to_day)
  - `this_week_section_toggle` (day, collapsed: Bool)

6) Sync & Error handling
- Optimistic moves update local list immediately.
- On failure from `updateTask`, revert local change and show error banner.

7) Feature flag
- Gate the new layout behind a local flag `@AppStorage("feature.thisWeekSections")` default on for internal/beta; easy rollback.

### QA Scenarios
- Rendering
  - Mon–Fri: correct sections per day; Friday shows only Today; weekends show empty.
  - Headers sticky; chevron toggles collapse; state persists.
- Task inclusion
  - Today = due today + overdue (incomplete). Others = due exactly that day.
- Drag-and-drop
  - Move Today → Thu updates `dueAt` to Thu; persists across refresh/relaunch.
  - Move overdue → Fri clears overdue.
  - Reorder within same section doesn’t change `dueAt`.
  - Failure path reverts and shows error.
- Time behavior
  - Midnight rollover and timezone change regroup correctly.
- Accessibility
  - VoiceOver actions present; drop targets labeled; keyboard shortcuts work on macOS/iPad.

### Release & Rollout
- Phase 1 (flagged internal): List + Board subsections; DnD rescheduling; basic telemetry.
- Phase 2 (beta/TestFlight): Accessibility polish; keyboard support; error/empty states; performance profiling.
- Phase 3 (public): Enable by default; monitor metrics; consider setting to hide prior-week overdue if noisy.

### Engineering Tasks (high-level)
- Utilities: Week planner and grouping.
- ViewModel: derived sections, schedule intent, collapse persistence.
- List: new sectioned view with DnD.
- Board: subsections in `InlineBucketColumn` for `.thisWeek`.
- Telemetry: new events in `Telemetry`.
- Feature flag wiring.
- Tests: unit tests for grouping, schedule intent, and UI smoke tests.


