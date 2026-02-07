# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-05)

**Core value:** Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

**Current focus:** Milestone v0.6: Live Values & Editing

## Current Position

Phase: 06-live-values (Live Values & Editing)
Plan: 05 of 5
Status: Phase complete
Last activity: 2026-02-07 — Completed 06-05 (Table View Value Display)

Progress: [██████████░] 56%

## Performance Metrics

**Velocity:**
- Total phases completed: 5 of 8 (v0.5)
- Total plans completed: 25
- Average duration: 7.8 min
- Total execution time: 3.3 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-ffi-foundation | 3 | 3 | 27.7 min |
| 02-state-management | 5 | 5 | 8.4 min |
| 03-tui-core | 5 | 5 | 6.0 min |
| 04-config-editing | 3 | 3 | 4.3 min |
| 05-view-switching | 2 | 2 | 2.0 min |
| 06-live-values | 5 | 5 | 2.8 min |

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

**From 06-01 (2026-02-07):**
- Live value display in tree view: formatHalValue function with type-specific formatting (●/○ for BIT, decimal for numeric)
- UTF-8 escape sequences in source: \xe2\x97\x8f/\xe2\x97\x8b instead of literal ●/○ to avoid encoding issues
- BIT values as circle symbols (● for TRUE, ○ for FALSE) instead of 1/0 for better visual scanning
- FLOAT with 6 decimal precision balances detail vs space
- Value column: 8 characters (1 space + 8 char value) right-aligned for standard numeric display
- Unicode rendering: graphemeIterator and ctx.stringWidth required by Vaxis for multi-byte characters
- Real-time updates via existing pubsub infrastructure (valueChangedCallback → redraw_flag → ctx.consumeAndRedraw)

**From 06-02 (2026-02-07):**
- In-place value editing in tree view: Enter on BIT toggles, Enter on numeric enters edit mode
- Edit mode state: edit_mode flag, edit_item pointer, edit_buffer ArrayList
- Writability checks: pins connected to signals are not editable (checked via pin_links HashMap)
- Type-specific input validation: FLOAT allows digits/minus/decimal, S32 allows digits/minus, U32 allows digits only
- Edit mode event handlers: Escape cancels, Enter confirms with parsing, Backspace deletes, typing validated
- Visual feedback: edited cell shown with reverse style highlight
- Edit mode reset on tree rebuild (node pointers invalidated)
- Store update methods called: updatePin/updateSignal/updateParam

**From 06-03 (2026-02-07):**
- Ctrl+S for signal editing: 'S' for Signal, distinct from Enter for value editing
- Separate edit mode for signal connection (signal_edit_mode) distinct from value editing (edit_mode)
- Type inference from pin value when creating signals prevents HAL type mismatch errors
- Pre-populate signal name buffer with current signal for easy disconnection/modification
- Signal name validation: alphanumeric + underscore + dash only (C identifier conventions)
- Silent ignore for Ctrl+S on non-pins (no error message, TreeView lacks status line access)
- Error logging to stderr instead of status messages (no Model.setError access in TreeView)

**From 06-04 (2026-02-07):**
- Signal deletion prompt when disconnecting last pin: checks countPinsForSignal == 0 before prompting
- Prompt mode blocks all input except 'y' (confirm), 'n' (cancel), or Escape (cancel)
- Owned memory pattern for prompt state: pending_signal_delete requires explicit free in deinit and on tree rebuild
- halSignalDelete FFI wrapper removes signals from HAL (unlinks all pins first)
- Messages logged to stderr: prompt shows "Delete orphaned signal 'X'? (y/n)", cancel shows "Signal 'X' left orphaned"
- Shows "X pins remain" message when disconnecting from signal with 2+ pins (no prompt)

**From 06-05 (2026-02-07):**
- Table view value display: formatHalValue function matches tree view (●/○ for BIT, 6-decimal for FLOAT)
- Right-aligned value column: uses ctx.stringWidth for Unicode width calculation, right-aligns in 30% width column
- Unicode rendering: graphemeIterator for proper multi-byte UTF-8 character rendering (●/○ are 3-byte sequences)
- Table view already had Value column; updated formatting to match tree view consistency
- Float precision increased from 2 to 6 decimal places for better detail
- Real-time updates work via existing pubsub infrastructure (no changes needed)
- Table view editing not yet implemented: users must switch to tree view (Ctrl+T) to edit values

### Pending Todos

None yet.

### Blockers/Concerns

**v0.6 Milestone Complete:**
- Phase 05 complete: view switching (tree ↔ table) with Ctrl-t
- Phase 06 complete: live values in tree and table views, inline value editing in tree view, signal CRUD with deletion prompt
- Table view editing not yet implemented (deferred to future phase)
- Known limitation: Users can view values in table mode but must switch to tree view (Ctrl+T) to edit

## Session Continuity

Last session: 2026-02-07 (phase 06-05: Table View Value Display)
Stopped at: Completed 06-05-PLAN.md - table view value display with right-aligned formatting
Resume file: None
Next action: Begin phase 07 or implement table view editing enhancement
