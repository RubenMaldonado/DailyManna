## Testing Strategy — Daily Manna (iOS + macOS)

### Objectives
- **Confidence**: Catch regressions early with fast, deterministic tests.
- **User-centric**: Verify the core flows (add/edit/complete/move/sync) across devices.
- **Safety**: Prove RLS isolation, tombstone deletes, and conflict rules work.
- **Performance**: Keep local UX snappy (<100ms for local actions) and sync scalable.

### Test Pyramid & Scope
- **Unit (majority, fastest)**: Pure Swift logic in `Domain`, `UseCases`, utilities.
- **Integration (selective)**: `Data` repositories with SwiftData in-memory; Supabase staging for contracts, RLS, delta queries, and tombstones.
- **UI (happy paths + critical edges)**: XCUITest for end-to-end flows; snapshot tests for visual regressions.

### What to Test by Layer
#### Domain & Use Cases (pure Swift)
- **Models**: `Task`, `Label`, `TimeBucket` invariants (e.g., bucket keys valid; soft-delete state; displayName/sortOrder).
- **Rules**: Completion toggles set `completedAt`; label-set merge semantics; recurrence placeholder behavior (until NLP).
- **Conflict policy helpers**: Last-write-wins for scalars by `updatedAt`; completion skew preference; set-union for labels.

#### Data Layer — Local (SwiftData)
- **Repository behavior**: `SwiftDataTasksRepository`, `SwiftDataLabelsRepository` using an in-memory `ModelContainer`.
  - Fetch by bucket with sorting; create/update/delete (soft-delete sets `deletedAt`); purge of tombstones older than threshold.
  - Sub-tasks queries and cascade constraints (where applicable in the entity mapping layer).
- **Migrations**: Schema version bump runs and preserves data; backfill/transform fields if needed.

#### Data Layer — Remote (Supabase)
- **Contract tests (live against staging)** for `SupabaseTasksRepository`/`SupabaseLabelsRepository`:
  - DTO mapping fidelity (round-trip domain → DTO → DB → DTO → domain).
  - Delta queries by `updated_at`; tombstone updates via `deleted_at`.
  - RLS: unauthorized access denied; owner access allowed.
  - Basic CRUD + filtering by `bucket_key`, `is_completed`, `due_at`.
- **Auth flows (staging)**: Token exchange happy path (Apple/Google) with test providers or stubbed tokens; session restore path validated.

#### Sync Orchestrator (`Core/Sync/SyncService.swift`)
- **Push-first**: Marks `needsSync` false after successful remote upsert.
- **Pull-then-merge**: LWW applied deterministically; label-set union applied; soft-deletes remove/hide locally.
- **Resilience**: Retries on transient network errors; safe re-entrancy (ignores concurrent sync).
- **Periodic scheduling**: Timer-based sync triggers without UI thread blocking.

#### UI & Design System
- **SwiftUI unit tests (ViewInspector)** for `DesignSystem/Components` (e.g., `TaskCard`, `LabelChip`): binding state changes, accessibility labels/traits, dynamic type.
- **Snapshot tests (optional)** using `pointfreeco/swift-snapshot-testing` for key screens/widgets in light/dark, standard/reduced transparency.
- **XCUITest**: end-to-end across iOS and macOS for:
  - Sign in, add task, label task, move between buckets, complete, offline then online sync.
  - macOS keyboard flows (focus rings, shortcuts) and command palette if present.

### Test Data, Fixtures, and Determinism
- **Factories**: Lightweight builders for `Task`/`Label` with deterministic defaults (seeded UUIDs, fixed dates).
- **Date provider**: Inject a `NowProvider` into code that touches time to avoid flaky `Date()` usage.
- **Model container**: In-memory SwiftData for unit/integration; reset between tests.
- **Supabase staging**: Separate project with seed SQL, dedicated test users, and nightly reset job.

### Tooling & Libraries
- **Built-in**: XCTest, XCUITest, `XCTMeasureMetrics` for performance.
- **Optional**:
  - `ViewInspector` for SwiftUI view assertions (unit-level).
  - `swift-snapshot-testing` for visual regression coverage of critical views.
  - `Nimble`/`Quick` if you prefer BDD-style syntax (optional).

