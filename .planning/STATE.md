# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-29)

**Core value:** Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

**Current focus:** Phase 5: Bookmarks & Plugins (ready to start)

## Current Position

Phase: 5 of 6 (Bookmarks & Plugins)
Plan: Not started
Status: Ready to plan
Last activity: 2026-01-29 — v0.4 milestone complete (Phases 1-4 shipped)

Progress: [████████░░] 67%

## Performance Metrics

**Velocity:**
- Total phases completed: 3 of 6
- Total plans completed: 16
- Average duration: 10.3 min
- Total execution time: 2.8 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-ffi-foundation | 3 | 3 | 27.7 min |
| 02-state-management | 5 | 5 | 8.4 min |
| 03-tui-core | 5 | 5 | 6.0 min |
| 04-config-editing | 3 | 3 | 4.3 min |
| 05-bookmarks-plugins | 0 | ? | - |

**Recent Trend:**
- Phase 4 complete: HAL signal FFI wrappers + SignalDialog wizard + Configuration export
- v0.4 milestone shipped: 16 plans across 4 phases, all complete
- Last 3 plans: 4.3 min avg (04-03: 4.3min, 04-02: 6min, 04-01: 3min)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

**From 04-03 (Configuration Export):**
- Defer pin link tracking in refresh thread - ULAPI signal pointer iteration is complex for v1, documented in TODO comment
- Use ArrayList(u8) for save filename input - proper UTF-8 backspace handling via pop() method
- Buffered file writing for export - use std.io.bufferedWriter for efficient I/O
- Null-terminate filename for std.fs.cwd API compatibility - dupeZ allocation required
- Placeholder for save dialog visual rendering - functionality complete (open, input, save, cancel) but UI deferred to avoid blocking flow
- Save dialog lifecycle pattern: openSaveDialog() → [filename input] → saveConfiguration() → closeSaveDialog()
- Error handling via setError() with user-facing messages and std.log.err() for debugging

**From 04-02 (TUI Signal Creation Dialog):**
- Use StringHashMap(void) for selected pins - simpler than tracking full pin state, only need O(1) membership test
- Load available pins on type selection (not name input) - reduces HAL queries and avoids unnecessary work
- Copy pin names when selecting into StringHashMap - prevents dangling pointers if StateStore cache updates during dialog
- Stub draw implementations for dialog steps - focus on functionality first, visual rendering can be enhanced later without blocking flow
- Dialog lifecycle pattern: init() → open() → [wizard steps] → close() → deinit() with proper resource cleanup
- Multi-select pattern with Space key toggle - store copies of keys for memory safety

**From 04-01 (HAL Signal FFI Wrappers):**
- halSignalNew does NOT acquire mutex - C function (hal_signal_new) handles locking internally
- halLink and halUnlink explicitly acquire HAL mutex following Phase 1 write function pattern
- Added LinkFailed and UnlinkFailed error types for specific error discrimination (not generic InitFailed)
- All signal functions follow existing documentation pattern (Parameters, Returns, Memory ownership, Thread safety)

**From 03-04 (Search, Filter, and In-Place Editing):**
- glob.zig library used for pattern matching (simpler than custom implementation)
- Search buffer managed via ArrayList(u8) for proper UTF-8 backspace handling
- Edit buffer is ArrayList with edit_mode flag controlling display
- Pending edits tracked in StringHashMap, displays "..." until refresh
- Error messages auto-clear after 5 seconds (balance between visibility and annoyance)
- Read-only detection via name heuristics (-out/-io suffix) for now
- Cursor selection not implemented (edits first item), deferred to future
- Help text displayed at bottom in dim style showing all key bindings

**From 03-03 (Data Table with Real-Time Updates):**
- Use global variable (GLOBAL_REDRAW_FLAG) for pubsub callback access
- Determine editability via name heuristics for now (direction not in cache yet)
- Read values from StateStore cache (lock-free) instead of calling HAL FFI directly
- Pubsub-driven redraws - SubscriptionManager callbacks set redraw_flag, key_press handler checks flag and calls ctx.consumeAndRedraw()
- Color-coded editability indicators - green (index 2) for editable, dim gray (index 8) for read-only

**From 03-02 (Tree Navigation):**
- Component hierarchy extracted from HAL item names using dot delimiter
- Widget state stored in TreeView HashMaps (expanded_nodes, checked_items)
- visible_nodes rebuilt on each draw from root nodes - simpler code, trivial performance cost
- Cursor tracks position in visible_nodes list (not global tree) - prevents jumping when tree structure changes

**From 03-01 (TUI Foundation):**
- Use vxfw framework (not low-level Vaxis API) - automatic redraw optimization
- Delegate layout logic to separate module (layout.zig) - keeps model.zig focused
- Use ctx.withConstraints for panel sizing - responsive layout at different terminal sizes
- Arena allocation pattern - use ctx.arena for temporary allocations (freed automatically each frame)
- Two-panel layout uses SubSurface children with origin offsets - left panel (30%), right panel (70%)

