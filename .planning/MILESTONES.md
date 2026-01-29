# Project Milestones: haltune

## v0.4 Configuration & Editing (Shipped: 2026-01-29)

**Delivered:** Runtime HAL manipulation capabilities including signal creation, pin linking, and configuration export in halcmd-compatible format.

**Phases completed:** 4 (3 plans total)

**Key accomplishments:**

- Implemented HAL signal FFI wrappers (halSignalNew, halLink, halUnlink) with mutex locking and specific error types
- Built complete 4-step SignalDialog wizard (name → type → pins → confirm) with type-safe pin filtering
- Created configuration export module with halcmd-compatible format (net/setp commands) and 's' key binding
- Added pin link tracking infrastructure in StateStore (full population deferred as v1 limitation)
- Established memory-safe dialog lifecycle patterns and error handling

**Stats:**

- ~9 files created/modified
- ~5,009 lines of Zig
- 1 phase, 3 plans, 21 tasks
- <1 hour from start to ship

**Git range:** `feat(04-01)` → `feat(04-03)`

**Known v1 limitations:**
- Pin link tracking not fully populated (ULAPI signal pointer iteration complex for v1)
- Save dialog visual rendering is placeholder (functionality complete, UI deferred)

**What's next:** Phase 5: Bookmarks & Plugins

---
