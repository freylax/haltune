# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2025-01-28)

**Core value:** Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

**Current focus:** Phase 2: State Management

## Current Position

Phase: 2 of 6 (State Management)
Plan: 4 of 5 in current phase
Status: In progress
Last activity: 2026-01-29 — Completed 02-04-PLAN.md (Signal and Parameter Refresh)

Progress: [██████░░░] 80%

## Performance Metrics

**Velocity:**
- Total plans completed: 8
- Average duration: 17.9 min
- Total execution time: 2.4 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-ffi-foundation | 3 | 3 | 27.7 min |
| 02-state-management | 5 | 5 | 8.4 min |

**Recent Trend:**
- Last 5 plans: 17.9 min avg (02-01: 6min, 02-02: 19min, 02-03: 4min, 02-04: 6min)
- Trend: State management plans completing quickly on solid FFI foundation

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

**From 01-01 (Project Scaffolding):**
- Added `-Dskip-hal-link` build option for development on machines without LinuxCNC
- Use `std.debug.print` instead of non-existent `std.io.getStdOut()` (Zig 0.15.1 API)
- Lazy @cImport allows development without hal.h present
- Target aarch64-linux for Raspberry Pi 5 deployment

**From 01-02 (Type-Safe FFI Layer):**
- Use extern struct (not packed) for C ABI compatibility on ARM64
- Compile-time size assertions prevent silent ABI mismatches on Raspberry Pi 5
- Error unions (!T) enforce explicit error handling at all FFI call sites
- Map LinuxCNC error codes to specific Zig error types for type safety
- Version-specific struct size verification for LinuxCNC 2.9.7 and 2.10
- Document memory ownership explicitly at FFI boundaries (HAL owns HAL memory, Zig owns Zig memory)

**From 01-03 (Safe Pin Operations):**
- Write operations use HAL mutex lock/unlock for thread safety
- Read operations are lock-free (HAL real-time thread owns writes)
- Type checking on all operations returns TypeMismatch error (not crash)
- HAL-allocated pin memory is never freed by Zig
- C types used directly via @cImport wrappers (simpler than extern struct)

**From 02-01 (State Cache):**
- Single RwLock per StateStore (not per HashMap) - simpler lock hierarchy, prevents deadlock
- Read operations use lockShared() - allows concurrent TUI access without blocking
- Write operations use lock() - blocks all readers during atomic updates
- List functions snapshot keys while holding lock, return owned slice - prevents iterator invalidation (RESEARCH.md Pitfall 3)
- Never call HAL functions while holding rwlock - prevents deadlock with HAL mutex (RESEARCH.md Pitfall 1)

**From 02-02 (Refresh Thread):**
- Use .acquire/.release memory ordering for atomic running flag - ensures visibility across threads (RESEARCH.md Pitfall 4)
- Read HAL values before acquiring cache lock - prevents deadlock with HAL mutex (RESEARCH.md Pitfall 1)
- Enumerate ALL pins from HAL each cycle via halpr_find_pin_by_name(null) - supports dynamic component load/unload
- Sleep loop with atomic flag for clean thread shutdown - thread exits within one refresh interval
- Stale pin cleanup deferred - new pins added immediately, old pins detected but removal TODO

**From 02-03 (Pubsub Notifications):**
- Mutex protects entire subscriber HashMap (not per-item locks) - simpler lock hierarchy prevents deadlock
- Callbacks invoked while holding mutex - documented to keep them fast to avoid blocking notifications
- Condition variable with has_changes predicate - prevents spurious wakeup bugs (RESEARCH.md Pitfall 2)
- waitForChange() uses while loop (not if) - correct spurious wakeup handling per RESEARCH.md
- Unsubscribe removes empty lists from HashMap - prevents memory bloat from zombie items

**From 02-04 (Signal and Parameter Refresh):**
- Read signal/param values directly from hal_sig_t/hal_param_t structures (same as pins)
- Follow exact same 4-phase refresh pattern as refreshPins() for consistency (discovery, snapshot, comparison, update)
- Use @import to avoid circular dependency between safe.zig and cache.zig
- All HAL data types (pins, signals, params) now refreshed at configured interval

### Pending Todos

None yet.

### Blockers/Concerns

**From 01-01:**
- None - build infrastructure is solid and ready for next phase

**From 01-02:**
- None - type-safe FFI foundation is complete and ready for pin/signal operations

**From 01-03:**
- None - pin operations complete with thread-safe mutex locking and leak-free tests

**From 02-01:**
- None - state cache complete with thread-safe RwLock and HashMap snapshot pattern
- Ready for refresh thread (02-02) to poll HAL and update cache

**From 02-02:**
- None - refresh thread complete with HAL discovery and atomic lifecycle management
- Stale pin removal deferred to future task (not blocking)
- Unit tests written but not yet runnable due to missing HAL library in dev environment

**From 02-03:**
- None - pubsub notification system complete with thread-safe subscriber management
- Ready for integration with StateStore to call notify() on value changes
- Unit tests written but not yet runnable due to missing HAL library in dev environment

**From 02-04:**
- None - signal and parameter refresh complete with full HAL enumeration
- STATE-02 requirement fully satisfied: all HAL data types refreshed at configured interval
- Ready for next phase (02-05: stale entry removal or 03-01: UI foundation)
- Unit tests written but not yet runnable due to missing HAL library in dev environment

## Session Continuity

Last session: 2026-01-29 (02-04 execution)
Stopped at: Completed 02-04-PLAN.md (Signal and Parameter Refresh)
Resume file: None
