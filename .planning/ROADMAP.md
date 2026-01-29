# Roadmap: haltune

## Overview

Build a TUI-based LinuxCNC HAL manager by first establishing safe FFI bindings to the LinuxCNC HAL C API, then layering thread-safe state management, responsive Vaxis-based TUI for HAL inspection and manipulation, bookmark functionality, and extensible plugin architecture. The journey progresses from low-level foundations (FFI, state caching) to user-facing features (browser, editing) to extensibility (plugins), culminating in performance optimization and polish for Raspberry Pi 5 deployment.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: FFI Foundation** - Safe Zig bindings to LinuxCNC HAL C API
- [ ] **Phase 2: State Management** - Thread-safe caching and synchronization
- [ ] **Phase 3: TUI Core** - Vaxis-based HAL inspection interface
- [ ] **Phase 4: Configuration & Editing** - HAL manipulation and persistence
- [ ] **Phase 5: Bookmarks & Plugins** - Quick access and extensibility
- [ ] **Phase 6: Polish & Optimization** - Performance tuning and UX refinement

## Phase Details

### Phase 1: FFI Foundation

**Goal**: Safe Zig wrappers for LinuxCNC HAL C API functions with correct struct alignment, memory management, and version compatibility

**Depends on**: Nothing (first phase)

**Requirements**: FFI-01, FFI-02, FFI-03, FFI-04, FFI-05

**Success Criteria** (what must be TRUE):
1. Zig code successfully calls LinuxCNC HAL C API functions (hal_init, hal_comp_name, etc.) with proper type conversions between Zig and C types
2. FFI layer compiles and runs on ARM64 (Raspberry Pi 5) without struct alignment errors or memory corruption
3. All memory allocated by C functions is properly freed (verified by valgrind or Zig's general purpose allocator leak detection)
4. HAL mutex lock/unlock is correctly paired for all write operations (no deadlocks or data races in multi-threaded scenarios)
5. Code compiles against both LinuxCNC 2.9.7+ and 2.10 APIs without breaking changes

**Plans:** 3 plans in 3 waves

Plans:
- [ ] 01-01-PLAN.md — Create build.zig, src/root.zig, src/ffi/c.zig (project scaffolding and C header imports)
- [ ] 01-02-PLAN.md — Create src/ffi/types.zig, src/ffi/errors.zig, src/ffi/safe.zig (types, errors, and init/exit wrappers)
- [ ] 01-03-PLAN.md — Pin wrapper functions with mutex locking and unit tests with leak detection

### Phase 2: State Management

**Goal**: Thread-safe central state store that caches HAL data and provides reactive updates to the TUI

**Depends on**: Phase 1

**Requirements**: STATE-01, STATE-02, STATE-03, STATE-04, STATE-05

**Success Criteria** (what must be TRUE):
1. State cache successfully stores current values of all HAL pins, signals, and parameters and refreshes at configured rate (default 100ms)
2. State manager handles dynamic HAL changes (components loading/unloading) without crashing or corrupting cache
3. Multiple threads can read state concurrently while refresh thread writes without race conditions or data corruption
4. TUI components receive state change notifications and can subscribe to specific items (e.g., "notify me when pid.0.P changes")
5. Application runs smoothly without blocking HAL refresh or causing real-time thread starvation

**Plans**: TBD

Plans:
- [ ] 02-01: TBD
- [ ] 02-02: TBD

### Phase 3: TUI Core

**Goal**: Vaxis-based terminal interface with two-panel layout (tree navigation + data table) for browsing and viewing HAL components in real-time

**Depends on**: Phase 2

**Requirements**: TUI-01, TUI-02, TUI-03, TUI-04, TUI-05, TUI-06, TUI-07, TUI-08, CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, CORE-09, CORE-10, CORE-12

**Success Criteria** (what must be TRUE):
1. TUI displays two-panel layout: left panel for tree navigation, right panel for data table view
2. Tree view (left panel) shows component hierarchy with collapse/expand navigation and checkboxes to select items for display
3. Data table view (right panel) displays selected items in tabular format with columns: Name, Type, Direction, Current Value
4. Values update in real-time in data table cells at configured refresh rate without lag or stutter
5. User can search tree for pins/signals/params by name with glob pattern matching (e.g., "*pid*" shows all PID-related items)
6. User can filter table view by pin type (show only float pins, show only s32, etc.) and by component ownership (show all pins for pid.0)
7. TUI renders correctly on Raspberry Pi 5 terminal at 80x24 minimum resolution (panels scale appropriately)
8. Data table uses color or icon indicators to visually distinguish editable items from read-only items (only writable parameters and OUT/I/O pins are editable)
9. Input validation prevents type errors (numeric fields only accept numbers, cannot type invalid input)
10. Boolean/bit pins: pressing Enter toggles value (True ↔ False) without opening edit dialog; cell shows unsaved color while waiting for HAL refresh
11. Numeric pins: pressing Enter enables in-place editing in data table cell with validation (only valid numeric input accepted, Enter confirms, Escape cancels); cell shows unsaved color during editing
12. After edit confirmation (Enter): clear cell immediately and wait for next HAL refresh to display actual value (confirms write succeeded, applies to both numeric and boolean)
13. TUI displays helpful error messages for non-input-related invalid operations (e.g., attempting to edit read-only items)

**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD
- [ ] 03-03: TBD

### Phase 4: Configuration & Editing

**Goal**: Runtime HAL manipulation (edit parameters, create signals, link pins) and configuration persistence

**Depends on**: Phase 3

**Requirements**: CORE-07, CORE-08, CORE-11

**Success Criteria** (what must be TRUE):
1. User can edit writable parameter values in data table and changes are immediately reflected in HAL (equivalent to halcmd setp); only visually marked editable items can be edited
2. User can create new signals and link pins to them (equivalent to halcmd net command)
3. User can save current HAL configuration to file in halcmd-compatible format (can be loaded later or used as backup)

**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

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
| 1. FFI Foundation | 0/3 | Planned, ready to execute | - |
| 2. State Management | 0/0 | Not started | - |
| 3. TUI Core | 0/0 | Not started | - |
| 4. Configuration & Editing | 0/0 | Not started | - |
| 5. Bookmarks & Plugins | 0/0 | Not started | - |
| 6. Polish & Optimization | 0/0 | Not started | - |
