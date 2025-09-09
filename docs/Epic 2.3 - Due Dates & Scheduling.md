### Epic 2.3 — Due Dates & Scheduling

- SwiftUI DatePicker in `TaskFormView` (date & time) with clear support
- Due chip on `TaskCard` with overdue styling (red) and accessibility labels
- Optional sorting by due date (incomplete first, earliest due first, nils last), persisted via `AppStorage("sortByDueDate")`
- Lightweight overdue computation and minute-based updates handled by the view model
- Local notifications for due reminders with user toggle in Settings
- Supabase schema already supports `due_at` (indexed in `idx_tasks_user_bucket`)

Usage
- Enable "Sort by Due Date" in the list header to order tasks by due time
- Toggle "Due date notifications" in Settings to receive alerts at the due time

Notes
- Notifications schedule on create/update and cancel on completion/delete/clear due date
- No schema changes required; delta sync continues to track `due_at`

### Date-only due dates
- New field `due_has_time` (client: `dueHasTime`) indicates whether a time was set.
- When `dueHasTime == false`:
  - Overdue starts at the beginning of the next day (effective deadline is end-of-day of the selected date).
  - Sorting and “Available only” filtering use the effective deadline (end-of-day) for comparisons.
  - UI hides the time portion in chips and labels.
  - Notifications are scheduled for 12:00 PM local time on the selected date.
- Default behavior when picking a due date is date-only (no time). Enabling “Include time” shows time controls and stores the explicit time; chips display time accordingly.
