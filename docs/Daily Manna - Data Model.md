# **Daily Manna Data Model (with Time Buckets)**

**Overview:** The initial “Data Model with Time Buckets” has been refined to align with the architecture review and product design. Key changes include using universally unique IDs for better sync, adding timestamp metadata for multi-device synchronization, and ensuring support for fixed time buckets, sub-tasks, labels, recurrence, and due dates. The schema below presents each table with changes **italicized** and rationales for each improvement.

## **Users**

* **`id` – UUID (PK)** – Unique user identifier (changed from INT to UUID to match Supabase Auth’s user IDs and allow cross-device uniqueness). In a Supabase implementation, this would correspond to the authenticated user’s ID.

* `email` – TEXT – User’s email address (unique).

* `full_name` – TEXT – User’s full name.

* `created_at` – TIMESTAMPTZ – Timestamp of account creation (defaults to current time).

* **`updated_at` – TIMESTAMPTZ** – Timestamp of last profile update (added for completeness if profile info can change).

* *Removed `password_hash`:* Authentication is handled by external providers (Sign in with Apple/Google via Supabase Auth) and not stored in the app schema.
* Trigger: `handle_new_user()` inserts a row into `public.users` when a new `auth.users` row is created (idempotent; `ON CONFLICT DO NOTHING`).

**Rationale:** Using a UUID for `id` enables consistency with Supabase’s user IDs and avoids relying on auto-increment IDs. This is important for syncing across devices – clients can generate their own user (and other entity) IDs without collisions. The password hash is dropped because authentication is external; we only keep minimal profile info (email, name) in this table.

## **TimeBuckets**

* **`key` – TEXT (PK)** – Identifier for the time bucket (e.g. `"THIS_WEEK"`, `"WEEKEND"`, etc.). Serves as a stable, predefined key for bucket category.

* `name` – TEXT – Human-friendly name (e.g. "This Week", "Weekend").

*(This table is pre-populated with **five fixed buckets**: “THIS\_WEEK”, “WEEKEND”, “NEXT\_WEEK”, “NEXT\_MONTH”, “ROUTINES”. All tasks must belong to one of these buckets, reflecting the app’s opinionated time-horizon structure.)*

**Rationale:** The `TimeBuckets` entity ensures tasks are organized into one of the five fixed time horizons. Using a textual `key` as the primary key provides a stable identifier for each bucket across all environments (no auto-increment IDs that might differ). We enforce the allowed values either by seeding this table or via a CHECK constraint on `bucket_key` in the `Tasks` table. This guarantees the schema supports the *“THIS WEEK”, “WEEKEND”, “NEXT WEEK”, “NEXT MONTH”, “ROUTINES”* structure central to Daily Manna’s design.

## **Tasks**

* **`id` – UUID (PK)** – Unique task identifier (changed from INT to UUID for global uniqueness and client-side generation). This enables offline task creation with no ID collisions and supports idempotent upsert during sync.

* `user_id` – UUID (FK → Users.id) – Owner of the task. (Type changed from INT to UUID to align with the Users table/Supabase Auth ID. Used in row-level security policies to isolate user data.)

* **`bucket_key` – TEXT** (FK → TimeBuckets.key) – Time bucket category to which this task belongs. (Replaces the numeric `bucket_id` with a stable text key. Ensures the task is in one of the five fixed buckets; e.g. a task can be in “THIS\_WEEK” or “ROUTINES”. A CHECK constraint enforces valid values if not using an explicit foreign key.)

* `parent_task_id` – UUID, nullable (FK → Tasks.id) – Reference to a parent task for sub-tasks. (`parent_task_id` remains for hierarchical tasks; now using UUID type. Allows tasks to have optional sub-tasks. If set, this task is a sub-task of another task.)

* `title` – TEXT – Short title or name of the task. (Type changed from VARCHAR to TEXT for flexibility in length.)

* `description` – TEXT – Detailed description with rich text (supports markdown formatting for **bold** or URLs).

* **`due_at` – TIMESTAMPTZ, nullable** – Specific due date and time for the task (renamed from `due_date` and stored with timezone precision. This allows tasks to have exact deadlines or reminder times in addition to their general bucket placement).

* `recurrence_rule` – TEXT, nullable – Recurrence pattern or rule for repeating tasks (e.g. `"every Friday"`). Used primarily for tasks in the \#ROUTINES bucket to generate the next occurrence when one is completed. (Stored as free-form text or a standardized rule; allows natural-language input parsing in the future.)

* `is_completed` – BOOLEAN (default FALSE) – Completion status of the task.

