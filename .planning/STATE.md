# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-05)

**Core value:** Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

**Current focus:** Milestone v0.5: View Switching UI

## Current Position

Phase: 05-view-switching of 6 (View Switching UI)
Plan: 02 of ?
Status: In progress
Last activity: 2026-02-06 — Completed 05-02-PLAN.md (Layout System View Mode Support)

Progress: [███░░░░░░░░] 20%

## Performance Metrics

**Velocity:**
- Total phases completed: 4 of 6 (v0.4)
- Total plans completed: 18
- Average duration: 9.5 min
- Total execution time: 2.8 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-ffi-foundation | 3 | 3 | 27.7 min |
| 02-state-management | 5 | 5 | 8.4 min |
| 03-tui-core | 5 | 5 | 6.0 min |
| 04-config-editing | 3 | 3 | 4.3 min |
| 05-view-switching | 2 | ? | 2.0 min |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

**From v0.4 (Complete):**
- All 4 phases (1-4) complete with 16 plans shipped
- FFI layer, state management, TUI core, and configuration editing all functional
- Known v1 limitations documented (pin link tracking, dialog visual polish, config restore)
- Tree view UX refined: tri-state visibility (none/partial/full), cursor indicator, hierarchical state propagation

**From Debug Session (2026-02-05):**
- Memory leaks fixed: changed TreeView.typeErasedDrawFn to use ctx.arena instead of self.allocator
- Event routing preserved: TreeView widget reference maintained when returning Surface
- Tree view format: `>component *` (root), `>  child *` (depth 1) with visibility symbols (`+`, ` *`)
- Backspace collapses current layer's children
- No reverse video styles - cursor indicator `>` sufficient

**From 05-01 (2026-02-06):**
- ViewMode enum: two variants (tree_only, table_only) with next() cycling pattern
- Silent event blocking: Ctrl-t ignored when dialogs open with no user feedback
- Model.current_view field: defaults to .tree_only for single-panel startup mode

**From 05-02 (2026-02-06):**
- Layout rendering: switch statement on current_view for conditional rendering
- Full-width single-panel layout: tree_only shows tree, table_only shows table
- Dynamic help text: shows "Ctrl+T=Table View" in tree mode, "Ctrl+T=Tree View" in table mode
- Widget state preserved across view switches (no reset)

### Pending Todos

None yet.

### Blockers/Concerns

**v0.5 Milestone In Progress:**
- View switching complete: tree and table render at full width in separate modes
- Ctrl-t cycles between tree_only and table_only views
- Help text dynamically shows next action
- Mode indicator may be needed in UI (not yet implemented)
- Each view uses full available width (implemented)

## Session Continuity

Last session: 2026-02-06 (phase 05-02: Layout System View Mode Support)
Stopped at: Completed 05-02-PLAN.md - Conditional layout rendering and dynamic help text
Resume file: None
Next action: Continue phase 05 or begin testing
