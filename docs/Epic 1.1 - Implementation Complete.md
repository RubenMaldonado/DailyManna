## Epic 1.1 — Time Buckets Foundation (Implementation Complete)

### Executive Summary
Epic 1.1 delivers the foundation for Daily Manna’s opinionated time horizons. Users can now navigate five fixed buckets, view tasks scoped to the selected bucket, see live counts, and quickly add tasks into the current bucket. The implementation follows the SwiftUI-only, local-first architecture with SwiftData as the on-device source of truth and Supabase as the system of record. All schema changes are codified as migrations for automation.

### Scope
- Fixed time buckets supported end-to-end: domain, data (local/remote), view model, and UI.
- Bucket-based navigation: segmented control to switch between buckets.
- Bucket header: displays the selected bucket’s title and count of incomplete tasks.
- Quick Add: create a new task directly into the selected bucket; counts and list update.
- Repository/use-case support for bucket filtering and counts.
- Supabase migration to seed `time_buckets` and enforce `tasks.bucket_key` integrity.

### User Stories (from Phase 1 / Epic 1.1)
- As a user, I can see the five fixed time buckets (THIS WEEK, WEEKEND, NEXT WEEK, NEXT MONTH, ROUTINES).
- As a user, I can view tasks organized by bucket.
- As a user, I understand which bucket is for what timeframe.

### Acceptance Criteria and Verification
- Create TimeBucket enum with five fixed values
  - Implemented in `DailyManna/Domain/Models/TimeBucket.swift` with stable raw values and display names.
- Implement bucket-based navigation UI
  - Segmented `Picker` in `TaskListView` switches buckets and filters tasks.
- Design bucket header components with counts
  - New DS components: `BucketHeader` with `CountBadge` show title + count.
- Seed database with fixed bucket data
  - Local SwiftData seeding in `DataContainer` at startup.
  - Supabase migration file seeds `time_buckets` and adds FK constraint.
- Create basic bucket selection UI
  - Segmented picker implemented; header + list wired to selection.

### What Shipped (Product)
- Bucket navigation: THIS WEEK, WEEKEND, NEXT WEEK, NEXT MONTH, ROUTINES.
- Contextual header showing current bucket and a live, accessible count badge.
- Quick Add: text field + Add button (and Return key) to add a task into the current bucket.
- List view filtered to the selected bucket; completion toggles update counts immediately.

### Technical Highlights (Engineering)
- Domain
  - `TimeBucket` enum with stable keys and display metadata.
  - `TaskUseCases` extended with `countTasks(for:in:includeCompleted:)`.
- Data (SwiftData Local)
  - `SwiftDataTasksRepository` implements `fetchTasks(for:in:)` and new `countTasks(...)` optimized by predicate.
  - Startup seeding of `TimeBucketEntity` ensures local presence of the five buckets.
- Remote (Supabase)
  - `docs/Epic 1.1 - Supabase Migration.sql` creates/seeds `time_buckets`, enforces `tasks.bucket_key` FK, adds `updated_at` trigger, RLS policy, and helpful indexes.
- ViewModel
  - `TaskListViewModel` now tracks `selectedBucket`, `bucketCounts`, and `showCompleted` (future toggle). Exposes `select(bucket:)` and `refreshCounts()`.
- UI / Design System
  - `BucketHeader` and `CountBadge` components added under DS.
  - `TaskListView` updated with segmented `Picker`, bucket header, Quick Add composer, and task list.

### Key Files
- Domain
  - `DailyManna/Domain/Models/TimeBucket.swift`
  - `DailyManna/Domain/UseCases/TaskUseCases.swift`
- Data (Local)
  - `DailyManna/Data/Repositories/SwiftDataTasksRepository.swift`
  - `DailyManna/Data/Utilities/DataContainer.swift` (bucket seeding)
- Remote (Supabase)
  - `docs/Epic 1.1 - Supabase Migration.sql`
- ViewModel & UI
  - `DailyManna/Features/ViewModels/TaskListViewModel.swift`
  - `DailyManna/Features/Views/TaskListView.swift`
  - `DailyManna/DesignSystem/Components/BucketHeader.swift`
  - `DailyManna/DesignSystem/Components/CountBadge.swift`

### Data Model & Migration Details
- Buckets are fixed and represented by stable text keys.
- `tasks.bucket_key` is constrained via FK to `public.time_buckets(key)` to prevent invalid values.
- `updated_at` trigger present for sync; RLS policy ensures per-user isolation.
- Helpful indexes support delta sync and common list queries: `(user_id, updated_at)` and `(user_id, bucket_key, is_completed, due_at)`.
- Migration automation is expected via Supabase CLI (`supabase db push`) and CI.

### Testing Summary
- Unit tests for bucket move and count logic added:
  - `TaskTests.testMoveTaskBetweenBuckets()`
  - `TaskTests.testCountsExcludeCompletedByDefault()`
- Repository tests validate fetch-by-bucket & sorting.
- UI tests: launch and performance smoke; bucket UI is exercised via unit-level integration.
- All tests pass on iOS Simulator (iPhone 16).

### How to Use (Manual QA)
1) Sign in.
2) Use the segmented control to select a bucket.
3) Add a task with the Quick Add field and press Add or Return.
4) Verify the new task appears in the list and the header count increments.
5) Toggle completion to see the count decrement (incomplete-only by default).

### Operational Notes
- Migrations
  - Create a migration: `supabase migration new epic_1_1_time_buckets`
  - Add SQL from `docs/Epic 1.1 - Supabase Migration.sql`.
  - Apply: `supabase db push` (in CI after linking the project).
- CI
  - Add a simple job to run `supabase db push` on merges to main for dev/staging environments.

### Known Limitations / Deferred to Later Phases
- NLP Quick Add and advanced recurrence are Phase-2 items.
- Remote counts API not required; counts computed locally via SwiftData.
- macOS/iPad Sidebar navigation (alternative to segmented picker) can come later.

### Risks & Mitigations
- Data drift between environments: mitigated by versioned migrations and CI-driven `db push`.
- RLS edge cases: covered by user_id scoping and server-side policies.
- Sync edge cases: covered by `updated_at` trigger and tombstones (Phase-1 strategy).

### Next Steps
- Phase 1.2: Label filtering UI within buckets.
- Phase 1.3: Sorting controls and completed toggle per bucket.
- Phase 2: NLP capture, recurrence automation, and richer compose.

### Changelog (Epic 1.1)
- Added `TimeBucket` domain model; seeded buckets in SwiftData.
- Implemented bucket navigation, bucket header with counts, and Quick Add.
- Extended repositories and use cases to support counts.
- Added Supabase migration for `time_buckets` and `tasks.bucket_key` FK.
- Wrote unit and repository tests; green test run on iOS Simulator.


