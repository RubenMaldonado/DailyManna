# Daily Manna - Development Roadmap & Epic Prioritization

## Overview

This document outlines a prioritized, iterative development approach for Daily Manna, focusing on delivering value incrementally while building a robust foundation for future enhancements. The roadmap is structured around epics that can be developed, tested, and released independently, following the principle of "working software over comprehensive documentation."

## Development Philosophy

**Iterative Approach**: Start simple, validate early, iterate quickly
- **Phase 0**: Foundation & Infrastructure
- **Phase 1**: Core MVP with Essential Features
- **Phase 2**: Enhanced User Experience
- **Phase 3**: Advanced Features & Polish

---

## Phase 0: Foundation & Infrastructure (Weeks 1-3)

### Epic 0.1: Project Architecture Setup
**Priority**: Critical
**Estimated Effort**: 1 week
**Goal**: Establish scalable, maintainable codebase structure

**User Stories**:
- As a developer, I need a modular project structure that supports future scaling
- As a developer, I need clear separation of concerns between UI, domain, and data layers

**Acceptance Criteria**:
- [ ] Refactor existing Xcode project into modular packages:
  - `App` (main target)
  - `Domain` (pure Swift business logic)
  - `Data` (SwiftData models and repositories)
  - `DesignSystem` (UI components and tokens)
  - `Features` (feature-specific UI modules)
- [ ] Implement Repository pattern with protocols
- [ ] Set up dependency injection container
- [ ] Create basic logging and error handling infrastructure

### Epic 0.2: Supabase Integration & Authentication
**Priority**: Critical
**Estimated Effort**: 1.5 weeks
**Goal**: Connect app to Supabase backend with secure authentication

**User Stories**:
- As a user, I can sign in with Apple to access my tasks securely
- As a user, I can sign in with Google as an alternative authentication method
- As a developer, I need secure session management and token refresh

**Acceptance Criteria**:
- [ ] Set up Supabase project with development environment
- [ ] Implement database schema as defined in data model
- [ ] Create RLS policies for user isolation
- [ ] Integrate Supabase Swift SDK
- [ ] Implement Sign in with Apple
- [ ] Implement Google OAuth
- [ ] Set up secure session management with Keychain
- [ ] Create authentication state management

### Epic 0.3: Swift Data Models & Local Storage
**Priority**: Critical
**Estimated Effort**: 1 week
**Goal**: Establish local-first data foundation with SwiftData

**User Stories**:
- As a developer, I need SwiftData models that mirror the server schema
- As a user, my app should work offline and sync when connected

**Acceptance Criteria**:
- [ ] Replace existing `Item` model with proper domain models:
  - `Task` model with all required fields
  - `Label` model
  - `TimeBucket` model (seeded data)
- [ ] Implement SwiftData migrations strategy
- [ ] Add sync metadata fields (remoteID, updatedAt, deletedAt)
- [ ] Create basic repository implementations for local storage
- [ ] Implement UUID generation for offline-first approach

---

## Phase 1: Core MVP - Essential Task Management (Weeks 4-8)

### Epic 1.1: Time Buckets Foundation
**Priority**: High
**Estimated Effort**: 1 week
**Goal**: Implement the core organizational structure of Daily Manna

**User Stories**:
- As a user, I can see the five fixed time buckets (THIS WEEK, WEEKEND, NEXT WEEK, NEXT MONTH, ROUTINES)
- As a user, I can view tasks organized by bucket
- As a user, I understand which bucket is for what timeframe

**Acceptance Criteria**:
- [ ] Create TimeBucket enum with five fixed values
- [ ] Implement bucket-based navigation UI
- [ ] Design bucket header components with counts
- [ ] Seed database with fixed bucket data
- [ ] Create basic bucket selection UI

### Epic 1.2: Basic Task CRUD Operations
**Priority**: High
**Estimated Effort**: 2 weeks
**Goal**: Users can create, read, update, and delete tasks

**User Stories**:
- As a user, I can add a new task with a title and bucket
- As a user, I can edit task details
- As a user, I can mark tasks as complete
- As a user, I can delete tasks
- As a user, I can move tasks between buckets