* `completed_at` – TIMESTAMPTZ, nullable – Timestamp when the task was marked completed. (Populated when `is_completed` flips true, to track *when* it was done.)

* `created_at` – TIMESTAMPTZ (default NOW()) – Timestamp when the task was created.

* **`updated_at` – TIMESTAMPTZ** (auto-updated) – Timestamp of the last modification to this task. (Added to support sync; this is automatically updated on every insert/update via `touch_updated_at()` trigger. Used by the sync engine to fetch changed tasks since the last sync.)

* **`deleted_at` – TIMESTAMPTZ, nullable** – Timestamp of logical deletion. (Added as a *tombstone* marker for deletions. Instead of hard-deleting tasks, setting this field indicates the task was deleted, which allows other devices to sync the deletion and hide or purge the task. A non-NULL `deleted_at` means the task is considered deleted and can be filtered out in queries.)

**Rationale:** These changes ensure the **Tasks** table fully supports Daily Manna’s functionality and the robust sync requirements:

* *Time Buckets:* Every task must belong to one fixed bucket. Using `bucket_key` directly in Tasks (with allowed values enforced) guarantees this relationship. This aligns with the design where tasks are always in “THIS WEEK”, “NEXT WEEK”, etc., and not in arbitrary user-created projects.

* *Sub-Tasks:* The `parent_task_id` FK allows nesting tasks (one level deep) so that larger tasks can be broken down into smaller steps. This recursion via self-reference keeps the schema normalized (no separate sub-task table needed) while fulfilling the feature of sub-tasks in the product. We ensure that if a parent task is deleted, its sub-tasks are also removed or marked deleted to avoid orphaned subtasks (implemented via **ON DELETE CASCADE** or a deletion trigger).

* *Due Dates & Times:* The move from a date-only field to `due_at` (timestamp with time zone) addresses the requirement that a task in a bucket like \#THIS WEEK can still have a specific due date **and time** for scheduling or reminders. This provides timestamp granularity as needed by the design.

* *Recurrence:* Storing a `recurrence_rule` as text meets the need for dynamic recurring tasks in the \#ROUTINES bucket. Instead of listing all future occurrences, we keep a rule (e.g. "every Monday") and generate the next task occurrence when the current one is completed. The schema is forward-compatible with NLP input; for example, a phrase like *"Submit report every Friday"* can be parsed by the app and saved into `title`, `due_at` (for the first occurrence), and `recurrence_rule`. No additional fields are required for NLP, since the existing fields capture the necessary structured data (the natural language is interpreted into these fields).

* *Sync Metadata:* Adding `updated_at` and `deleted_at` is critical for the offline-first, multi-device sync strategy. Every change touches `updated_at` (via a trigger) so that clients can pull incremental updates (e.g., “give me all tasks where `updated_at` \> my last sync”). The `deleted_at` field enables **logical deletes** – rather than immediately removing tasks from the database, which could lead to sync conflicts or data loss, we mark them deleted. Other devices then receive that tombstone and can hide or delete the task locally. This approach supports *deterministic conflict resolution* (Supabase/Postgres can do "last-write-wins" based on `updated_at`, and we never lose a delete operation since it’s a state in the data model rather than an absence).

* *UUID Primary Key:* Switching `task_id` to a UUID `id` ensures that tasks created on different devices won’t clash on ID. The architecture calls for client-generated IDs (UUID/ULID) for exactly this reason. It allows the app to create tasks offline and later upsert to the server without id conflicts, and it aligns with Supabase’s preference for UUID keys in distributed systems.

Additionally, an index on `parent_task_id` is recommended to quickly query sub-tasks of a given parent, and `user_id` is part of other important indexes (see **Indexes** below).

## **Labels**

* **`id` – UUID (PK)** – Unique label identifier (changed from INT to UUID for consistency and to allow client-side generation if needed, similar to tasks).

* `user_id` – UUID (FK → Users.id) – Owner of the label. Each label is owned by a user; we use UUID to match the Users table and for RLS enforcement (only the owner’s labels are visible to them).

* `name` – TEXT – Name of the label (e.g. `"@work"`, `"@personal"`). Ideally unique per user to avoid duplicates (we can enforce a **unique index on (user\_id, name)**).

* `color` – TEXT – Hex color code or identifier for the label (for UI display, e.g. "\#FF0000").

* **`created_at` – TIMESTAMPTZ** – Timestamp when the label was created.

* **`updated_at` – TIMESTAMPTZ** – Timestamp of the last update to the label (if the label’s name or color is edited). Consider a similar `touch_updated_at()` trigger.

