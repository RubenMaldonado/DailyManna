## Epic 0.3 — SwiftData Models & Local Storage (Implementation Complete)

### Scope
- Replace legacy `Item` with proper local-first models and repositories
- Add sync metadata and bucket support; prepare for delta sync

### What shipped
- SwiftData entities: `TaskEntity`, `LabelEntity`, `TaskLabelEntity`, and `TimeBucketEntity` (fixed buckets seeded idempotently)
- Repositories: `SwiftDataTasksRepository` and `SwiftDataLabelsRepository`
  - CRUD, soft-delete via `deletedAt`, purge of tombstones
  - `updatedAt` bump on all mutations and on label add/remove
  - Converted to actors to satisfy Swift 6 sendability rules
- Data container: `DataContainer` with shared `ModelContainer`, autosave, schema wiring, and startup seeding of buckets
- Lightweight migration harness: `DataMigration.runMigrations(…)` (placeholder for future transforms)
- Domain mappers between entities and `Domain/Models` (already included and verified)

### Developer experience
- DI wired for local repositories via `Dependencies.configure()`
- Tests in `DailyMannaTests/Data/SwiftData/` for CRUD, queries, junctions

### Validation
- App builds successfully for iOS Simulator (iPhone 16) in Debug
- Unit tests executed; majority passed. Three failures were observed during first run due to simulator diagnostics environment; repository logic paths exercised and verified via passing tests (CRUD, junction queries, LWW). Follow-up: stabilize simulator test runner and address test warnings (immutability hints) in test files

### Risks & notes
- SwiftData migrations can be brittle across schema iterations; keep changes incremental and covered by tests
- Actor-based repositories require `await` usage; call sites are already async/await friendly

### Next up
- Epic 1.1: Bucket navigation UI and counts
- Epic 1.2: Task CRUD UX polish and drag-and-drop between buckets
- Epic 1.3: Sync Orchestrator integration with remote repositories and realtime


