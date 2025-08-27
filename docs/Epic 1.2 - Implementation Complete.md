## Epic 1.2 — Task CRUD, Editing, Delete, and Board View (Implementation Complete)

### Executive summary
Epic 1.2 adds full task CRUD UX on top of the MVP foundation delivered in Epic 1.1. Users can create and edit tasks (title, description, due date, bucket), delete tasks with confirmation, move tasks across buckets either from the list or an optional board view, and the UI maintains bucket‑scoped filtering at all times. macOS and iOS both compile and run with fast SwiftUI previews.

### Scope delivered
- Create/Edit via `TaskFormView` with `TaskDraft` (title, description, optional due date, bucket)
- Quick Add in list view to create in current bucket
- Delete with confirmation (list and board)
- Move between buckets (context menu in list, drag‑and‑drop in board)
- Board view: columns per bucket, drag and drop, edit/delete, back navigation
- Strict bucket filtering preserved after all actions and when returning from board

### Key code changes
- UI
  - `TaskListView`: segmented bucket picker; Quick Add; context menu for edit/move/delete; sheet for form; alert for delete; ensured filtered fetch on appear and after actions; added `NavigationStack`.
  - `BucketBoardView`: columns with `BucketHeader`; drag/drop; context menu and double‑click for edit; Back toolbar; own sheet/alert; data refresh after drops/toggles.
  - DS: `Buttons.swift` (Primary/Secondary/Destructive).
- ViewModel
  - `TaskListViewModel`: form state (`isPresentingTaskForm`, `editingTask`, `pendingDelete`); `save(draft:)`, `presentCreateForm`, `presentEditForm`, `confirmDelete`, `performDelete`, `move(taskId:to:)`; all actions refresh counts and re‑fetch with `selectedBucket`.
- Domain/Data
  - Reused repository/use case APIs from 1.1; no schema changes required.

### Tests (automated)
- Unit tests run green (see Test log) and cover:
  - `TaskTests.testMoveTaskBetweenBuckets()` — moving tasks adjusts bucket membership
  - `TaskTests.testCountsExcludeCompletedByDefault()` — counts logic
  - Repository tests for sort/filter and SwiftData CRUD
  - Sync tests (unchanged) still pass

Recommended follow‑ups (optional):
- Add unit tests for `TaskListViewModel` to assert filtered re‑fetch after create/delete/move when `selectedBucket` is set (non‑UI logic).

### Manual QA checklist
- Switch buckets; create via Quick Add; list stays filtered; counts update
- Edit a task and change bucket; list reflects move; counts update
- Delete a task; confirmation appears; list remains filtered
- Open Board; drag a card to a different bucket; card reappears in target column; Back returns to filtered list
- macOS and iOS builds succeed; Sign in/out works

### Known limitations
- Board view uses a simple layout without virtualization; adequate for MVP volumes
- Form does not yet include recurrence or label assignment (future epics)

### Outcome
Epic 1.2 is functionally complete and integrated with the design system. Users have a coherent CRUD experience across list and board, with reliable bucket scoping and live counts.