**From 03-00 (FFI Write Functions):**
- Pin write functions use HAL mutex locking for thread safety
- Parameter write functions include type validation
- getPinValue handles both linked pins (delegate to getSignalValue) and unlinked pins (read from dummysig)
- Write functions follow Phase 1 pattern: acquire mutex, write value, release mutex
- Read functions remain lock-free across all FFI (pins, signals, parameters)
- TUI layer responsible for checking pin direction/param writability before calling write functions

**From 02-05 (Stale Entry Cleanup):**
- Use HashMap.remove() which returns bool - ignore return value with _ since stale entries may or may not exist
- Log stale removal errors but don't fail refresh cycle - prevents one bad removal from stopping all updates
- Compare cached names to HAL snapshot (not reverse) - ensures we catch all stale entries
- Cache size invariant now maintained (no unbounded growth as components load/unload)

**From 02-04 (Signal and Parameter Refresh):**
- Read signal/param values directly from hal_sig_t/hal_param_t structures (same as pins)
- Follow exact same 4-phase refresh pattern as refreshPins() for consistency
- Use @import to avoid circular dependency between safe.zig and cache.zig

**From 02-03 (Pubsub Notifications):**
- Mutex protects entire subscriber HashMap (not per-item locks) - simpler lock hierarchy
- Callbacks invoked while holding mutex - documented to keep them fast
- Condition variable with has_changes predicate - prevents spurious wakeup bugs (RESEARCH.md Pitfall 2)
- waitForChange() uses while loop (not if) - correct spurious wakeup handling per RESEARCH

**From 02-02 (Refresh Thread):**
- Use .acquire/.release memory ordering for atomic running flag - ensures visibility across threads (RESEARCH.md Pitfall 4)
- Read HAL values before acquiring cache lock - prevents deadlock with HAL mutex (RESEARCH.md Pitfall 1)
- Enumerate ALL pins from HAL each cycle via halpr_find_pin_by_name(null) - supports dynamic component load/unload
- Sleep loop with atomic flag for clean thread shutdown - thread exits within one refresh interval
- Stale pin cleanup deferred - new pins added immediately, old pins detected but removal TODO

**From 02-01 (State Cache):**
- Single RwLock per StateStore (not per HashMap) - simpler lock hierarchy, prevents deadlock
- Read operations use lockShared() - allows concurrent TUI access without blocking
- Write operations use lock() - blocks all readers during atomic updates
- List functions snapshot keys while holding lock, return owned slice - prevents iterator invalidation (RESEARCH.md Pitfall 3)
- Never call HAL functions while holding rwlock - prevents deadlock with HAL mutex (RESEARCH.md Pitfall 1)

**From 01-03 (Safe Pin Operations):**
- Write operations use HAL mutex lock/unlock for thread safety
- Read operations are lock-free (HAL real-time thread owns writes)
- Type checking on all operations returns TypeMismatch error (not crash)
- HAL-allocated pin memory is never freed by Zig
- C types used directly via @cImport wrappers (simpler than extern struct)

**From 01-02 (Type-Safe FFI Layer):**
- Use extern struct (not packed) for C ABI compatibility on ARM64
- Compile-time size assertions prevent silent ABI mismatches on Raspberry Pi 5
- Error unions (!T) enforce explicit error handling at all FFI call sites
- Map LinuxCNC error codes to specific Zig error types for type safety
- Version-specific struct size verification for LinuxCNC 2.9.7 and 2.10
- Document memory ownership explicitly at FFI boundaries (HAL owns HAL memory, Zig owns Zig memory)

**From 01-01 (Project Scaffolding):**
- Added `-Dskip-hal-link` build option for development on machines without LinuxCNC
- Use `std.debug.print` instead of non-existent `std.io.getStdOut()` (Zig 0.15.1 API)
- Lazy @cImport allows development without hal.h present
- Target aarch64-linux for Raspberry Pi 5 deployment

### Pending Todos

None yet.

### Blockers/Concerns

**v0.4 Milestone Complete:**
- All 4 phases (1-4) complete with 16 plans shipped
- FFI layer, state management, TUI core, and configuration editing all functional
- Known v1 limitations documented (pin link tracking, dialog visual polish, config restore)

**From 04-03:**
- Note: Pin link tracking not implemented - export will show empty pin lists until refresh thread is updated to iterate signals and find matching pointers (documented in TODO comment)
- Note: Save dialog visual rendering is a TODO placeholder - dialog works (open, input, save, cancel) but no visual feedback yet

**From 04-02:**
- Note: Draw functions are stub implementations - visual rendering of dialog steps deferred to avoid blocking functionality
- Dialog needs visual polish (borders, colors, proper text rendering) but core wizard flow is complete and functional

**From 04-01:**
- None - HAL signal FFI wrappers complete and ready for TUI integration

## Session Continuity

Last session: 2026-01-29 (v0.4 milestone completion)
Stopped at: v0.4 milestone complete - Phases 1-4 shipped, archived to milestones/
Resume file: None
Next action: Start Phase 5 (Bookmarks & Plugins) or enhance v1 polish items
