# Roadmap: haltune

## Overview

Build a TUI-based LinuxCNC HAL manager by first establishing safe FFI bindings to the LinuxCNC HAL C API, then layering thread-safe state management, responsive Vaxis-based TUI for HAL inspection and manipulation, bookmark functionality, and extensible plugin architecture. The journey progresses from low-level foundations (FFI, state caching) to user-facing features (browser, editing) to extensibility (plugins), culminating in performance optimization and polish for Raspberry Pi 5 deployment.

## Milestones

- ✅ **v0.1 FFI Foundation** — Phase 1 (shipped 2026-01-29)
- ✅ **v0.2 State Management** — Phase 2 (shipped 2026-01-29)
- ✅ **v0.3 TUI Core** — Phase 3 (shipped 2026-01-29)
- ✅ **v0.4 Configuration & Editing** — Phase 4 (shipped 2026-01-29)
- 🚧 **v0.5 Bookmarks & Plugins** — Phase 5 (in progress)
- 📋 **v0.6 Polish & Optimization** — Phase 6 (planned)

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

### 🚧 v0.5 Bookmarks & Plugins (In Progress)

- [ ] **Phase 5: Bookmarks & Plugins** - Quick access and extensibility

## Phase Details

*(Full details for Phases 1-4 archived to `.planning/milestones/v0.4-ROADMAP.md`)*

### Phase 5: Bookmarks & Plugins

**Goal**: Quick access to frequently monitored items and extensible plugin architecture for domain-specific workflows

**Depends on**: Phase 4

**Requirements**: BKMK-01, BKMK-02, BKMK-03, BKMK-04, PLUGIN-01, PLUGIN-02, PLUGIN-03, PLUGIN-04

**Success Criteria** (what must be TRUE):
1. User can add pins/signals/params to bookmark list and quickly jump to bookmarked items from main view
2. Bookmark list persists across application restarts (saved to config file)
3. Plugin manager can discover and list available plugins (even if only foundation plugins exist initially)
4. Plugin foundation provides API for plugins to request scoped views (e.g., PID plugin can show only PID-related components and hide others)

**Plans**: TBD

Plans:
- [ ] 05-01: TBD
- [ ] 05-02: TBD

### Phase 6: Polish & Optimization

**Goal**: Performance tuning for Raspberry Pi 5 deployment, UX refinement, and production readiness

**Depends on**: Phase 5

**Requirements**: None (polish phase focuses on optimization, UX, and edge cases)

**Success Criteria** (what must be TRUE):
1. Application runs smoothly on Raspberry Pi 5 hardware without noticeable lag or stutter during HAL refresh or TUI navigation
2. TUI handles edge cases gracefully (empty HAL, no components loaded, terminal resize, signal interruption)
3. Error messages provide clear, actionable guidance (not just "HAL error: -1" but "Failed to connect to HAL: is LinuxCNC running?")
4. Code is well-documented with examples for common workflows (viewing pins, editing parameters, creating signals)
5. Application has been tested on real LinuxCNC machine with actual HAL components (not just mock HAL environment)

**Plans**: TBD

Plans:
- [ ] 06-01: TBD
- [ ] 06-02: TBD
- [ ] 06-03: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. FFI Foundation | 3/3 | Complete | 2026-01-29 |
| 2. State Management | 5/5 | Complete | 2026-01-29 |
| 3. TUI Core | 5/5 | Complete | 2026-01-29 |
| 4. Configuration & Editing | 3/3 | Complete | 2026-01-29 |
| 5. Bookmarks & Plugins | 0/0 | Not started | - |
| 6. Polish & Optimization | 0/0 | Not started | - |
