# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-05)

**Core value:** Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

**Current focus:** Milestone v0.5: View Switching UI

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-02-05 — Milestone v0.5 started

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total phases completed: 4 of 6 (v0.4)
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
| 05-view-switching | 0 | ? | - |

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

### Pending Todos

None yet.

### Blockers/Concerns

**v0.5 Milestone Starting:**
- Design change: Switch from simultaneous two-panel layout to alternative view modes
- Tree view and data table displayed separately, not together
- 't' key binding to switch between modes
- Mode indicator needed in UI
- Each view should use full available width

## Session Continuity

Last session: 2026-02-05 (debug session: memory leaks, UI refinements, tri-state visibility)
Stopped at: v0.5 milestone initialization - view switching design proposed by user
Resume file: None
Next action: Define requirements for view switching milestone