* **`deleted_at` – TIMESTAMPTZ, nullable** – Timestamp if the label was deleted. (Like tasks, labels can be logically deleted to sync label removals. When a label is “deleted,” we mark this field and keep the row for sync purposes.)

**Rationale:** The **Labels** table allows users to tag tasks with categories that cut across the fixed buckets. Changes here mirror the patterns in Tasks:

* Using a UUID `id` for the primary key aligns with the rest of the schema and supports offline label creation. For example, a user can create a new label on one device and another on a second device; using UUIDs avoids primary key collisions when syncing.

* We include `user_id` to scope labels to their owner and to enforce row-level security (each user manages their own set of labels). In combination with a unique constraint on name, this ensures one user cannot accidentally duplicate label names, while different users can have labels with the same name (since their `user_id` differs).

* Timestamp fields (`created_at`, `updated_at`, `deleted_at`) are added for similar reasons as with tasks: to support sync and potential conflict resolution. For instance, if a label’s name or color is modified on one device, the `updated_at` helps propagate that change to others. If a label is deleted (or renamed to something else), marking `deleted_at` helps propagate the deletion and prevent ghost references. (Deleting a label might also necessitate cleaning up its entries in the join table – see below.)

* **Normalization:** The labels are in their own table (rather than stored on the task record) to allow many-to-many relationships and reuse. This means a user can tag multiple tasks with the same label and filter tasks by that label easily. The separate table avoids repeating label text on every task and makes it easy to manage label attributes (like color) in one place.

## **TaskLabels (Task-Label Mapping)**

* `task_id` – UUID (FK → Tasks.id) – References a task.

* `label_id` – UUID (FK → Labels.id) – References a label.

* *(Optional:* `user_id` – UUID – References the user) – This field is not strictly required because `task_id` and `label_id` already indirectly link to a user. However, including `user_id` (and enforcing it matches the task’s and label’s owner) can simplify RLS policies and ensure consistency – i.e. prevent linking a task to someone else’s label.）

* **Primary Key:** *(task\_id, label\_id)* composite PK – This prevents duplicate entries (a task can only have a given label once).

* **Indexes:** An index on `task_id` and another on `label_id` speed up queries filtering by task or by label. For example, to fetch all labels associated with a task, or to find all tasks that have a certain label. (Composite PK inherently covers both columns, but single-column indexes are still useful for one-sided lookups.)

**Rationale:** **TaskLabels** is the join table implementing the many-to-many relationship between tasks and labels. This design allows any task to be tagged with multiple labels and any label to tag multiple tasks, as required by the product’s flexible filtering feature. Storing just foreign keys keeps it normalized. We ensure data integrity by:

* Enforcing a composite primary key or a unique constraint so the same task-label pair isn’t entered twice.

* (If using `user_id` here) ensuring that on insert, the `user_id` matches the task’s and label’s owner (this can be done via a CHECK or in application logic) so that users cannot mix data across accounts. If we exclude `user_id` in this table, we rely on foreign key relationships plus RLS policies on the Tasks and Labels tables (Supabase can write a policy like: allow if `EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND t.user_id = auth.uid())` and similarly for labels). Including `user_id` simply makes policies easier (policy: `task_labels.user_id = auth.uid()`) at the cost of a tiny redundancy.

* When a label is deleted (has `deleted_at` set), we should also remove or mark related TaskLabels. Typically, we can cascade delete these join records (since they have no meaning if either side is “deleted”). This can be done with a foreign key ON DELETE CASCADE, or handled in application logic when a label is deleted/tombstoned.

## **Indexes & Constraints**

To ensure the schema performs well and supports offline sync and filtering, we add the following indexes and constraints (in addition to primary keys and foreign keys mentioned):

* **Tasks:**

  * Index on `(user_id, updated_at)` – enables efficient delta queries for sync, e.g. selecting all of a user’s tasks updated since a given timestamp.

  * Index on `(user_id, bucket_key, is_completed, due_at)` – supports fast lookups for listing tasks by bucket (and filtering out completed ones, ordering by due date). This aligns with typical queries like “show all incomplete tasks in THIS WEEK, sorted by due time.”

  * (Optional) Index on `parent_task_id` – speeds up retrieval of sub-tasks for a given parent task (especially if we frequently display or count sub-tasks). If we include `user_id` in this index (i.e. `(user_id, parent_task_id)`), it could further optimize queries under RLS that always filter by user anyway.

* **Labels:**

  * Unique index on `(user_id, name)` – ensures no duplicate label names per user (preserving the intent that each label is distinct for a user). This also makes lookups by name fast if needed (e.g., checking if a label already exists when creating a new one).

