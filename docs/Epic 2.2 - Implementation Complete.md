### Epic 2.2 — Subtasks & Rich Descriptions

- Hierarchical subtasks (parent/child) with create, inline edit, complete, delete
- Drag-and-drop reordering with position normalization
- Subtask progress shown on task cards (completed/total)
- Markdown description editor with preview and toolbar (bold, italic, link, list, code)
- Completion logic: parent cascade, auto-complete when all children complete
- Supabase: composite indexes for (user_id,parent_task_id,deleted_at) and (user_id,parent_task_id,position)
- Realtime: table change hinting triggers debounced syncs
- Tests updated for cascade and progress
- Feature flag toggle in Settings

Definition of Done items met.