**Acceptance Criteria**:
- [ ] Implement task creation form with bucket selection
- [ ] Create task list view showing tasks by bucket
- [ ] Add task editing capabilities
- [ ] Implement task completion with visual feedback
- [ ] Add task deletion with confirmation
- [ ] Enable drag-and-drop between buckets (iOS/macOS appropriate)
- [ ] Add basic task details (title, description, due date)

### Epic 1.3: Basic Sync Implementation
**Priority**: High
**Estimated Effort**: 2 weeks
**Goal**: Ensure data consistency across devices

**User Stories**:
- As a user, changes I make on one device appear on my other devices
- As a user, I can work offline and changes sync when I reconnect
- As a user, I don't lose data due to sync conflicts

**Acceptance Criteria**:
- [ ] Implement basic push/pull sync strategy
- [ ] Create sync orchestrator with delta queries
- [ ] Handle offline mutations queue
- [ ] Implement last-write-wins conflict resolution
- [ ] Add sync status indicators in UI
- [ ] Create retry logic for failed syncs
- [ ] Implement Supabase Realtime subscriptions

### Epic 1.4: Design System Implementation
**Priority**: Medium-High
**Estimated Effort**: 1.5 weeks
**Goal**: Establish consistent, accessible UI foundation

**User Stories**:
- As a user, the app feels polished and consistent across all screens
- As a user with accessibility needs, the app works well with system settings
- As a developer, I have reusable components that maintain consistency

**Acceptance Criteria**:
- [ ] Implement design token system from design specification
- [ ] Create surface/material abstraction for future Liquid Glass compatibility
- [ ] Build core UI components:
  - Task cells with proper states
  - Bucket headers
  - Basic buttons and forms
  - Loading states
- [ ] Implement accessibility features (VoiceOver, Dynamic Type, Reduce Motion)
- [ ] Add Dark Mode support
- [ ] Create SwiftUI preview catalog for components

---

## Phase 2: Enhanced User Experience (Weeks 9-14)

### Epic 2.1: Labels & Filtering System
**Priority**: Medium-High
**Estimated Effort**: 2 weeks
**Goal**: Add flexible organization layer across buckets

**User Stories**:
- As a user, I can create and assign colored labels to tasks
- As a user, I can filter tasks by labels within and across buckets
- As a user, I can manage my label library

**Acceptance Criteria**:
- [ ] Implement label creation and management
- [ ] Add label assignment to tasks (many-to-many)
- [ ] Create label filtering UI
- [ ] Implement label color system
- [ ] Add label chips to task display
- [ ] Create saved filter views
- [ ] Sync label data across devices

### Epic 2.2: Subtasks & Rich Descriptions
**Priority**: Medium
**Estimated Effort**: 1.5 weeks
**Goal**: Enable detailed task breakdown and context

**User Stories**:
- As a user, I can break large tasks into smaller subtasks
- As a user, I can add rich descriptions with formatting and links
- As a user, I can track progress on complex tasks

**Acceptance Criteria**:
- [ ] Implement hierarchical task structure (parent/child)
- [ ] Create subtask UI with progress indicators
- [ ] Add rich text editing for descriptions (Markdown support)
- [ ] Implement subtask completion logic
- [ ] Add subtask drag-and-drop reordering
- [ ] Sync subtask relationships

### Epic 2.3: Due Dates & Scheduling
**Priority**: Medium
**Estimated Effort**: 1 week
**Goal**: Add time-specific task management within buckets

**User Stories**:
- As a user, I can set specific due dates and times for tasks
- As a user, I can see overdue tasks clearly
- As a user, I can sort tasks by due date within buckets

**Acceptance Criteria**:
- [ ] Add due date/time picker to task creation/editing
- [ ] Implement due date display in task lists
- [ ] Create overdue task indicators
- [ ] Add due date-based sorting options
- [ ] Implement basic reminder system (local notifications)

### Epic 2.4: macOS-Specific Enhancements
**Priority**: Medium
**Estimated Effort**: 1.5 weeks
**Goal**: Optimize experience for macOS users

**User Stories**:
- As a macOS user, I can use keyboard shortcuts for common actions
- As a macOS user, I have right-click context menus
- As a macOS user, the app feels native to macOS

**Acceptance Criteria**:
- [ ] Implement keyboard shortcuts (⌘N for new task, etc.)
- [ ] Add context menus for tasks and buckets
- [ ] Optimize layout for macOS (menu bar, window management)
- [ ] Add Focus and tab navigation
- [ ] Implement proper macOS window restoration

