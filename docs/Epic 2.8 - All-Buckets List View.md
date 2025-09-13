## Epic 2.8 — All-Buckets List View (Vertical Sections)

### Goal
Replace the single-bucket list and bucket picker with one vertically scrolling list that shows all buckets as sections. Each section has a header with a count and an add action. Filters apply across all sections. Drag-and-drop supports reordering within a bucket and moving tasks across buckets.

### Problem / Opportunity
The current list mode requires switching buckets via a picker, hiding context and increasing navigation friction. A consolidated, multi-bucket list reduces mode switching, makes cross-bucket triage faster, and aligns list and board mental models.

### Objectives
- Provide a single-page view that includes all buckets, top-to-bottom.
- Remove the bucket picker/menu in list mode (board toggle remains).
- Keep per-bucket add actions and counts visible in context.
- Support cross-bucket and in-bucket reordering with smooth drag-and-drop.
- Apply filters globally across all sections.
- Preserve the “This Week” weekday subsections behavior inside that section only (when feature flag on).

### Scope
- iOS and macOS list modes.
- Board mode unchanged; still accessible via toolbar toggle.
- Deep-link “open task” and “task created” scroll-to in the unified list.
- Pinned (sticky) bucket headers while scrolling.
- Bucket sections are collapsible; empty buckets are visible (collapsible) to allow drop targets.

### Out of Scope (v1)
- Custom bucket ordering UI; order must match the board view’s bucket order.

### User Stories & Acceptance Criteria
1) As a user, I can see all buckets in one scrolling list
- All buckets render in the same order as the board view.
- Each section shows a pinned header with name and count, plus a “+” to add into that bucket.
- Empty buckets still show their header; sections are collapsible; provide a subtle empty hint.

2) As a user, filters apply across the whole list
- Applying or clearing filters refreshes all sections (no bucket switching).

3) As a user, I can drag tasks within and across buckets
- Reordering within a bucket updates the position.
- Dropping into another bucket (including empty sections) moves the task and places it at the computed target index.
- Visual indicators appear at the target index. Optimistic UI updates.

4) As a user, I can deep-link to a task and the list scrolls to it
- Opening a task from notification/deeplink scrolls the unified list to the item and opens the editor.

5) As a user, I still see “This Week” organized by weekdays when enabled
- Only inside the `.thisWeek` section, weekday subsections render as today + remaining weekdays.

### UX Specs
- One `ScrollView` + `LazyVStack` for the entire page; no nested scrolls inside sections.
- Pinned headers: bucket headers remain visible at the top while their section is in view.
- Section header component: reuse `BucketHeader(bucket:count:onAdd:)` with collapse toggle.
- Rows: reuse existing task cards and interactions.
- Drag-and-drop affordances and insertion indicators match existing list behavior.
- Empty placeholder per section; section is a drop target even when empty/collapsed.

### Technical Plan
- Rendering
  - Create `AllBucketsListView` (one `ScrollViewReader` + `ScrollView` + `LazyVStack`).
  - For each `TimeBucket`, render `BucketHeader` (with collapse toggle, pinned) and the bucket’s tasks. Avoid nested `ScrollView`s.
  - For `.thisWeek` with the feature flag enabled, render `ThisWeekSectionsListView` within that section; other buckets use flat rows.

- Refactor list content
  - Extract non-scrolling row stack + drag/drop logic from `TasksListView` into `TasksListContent` so it can be embedded per section without nested scrolling.
  - Keep `TasksListView` as a thin single-bucket wrapper to preserve existing usage elsewhere.

- Data fetching
  - In list mode, fetch with `bucket=nil` to retrieve all buckets (`TaskListViewModel.fetchTasks(in: nil)` already supported for board mode).
  - Replace list-mode call sites that use `selectedBucket` with `nil`.

- Remove bucket picker/menu in list mode
  - Set `showBucketMenu: false` in `TaskListHeader` for list mode on iOS and macOS.
  - Remove any segmented picker remnants.

- Drag-and-drop across sections
  - Each `TasksListContent` section has a drop target (works when empty/collapsed); compute target index relative to the destination bucket’s incomplete tasks.
  - Call `viewModel.reorder(taskId:to:targetIndex:)` to persist position and bucket.

- Filters & deep links
  - Update filter handlers to refetch with `nil`.
  - Move scroll-to handling for `dm.task.created` and `dm.open.task` into `AllBucketsListView`’s `ScrollViewReader`.

- Telemetry
  - Add event: `multi_bucket_list_shown` and per-bucket add taps; retain existing reorder/move telemetry if present.
  - Add event: `bucket_section_toggle` (bucket, collapsed: Bool).

### Files & Changes
- `Features/Views/TaskList/AllBucketsListView.swift` (new)
- `Features/Views/TaskList/TasksListView.swift` → extract `TasksListContent` (non-scrolling)
- `Features/Views/TaskListView.swift` (macOS/shared) → render `AllBucketsListView` in list mode; hide bucket menu
- `Features/Views/TaskList/TaskListScreenIOS.swift` (iOS) → same as above
- `DesignSystem/Components/BucketHeader.swift` (reuse)
- `Features/ViewModels/TaskListViewModel.swift` → adjust fetch/refetch call sites for `nil` in list mode; no schema changes

### Data & Backend Impact
- No database schema changes. Existing move and reorder APIs already support cross-bucket changes.

### Risks & Mitigations
- Nested scroll performance → Remove inner scroll; use `LazyVStack` only at the page level.
- Cross-bucket reorder correctness → Reuse existing `reorder(taskId:to:targetIndex:)` logic; compute per-bucket indices.
- Deep-link scroll accuracy → Use a single `ScrollViewReader` and stable `.id(task.id)` on rows.

### Milestones (est. 1–1.5 weeks)
- Days 1–2: Create `AllBucketsListView`, extract `TasksListContent`, render sections.
- Days 3–4: Wire `nil` fetching in list mode; remove picker/menu; filters across sections.
- Days 5–6: Cross-bucket drag-drop; deep-link/created-task scroll; telemetry.
- Day 7: Tests (unit/integration/UI), polish, accessibility, docs.

### Definition of Done
- All buckets visible in one scrolling list; no picker/menu in list mode.
- Add per bucket opens prefilled composer; counts correct.
- Drag-and-drop reorders within and across buckets with optimistic UI and persistence.
- Filters apply across the entire list; This Week subsections appear only within that section.
- Deep-link/created-task scroll works reliably.
- Tests green; no regressions; docs updated.

### References
- `Features/Views/TaskListView.swift`
- `Features/Views/TaskList/TaskListScreenIOS.swift`
- `Features/Views/TaskList/TasksListView.swift`
- `Features/ViewModels/TaskListViewModel.swift`
- `DesignSystem/Components/BucketHeader.swift`


