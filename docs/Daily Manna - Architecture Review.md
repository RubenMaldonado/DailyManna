# Architecture Review Document — “Daily Manna” (Universal iOS \+ macOS)

# **0\) Executive Summary**

Daily Manna is a universal Swift/SwiftUI app for iOS and macOS with Supabase (Postgres) as the source of truth. Phase-1 excludes NLP; the focus is a polished Apple experience with fast local UX and deterministic multi-device sync across a user’s Apple devices. The domain centers on fixed time buckets and taggable tasks with optional sub-tasks.

# **1\) Goals & Scope**

* Platforms: iOS (iPhone/iPad) and macOS (universal codebase).  
* Backend: Supabase (Postgres \+ RLS \+ Realtime \+ Auth).  
* Auth: Sign in with Apple and Google accounts.  
* Phase-1 features: Time buckets; tasks with labels and subtasks; rich descriptions; due dates; completion; realtime multi-device sync; offline-first UX. (NLP postponed to Phase-2.)  
* Forward compatibility: Clean separation to enable a future migration to Liquid Glass without a rewrite.

# **2\) Product Requirements (Summary)**

## **Core Model**

* Five fixed time buckets: THIS WEEK, WEEKEND, NEXT WEEK, NEXT MONTH, ROUTINES.  
* Entities: Users, TimeBuckets, Tasks, Labels, TaskLabels (M:N); Tasks may have sub-tasks via parent\_task\_id.

## **Key Flows**

* Quick add, edit, complete, move between buckets.  
* Filter tasks by labels within/across buckets.  
* Works offline; changes sync when online.  
* Same account → all devices stay in sync.

## **Non-Functional**

* Snappy interactions (\<100ms UI latency for local ops).  
* Safe multi-device merges with predictable conflict rules.  
* Privacy by default (RLS; per-user isolation).  
* Modular codebase ready to scale.

# **3\) High-Level Architecture**

SwiftUI Views (iOS/macOS) — Pure SwiftUI, Custom Design System
       │  
  ViewModels (@MainActor, async/await)  
       │  
Domain Layer (Task, Label, Bucket; pure Swift)  
       │  
Repositories (protocols)  
 ├─ SwiftDataRepository (local authoritative store)  
 └─ RemoteRepository (Supabase transport)  
       │  
  Sync Orchestrator  
 (pull, push, realtime)  
       │  
Supabase (Postgres \+ RLS \+ Realtime \+ Auth)

Design notes:

* **Modern SwiftUI-First**: Pure SwiftUI architecture with custom design system, no UIKit dependencies.
* **Local-first UX**: SwiftData is the on-device truth for rendering; the server is the system-of-record for persistence/sharing.  
* **Repository \+ Adapter pattern** isolates Supabase. A second adapter can target Liquid Glass later with no UI/domain changes.  
* **Dependency Injection**: Clean architecture with DI container for testability and modularity.
* **Sync Orchestrator** performs delta pulls, pushes, and applies Realtime diffs.

# **4\) Data Model (DB) — Supabase**

Based on your schema with production-grade tweaks (UUID/ULID, timestamps, tombstones).

## **Tables**

* users (managed by Auth; app keeps a profile row if needed).  
* time\_buckets (seeded with five fixed buckets; stable keys).  
* tasks: id UUID (PK), user\_id UUID, bucket\_key TEXT, parent\_task\_id UUID?, title TEXT, description TEXT?, due\_at TIMESTAMPTZ?, recurrence\_rule TEXT?, is\_completed BOOL, completed\_at TIMESTAMPTZ?, created\_at, updated\_at, deleted\_at (tombstone).  
* labels: id, user\_id, name, color.  
* task\_labels: task\_id, label\_id.

## **Indexes**

* tasks (user\_id, updated\_at) for sync.  
* tasks (user\_id, bucket\_key, is\_completed, due\_at) for list views.  
* task\_labels (task\_id) and (label\_id).

## **RLS (Row-Level Security)**

* Enabled on all tables; policy pattern: user\_id \= auth.uid().  
* Insert/update guarded to the session’s user; deleted\_at required for logical deletes.