---

## Phase 3: Advanced Features & Polish (Weeks 15-20)

### Epic 3.1: Routines & Recurrence
**Priority**: Medium
**Estimated Effort**: 2 weeks
**Goal**: Implement sophisticated recurring task management

**User Stories**:
- As a user, I can create recurring tasks with various patterns
- As a user, completing a recurring task generates the next instance
- As a user, I can manage my routine tasks effectively

**Acceptance Criteria**:
- [ ] Implement recurrence rule parsing and storage
- [ ] Create next-instance generation logic
- [ ] Build recurring task UI with pattern selection
- [ ] Add routine-specific views and management
- [ ] Implement recurrence conflict handling in sync

### Epic 3.2: Widgets & App Intents
**Priority**: Medium
**Estimated Effort**: 1.5 weeks
**Goal**: Extend app presence beyond main interface

**User Stories**:
- As a user, I can see my tasks in widgets on home screen/desktop
- As a user, I can add tasks via Siri or Shortcuts
- As a user, I can quickly check my progress without opening the app

**Acceptance Criteria**:
- [ ] Create small/medium/large widget variants
- [ ] Implement App Intents for Siri integration
- [ ] Add Shortcuts support for task creation
- [ ] Create interactive widget actions (mark complete)
- [ ] Optimize widget performance and updates

### Epic 3.3: Search & Command Palette
**Priority**: Medium
**Estimated Effort**: 1 week
**Goal**: Enable quick task discovery and actions

**User Stories**:
- As a user, I can search across all my tasks quickly
- As a user, I can use a command palette for quick actions
- As a user, I can find tasks by content, labels, or bucket

**Acceptance Criteria**:
- [ ] Implement full-text search across tasks
- [ ] Create command palette UI (⌘K on macOS)
- [ ] Add search filters and suggestions
- [ ] Integrate with Spotlight on macOS
- [ ] Add recent items and smart suggestions

### Epic 3.4: Performance & Polish
**Priority**: Medium
**Estimated Effort**: 1.5 weeks
**Goal**: Optimize performance and add final polish

**User Stories**:
- As a user with many tasks, the app remains responsive
- As a user, interactions feel smooth and delightful
- As a user, error states are handled gracefully

**Acceptance Criteria**:
- [ ] Optimize list performance for large datasets
- [ ] Add smooth animations and micro-interactions
- [ ] Implement proper error handling and retry logic
- [ ] Add empty states and loading skeletons
- [ ] Performance testing and optimization
- [ ] Final accessibility audit and improvements

---

## Future Considerations (Post-MVP)

### Phase 4: Advanced Features
- **Epic 4.1**: Natural Language Processing for task input
- **Epic 4.2**: Collaboration features (shared buckets/tasks)
- **Epic 4.3**: Analytics and insights
- **Epic 4.4**: Liquid Glass backend migration preparation

### Phase 5: Platform Expansion
- **Epic 5.1**: Apple Watch companion app
- **Epic 5.2**: iPad-specific optimizations
- **Epic 5.3**: Apple Vision Pro exploration

---

## Success Metrics

### Phase 0-1 Success Criteria:
- [ ] User can create, complete, and sync tasks across devices
- [ ] Authentication works reliably
- [ ] App works offline with proper sync
- [ ] Basic time bucket organization is intuitive

### Phase 2-3 Success Criteria:
- [ ] Users actively use labels for organization
- [ ] Subtasks improve task completion rates
- [ ] macOS users adopt keyboard shortcuts
- [ ] App feels polished and production-ready

## Risk Mitigation

1. **Sync Complexity**: Start with simple last-write-wins, iterate to handle edge cases
2. **Performance**: Implement pagination and lazy loading early
3. **User Adoption**: Focus on core value proposition (time buckets) before adding complexity
4. **Platform Differences**: Design mobile-first, enhance for desktop

## Dependencies & Assumptions

- Supabase service availability and performance
- Apple's SwiftData stability and feature set
- Access to beta testing users for feedback
- Design system tokens finalized before UI implementation

---

*This roadmap is living document and should be updated based on user feedback, technical discoveries, and changing priorities.*


