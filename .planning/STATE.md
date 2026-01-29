# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2025-01-28)

**Core value:** Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

**Current focus:** Phase 2: State Management

## Current Position

Phase: 2 of 6 (State Management)
Plan: 1 of 3 in current phase
Status: In progress
Last activity: 2026-01-29 — Completed 02-01-PLAN.md (State Cache)

Progress: [███░░░░░░] 33%

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: 23.5 min
- Total execution time: 1.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-ffi-foundation | 3 | 3 | 27.7 min |
| 02-state-management | 1 | 3 | 6.0 min |

**Recent Trend:**
- Last 5 plans: 23.5 min avg (01-01: 8.2min, 01-02: 66min, 01-03: 6min, 02-01: 6min)
- Trend: 02-01 was quick - state cache built directly on FFI foundation

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

## Session Continuity

Last session: 2026-01-29 (02-01 execution)
Stopped at: Completed 02-01-PLAN.md (State Cache)
Resume file: None
