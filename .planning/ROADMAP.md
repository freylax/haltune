# Roadmap: haltune

**Created:** 2026-01-29
**Updated:** 2026-02-06
**Current milestone:** v0.6 Live Values & Editing

## Overview

Build a TUI-based LinuxCNC HAL manager by first establishing safe FFI bindings to the LinuxCNC HAL C API, then layering thread-safe state management, responsive Vaxis-based TUI for HAL inspection and manipulation, and extensible plugin architecture. The journey progresses from low-level foundations (FFI, state caching) to user-facing features (browser, editing) to UX refinement (view switching) to live value display and editing, culminating in extensibility (plugins) and polish for Raspberry Pi 5 deployment.

## Milestones

- ✅ **v0.1 FFI Foundation** — Phase 1 (shipped 2026-01-29)
- ✅ **v0.2 State Management** — Phase 2 (shipped 2026-01-29)
- ✅ **v0.3 TUI Core** — Phase 3 (shipped 2026-01-29)
- ✅ **v0.4 Configuration & Editing** — Phase 4 (shipped 2026-01-29)
- ✅ **v0.5 View Switching** — Phase 5 (in progress)
- 📋 **v0.6 Live Values & Editing** — Phase 6 (planned)
- 📋 **v0.7 Bookmarks & Plugins** — Phase 7 (planned)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>✅ v0.1-v0.4 Foundation & Core (Phases 1-4) — SHIPPED 2026-01-29</summary>

- [x] Phase 1: FFI Foundation (3/3 plans) — completed 2026-01-29
- [x] Phase 2: State Management (5/5 plans) — completed 2026-01-29
- [x] Phase 3: TUI Core (5/5 plans) — completed 2026-01-29
- [x] Phase 4: Configuration & Editing (3/3 plans) — completed 2026-01-29

**Full details archived to:** `.planning/milestones/v0.4-ROADMAP.md`

</details>

### 🚧 v0.5 View Switching (In Progress)

- [ ] **Phase 5: View Switching** — Alternative view modes for simplified layout

### ✅ v0.6 Live Values & Editing (Planned)

- [ ] **Phase 6: Live Values & Editing** — Real-time value display and inline editing

### Phase Details

*(Full details for Phases 1-4 archived to `.planning/milestones/v0.4-ROADMAP.md`)*

### Phase 5: View Switching

**Goal**: Replace two-panel layout with alternative view modes (tree view and data table displayed separately)

**Depends on**: Phase 4

**Requirements**: LAY-01, LAY-02, LAY-03, SWITCH-01, SWITCH-02, SWITCH-03, TREE-01 through TREE-06, TABLE-01 through TABLE-05, HELP-01 through HELP-03

**Success Criteria** (what must be TRUE):
1. Tree view and data table are never displayed simultaneously in single-view modes
2. User can switch between views with Ctrl-t key
3. Each view uses full terminal width in single-view mode
4. Tree view maintains existing functionality (navigation, editing, search, visibility toggles, real-time updates) - pins, signals, params all viewable and editable
5. Data table maintains existing functionality (real-time updates, editing) - pins, signals, params all viewable and editable
6. Help text reflects current mode's key bindings
7. View switching is blocked when dialogs are open (silent ignore)

**Plans**: 2 plans in 1 wave

Plans:
- [ ] 05-01-PLAN.md — Add ViewMode enum and Ctrl-t key handler
- [ ] 05-02-PLAN.md — Refactor layout for conditional rendering and dynamic help text

### Phase 6: Live Values & Editing

**Goal**: Display real-time pin/signal/parameter values in both tree and table views, with inline editing capability and full signal CRUD operations.

**Depends on**: Phase 5

**Success Criteria** (what must be TRUE):
1. Tree view displays live current values for pins/signals/params (real-time updates via pubsub)
2. Table view displays live current values (real-time updates via pubsub)
3. Values can be edited directly in tree view (Enter on value opens edit)
4. Values can be edited directly in table view (Enter on value opens edit)
5. Signals can be created from tree or table view (new signal dialog)
6. Signals can be removed from tree or table view
7. Signal properties (name, direction, type) can be edited
8. Value changes reflect immediately in HAL and update displayed value

**Plans**: TBD (to be planned after Phase 5 completion)

### Phase 7: Bookmarks & Plugins

**Goal**: Quick access to frequently monitored items and extensible plugin architecture for domain-specific workflows

**Depends on**: Phase 6

**Requirements**: BKMK-01, BKMK-02, BKMK-03, BKMK-04, PLUGIN-01, PLUGIN-02, PLUGIN-03, PLUGIN-04

**Success Criteria** (what must be TRUE):
1. User can add pins/signals/params to bookmark list and quickly jump to bookmarked items from main view
2. Bookmark list persists across application restarts (saved to config file)
3. Plugin manager can discover and list available plugins (even if only foundation plugins exist initially)
4. Plugin foundation provides API for plugins to request scoped views (e.g., PID plugin can show only PID-related components and hide others)

**Plans**: TBD

### Phase 8: Polish & Optimization

**Goal**: Performance tuning for Raspberry Pi 5 deployment, UX refinement, and production readiness

**Depends on**: Phase 7

**Requirements**: None (polish phase focuses on optimization, UX, and edge cases)

**Success Criteria** (what must be TRUE):
1. Application runs smoothly on Raspberry Pi 5 hardware without noticeable lag or stutter during HAL refresh or TUI navigation
2. TUI handles edge cases gracefully (empty HAL, no components loaded, terminal resize, signal interruption)
3. Error messages provide clear, actionable guidance (not just "HAL error: -1" but "Failed to connect to HAL: is LinuxCNC running?")
4. Code is well-documented with examples for common workflows (viewing pins, editing parameters, creating signals)
5. Application has been tested on real LinuxCNC machine with actual HAL components (not just mock HAL environment)

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. FFI Foundation | 3/3 | Complete | 2026-01-29 |
| 2. State Management | 5/5 | Complete | 2026-01-29 |
| 3. TUI Core | 5/5 | Complete | 2026-01-29 |
| 4. Configuration & Editing | 3/3 | Complete | 2026-01-29 |
| 5. View Switching | 0/2 | Not started | - |
| 6. Live Values & Editing | 0/0 | Not started | - |
| 7. Bookmarks & Plugins | 0/0 | Not started | - |
| 8. Polish & Optimization | 0/0 | Not started | - |