### Test Organization
- Targets already present:
  - `DailyMannaTests/` (unit + integration)
  - `DailyMannaUITests/` (UI)
- Suggested folders under `DailyMannaTests/`:
  - `Domain/` (models, use-cases)
  - `Data/SwiftData/` (local repos, migrations)
  - `Data/Supabase/` (live contract tests guarded by env flags)
  - `Sync/` (sync scenarios and conflict rules)
  - `Support/` (factories, date provider, in-memory containers, test doubles)

### CI/CD and Environments
- **CI provider**: Xcode Cloud or GitHub Actions (either is fine; Actions sample below).
- **Secrets**: Store Supabase URL/keys and test user creds as CI secrets; never in repo.
- **Plans**:
  - On PR: run unit + local integration (SwiftData) + light UI smoke.
  - Nightly: run full integration against Supabase staging and full UI suite.
- **xcodebuild examples**:
  - Unit/local integration (iOS):
    - `xcodebuild -project DailyManna.xcodeproj -scheme DailyManna -destination 'platform=iOS Simulator,name=iPhone 15' -enableCodeCoverage YES test`
  - UI (iOS):
    - `xcodebuild -project DailyManna.xcodeproj -scheme DailyMannaUITests -destination 'platform=iOS Simulator,name=iPhone 15' test`
  - macOS unit/UI:
    - `xcodebuild -project DailyManna.xcodeproj -scheme DailyManna -destination 'platform=macOS' test`

### Coverage Goals (gating where noted)
- **Domain & Use Cases**: ≥ 90% (gate).
- **Repositories (local)**: ≥ 85%.
- **Sync logic**: ≥ 85% (gate key paths: LWW, tombstones, label merge).
- **Overall project**: ≥ 80%.

### Performance Benchmarks
- **Local interactions**: Add/edit/complete measured < 100ms p50, < 200ms p95.
- **List scrolling**: No dropped frames with 5k tasks on target devices.
- **Sync**: Batch size/config verified to keep UI responsive; measure push/pull wall time.

### Security & Privacy Tests
- **RLS enforcement (staging)**: Cross-user access is denied across `tasks`, `labels`, `task_labels`.
- **PII scrubbing**: `Core/Utilities/Logger.swift` does not log email/token content.
- **Keychain**: `KeychainService` stores/clears session; no plaintext secrets.

### Test Execution Controls
- **Env flags**: Use `INTEGRATION_TESTS=1` to enable staging tests; skip when unset.
- **Retries**: Apply minimal retries for flaky network tests; never for logic tests.
- **Quarantines**: Temporarily tag flaky UI tests; fix before next release.

### Immediate Implementation Plan (Milestones)
1. Domain unit tests for `Task`, `Label`, `TimeBucket`; factories + date provider.
2. SwiftData repository tests with in-memory container (CRUD, soft-delete, purge, filtering).
3. SyncService unit tests (push/pull, LWW, tombstones, periodic scheduling with a testable clock).
4. Minimal XCUITest smoke: sign-in screen loads; add → complete → move flow.
5. Supabase contract tests (guarded by env) for CRUD, delta, tombstones, RLS.
6. Snapshot tests for `TaskListView` states (loading/empty/error/offline) and `TaskCard`.
7. CI wiring: PR (fast suite) + nightly (full suite), coverage gates on Domain/Sync.

### How to Run Locally
- From Xcode: Select the appropriate Test Plan or scheme and press Run Tests.
- From CLI (example):
  - Unit/local integration: see `xcodebuild` examples above.
  - Enable staging integration: prefix with `INTEGRATION_TESTS=1` and provide Supabase env vars.

### Risks & Mitigations
- **Network flakiness**: Keep staging tests opt-in and retried once; most logic covered offline.
- **Clock skew**: Base conflict order on server `updated_at`; inject `NowProvider` in tests.
- **SwiftUI brittleness**: Prefer ViewInspector for logic; limit snapshot scope to high-value screens.

---

This strategy aligns with the architecture in `docs/Daily Manna - Architecture Review.md` and the current code structure (`Domain`, `Data`, `Core/Sync`, `Features`). It prioritizes fast unit coverage of business rules, realistic repository behavior via in-memory SwiftData, and targeted staging tests to prove contracts, RLS, and sync behavior end-to-end.