## **Triggers**

* updated\_at auto-touch on INSERT/UPDATE.  
* Optional: propagate deleted\_at to child rows (e.g., cascade for sub-tasks).

# **5\) Local Storage — SwiftData**

* Models mirror server tables and include sync metadata: remoteID, updatedAt, deletedAt, version.  
* Deterministic IDs: client creates UUID/ULID at task creation → safe to upsert on server (idempotent).  
* Migrations: SwiftData schema versions track app releases.

# **6\) Auth — Apple & Google**

* Supabase Auth as the identity provider.  
* Apple: native “Sign in with Apple” from iOS/macOS → obtain identity token → exchange with Supabase.  
* Google: OAuth via Supabase (ASWebAuthenticationSession on Apple platforms).  
* Sessions stored in Keychain; short-lived access token \+ refresh handled by the SDK.

# **7\) Sync Strategy (Multi-Device)**

## **Pull (delta)**

* At app start and on schedule: SELECT \* FROM tasks WHERE updated\_at \> last\_sync OR deleted\_at IS NOT NULL AND user\_id \= auth.uid().  
* Apply to SwiftData: upserts; purge items with deleted\_at set.

## **Push**

* Local pending mutations queue.  
* Upsert rows with client-generated id; server assigns updated\_at.  
* If server returns a newer updated\_at, last-write-wins (LWW) for scalar fields; label sets merge (union).

## **Realtime**

* Subscribe to Postgres Changes for tasks, labels, task\_labels filtered by user\_id.  
* Apply incoming changes to SwiftData for instant cross-device updates.

## **Conflict Rules**

* Scalar fields: LWW by updated\_at.  
* Boolean toggles (is\_completed): prefer “completed” if timestamps are within a small skew window (e.g., 2s).  
* Sets (labels): union client & server; remove only if explicit delete recorded.

## **Offline**

* All operations mutate SwiftData first (optimistic); failed pushes are retried with exponential backoff.

# **8\) App Organization (Scalable Code)**

## **Targets/Packages**

* App (platform entry points \+ Scenes).  
* Features/Tasks, Features/Labels, Features/Buckets.  
* DesignSystem (components, tokens).  
* Domain (pure Swift types, use-cases).  
* Data/SwiftDataStore (models, migrations, queries).  
* Data/SupabaseTransport (SQL/REST, Realtime, Auth).  
* Sync (orchestrator, conflict logic).  
* Utilities (Logging, Analytics, FeatureFlags).

## **UI Best Practices — Modern SwiftUI-Only Architecture**

* **Pure SwiftUI**: No UIKit dependencies; modern SwiftUI-only approach for all UI.
* **Custom Design System**: Brand-specific color tokens and components, not relying on system colors.
* **MVVM Pattern**: Clean separation with ViewModels using `@MainActor` and async/await.
* **Previewable Components**: All UI components designed with SwiftUI previews.
* **Platform Optimization**: Deep keyboard support on macOS, widgets & App Intents.
* **Accessibility**: Built-in SwiftUI accessibility features with custom design tokens.
* **Command palette and Spotlight integration**: Native iOS/macOS integration.

# **9\) Portability Plan — Future “Liquid Glass” Migration**

* Repository protocols: TasksRepository, LabelsRepository, BucketsRepository.  
* Current impl: SupabaseRepository. Future: LiquidGlassRepository.  
* DTO/Mapper boundary separates domain models from transport payloads.  
* Feature flags to enable dual-write, read-from-A/write-to-B, or strangler rollout.  
* Bulk export/import: periodic server job (CSV/JSON) to object store; one-click export for user data portability.  
* Avoid backend-specific logic in the client; keep queries in repositories.

# **10\) Security & Privacy**

* RLS enforces per-user isolation server-side.  
* App secrets in Keychain; never in plist.  
* All network calls over TLS; ATS enabled.  
* Privacy manifest describes data use.  
* PII minimization: store only what’s required.

# **11\) Observability & Operations**

* Client: Structured logs (OSLog); crash & performance telemetry (e.g., Sentry/Crashlytics) with scrubbed PII.  
* Backend: DB logs for slow queries; monitor Realtime connection errors; daily row counts per user for sanity checks.

