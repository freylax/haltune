# Phase 5: View Switching - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

## Phase Boundary

Transform the current two-panel layout into alternative view modes where tree view and data table are displayed separately, not simultaneously. Users switch between views using `Ctrl-t`. The underlying functionality (editing, search, visibility toggles, real-time updates) in both views must be preserved.

## Implementation Decisions

### Toggle behavior
- Key binding: `Ctrl-t` (changed from 't' to avoid conflicts with text input)
- Instant switch — no transition or animation
- Cycles both directions: tree ↔ table
- Blocked when dialog is open — silent ignore (no feedback message)
- No mode indicator needed — the visible content makes the current view obvious

### Layout handling
- Views are fluid — expand to fill available space
- When no right panel (plugins/.ini) is active, view uses entire width
- Plugin/layout arrangement for right panel is deferred to Phase 6
- Each view occupies whatever space is available

### State preservation
- Scroll position: Shared between views — maintain relative position
- Selection: Maintain cursor on same item (or nearest visible neighbor) when switching
- Visibility state: Source of truth — tree view's visibility controls table view filtering
  - Tree → Table: if focused item is invisible in table, move to nearest visible neighbor
  - Table → Tree: all table items exist in tree view
- Search: Persists across views as navigation aid
- Expand/collapse: Tree view state is per-view (table has no expand/collapse)

### Claude's Discretion
- Exact mechanism for finding "nearest visible neighbor" when switching from invisible item
- How scroll position is mapped between views with different content densities
- Transition handling for edge cases (empty views, single item, etc.)

## Specific Ideas

- User recognized search as a navigation tool that should persist across views
- `Ctrl-t` chosen to avoid conflicts with typing/text input scenarios

## Deferred Ideas

- Plugin layout arrangement — Phase 6 (Bookmarks & Plugins)
- Right panel behavior when view switching occurs — deferred until plugin architecture exists

---

*Phase: 05-view-switching*
*Context gathered: 2026-02-05*