* **TaskLabels:**

  * Index on `task_id` – for quickly finding all labels of a task (used when displaying a task’s tags, or when syncing task changes, to retrieve associated labels).

  * Index on `label_id` – for finding all tasks tagged with a given label (used in filtering by label views).

  * (If `user_id` is present, an index on `user_id` (or composite on `user_id, label_id`) can help if querying all tasks for a user with a specific label, though typically queries will join through tasks or labels which already have user scoping.)

* **Foreign Key & Check Constraints:** All foreign keys are in place to maintain referential integrity: tasks.user\_id → users.id; tasks.bucket\_key → time\_buckets.key (if using the table); tasks.parent\_task\_id → tasks.id (with ON DELETE CASCADE for safety); labels.user\_id → users.id; task\_labels.task\_id → tasks.id; task\_labels.label\_id → labels.id. In addition, a CHECK constraint on tasks.bucket\_key (as shown in the architecture SQL snippet) ensures tasks only carry valid bucket keys. These constraints guard against invalid data relationships and help maintain a normalized structure.

## **Row-Level Security (RLS)**

All user-specific tables have RLS policies to enforce that each user can only access their own data. In a Supabase (Postgres) context, we enable RLS and add policies such as:

* **Tasks/Labels:** `user_id = auth.uid()` for SELECT/UPDATE/DELETE, ensuring isolation per user. Inserts must likewise require the inserting user’s ID to match `auth.uid()`. Deletion operations should be handled via setting `deleted_at`.

* **TaskLabels:** If we include `user_id`, the policy is similarly `user_id = auth.uid()`. If not, we write a composite policy that joins to ensure both the associated task and label belong to the user performing the action. For instance, the policy can allow a SELECT on task\_labels only if the corresponding task’s user\_id is `auth.uid()` (and similarly for label) – this ensures users only see tag links for their own items.

These RLS rules uphold privacy by design: no user can ever access another user’s tasks or labels. (The TimeBuckets table, containing only fixed category names, can be world-readable since it’s the same for everyone and contains no sensitive data.) The **per-user isolation** was explicitly required by the architecture.

## **Triggers & Sync Considerations**

To support the real-time sync and conflict resolution strategy, we incorporate some triggers and conventions:

* **`updated_at` trigger:** A trigger on the Tasks (and Labels) tables automatically sets `updated_at = now()` on every INSERT or UPDATE. This ensures server-time ordering for sync. The client treats server time as the source of truth and sets checkpoints to the max server `updated_at` seen per pull.
* **User bootstrap trigger:** `public.handle_new_user()` bound to `auth.users` creates the `public.users` row and avoids race conditions; uses `SECURITY DEFINER`, `SET search_path = public`.

* **Cascade delete trigger (optional):** If using logical deletes, we implement an *on-delete trigger* or procedure to handle sub-task and tag cleanup. For example, when a task is marked deleted (setting `deleted_at`), an optional trigger could propagate that tombstone to its sub-tasks automatically (or we rely on ON DELETE CASCADE if a task is hard-deleted, though in Phase-1 we prefer soft deletes). This ensures no dangling subtasks when a parent is removed. Similarly, if a label is deleted, we could auto-remove its TaskLabel entries. These measures keep the data model consistent without requiring the client to remember to clean up related entities.

* **Sync strategy compatibility:** Clients pull deltas using `updated_at >= (last_checkpoint - 120s)` to heal clock skew, and set their checkpoint to the max server `updated_at`. Because we soft-delete (tombstones), deletions are also propagated. On push, client-generated UUIDs enable idempotent upserts. Conflict resolution favors the latest server `updated_at` for scalars; booleans and sets follow the rules noted above.

## **Forward Compatibility (NLP & “Liquid Glass”)**

The revised schema remains forward-compatible with planned Phase-2 enhancements like Natural Language Processing input and a potential migration to a different backend (Liquid Glass):

* **NLP Integration:** No schema change is needed to handle NLP-powered quick add of tasks. The existing fields (`title`, `due_at`, `recurrence_rule`, etc.) are sufficient to store the structured output of parsing natural language text. For instance, when a user types `"Call plumber tomorrow at 10am"`, the app’s NLP can parse this into `title="Call plumber"`, `due_at=[tomorrow 10am]`. Similarly, `"Submit report every Friday"` yields `title="Submit report"`, `recurrence_rule="every Friday"`, and maybe a `due_at` for the first occurrence. The schema’s support for a timestamp due date and a free-form recurrence rule covers these cases. In the future, if we wanted to store more structured recurrence (e.g., an RRULE format), we could either parse on the fly or add an optional structured field. But as is, the text rule plus application logic to interpret it is adequate and flexible.