# **12\) CI/CD**

* Branches: trunk-based, feature flags.  
* Builds: Xcode Cloud or GitHub Actions → TestFlight (iOS/macOS).  
* Schema: SQL migrations via Supabase CLI, versioned with app releases.  
* Secrets: per-env (Dev/Staging/Prod) in CI; no plaintext in repo.

# **13\) Testing Strategy (Phase-1)**

## **Unit Tests (Swift)**

* Domain logic (bucket moves, completion rules, label merges).  
* Repository fakes for deterministic tests.

## **Integration Tests**

* Staging Supabase project with separate DB.  
* Verify RLS (unauthorized denied; rightful access allowed).  
* CRUD \+ Realtime propagation.  
* Auth flows (Apple/Google) with test providers or token stubs.

## **UI Tests (XCUITest)**

* Add/edit/complete/move; offline capture then online sync.  
* macOS keyboard flows and command palette.  
* Snapshot tests for key screens and widgets.

## **Sync Tests**

* Bidirectional edits on two simulated devices; assert LWW & label-set merge.  
* Tombstone propagation; recovery after network partition.

## **Performance**

* List scrolling under 5k tasks; quick add latency under 100ms (local).  
* Sync batch sizes tuned (e.g., 200–500 rows per page).

## **Regression/Smoke**

* Pre-release suite over staging DB; seeded data fixtures; pipeline blocks on failures.

# **14\) Release Phasing**

## **Phase-0 (Foundation)**

* Supabase project, schema, RLS, triggers.  
* SwiftData models & migrations.  
* Auth (Apple/Google).  
* Minimal sync.

## **Phase-1 (MVP)**

* Tasks/Labels/Buckets UX.  
* Widgets & App Intents.  
* Full delta sync \+ Realtime.  
* Testing harness & CI/CD.

## **Phase-2 (Enhancements)**

* NLP capture & recurrence automation.  
* Collaboration options.  
* Analytics.  
* Liquid Glass exploration (dual-write pilot).

# **15\) Open Risks & Mitigations**

* Realtime edge cases (delete payload filtering): rely on tombstones and periodic delta pulls.  
* Clock skew: use server updated\_at; ignore client clocks for ordering.  
* Auth UX on macOS: robust redirect handling with ASWebAuthenticationSession.

# **16\) Appendix — Exemplar SQL (abridged)**

\-- tasks (abridged)  
create table if not exists tasks (  
  id uuid primary key default gen\_random\_uuid(),  
  user\_id uuid not null,  
  bucket\_key text not null check (bucket\_key in ('THIS\_WEEK','WEEKEND','NEXT\_WEEK','NEXT\_MONTH','ROUTINES')),  
  parent\_task\_id uuid null references tasks(id) on delete cascade,  
  title text not null,  
  description text,  
  due\_at timestamptz,  
  recurrence\_rule text,  
  is\_completed boolean not null default false,  
  completed\_at timestamptz,  
  created\_at timestamptz not null default now(),  
  updated\_at timestamptz not null default now(),  
  deleted\_at timestamptz  
);

\-- touch updated\_at  
create or replace function touch\_updated\_at()  
returns trigger language plpgsql as $$  
begin  
  new.updated\_at \= now();  
  return new;  
end $$;

create trigger trg\_tasks\_updated\_at  
before update on tasks  
for each row execute function touch\_updated\_at();

\-- RLS  
alter table tasks enable row level security;  
create policy "task\_owner"  
on tasks for all  
using (user\_id \= auth.uid())  
with check (user\_id \= auth.uid());

\-- helpful indexes  
create index if not exists idx\_tasks\_user\_updated on tasks (user\_id, updated\_at);  
create index if not exists idx\_tasks\_user\_bucket on tasks (user\_id, bucket\_key, is\_completed, due\_at);

# **Sources from your documents**

* Buckets, feature intent, and UX philosophy — "Daily Manna: Value Proposition & Feature Set".  
* Core entities and relationships — "Data Model with Time Buckets".