# Phase 3: TUI Core - Context

**Gathered:** 2026-01-29
**Status:** Ready for planning

## Phase Boundary

Vaxis-based terminal interface with two-panel layout (tree navigation + data table) for browsing and viewing HAL components in real-time. Users can view component hierarchies, monitor pin/signal/parameter values, and see updates as HAL changes. Editing and configuration are separate phases.

## Implementation Decisions

### Layout proportions
- Responsive panel sizing with manual adjustment (both mouse drag and keyboard shortcuts)
- Auto-hiding scrollbars (appear only when content overflows)
- No fixed minimum widths - scrolling activates when actual data needs it
- Both tree and table are interchangeable views - user can use either or both depending on situation

### Tree navigation
- Space toggles visibility in data table: marked component + all children become visible/hidden
- Children can individually override parent's visibility state
- Arrow keys (up, down, left, right) navigate the tree
- Return/Enter toggles collapse/expand state
- No checkboxes - use rich text icons to visualize state
- Icons for visibility: open eye (fully visible), closed eye (partially visible), no icon (hidden)
- Only leaf nodes (children) appear in data table; parent visibility is aggregate of children
- Additional icons in tree view:
  - Flash icon for signal-connected pins
  - Left arrow for input pins
  - Right arrow for output pins
  - Type indicators for float/uint/sint/bool
- Tree shows: type, value, and signal connection status
- Tree graphic lines use minimal indentation (not full-width spaces) to save room for data

### Table density
- Same icon system as tree view (without visibility markers)
- Direction indicators are important (shows editability - only input/not-connected pins are editable)
- Pin path (name) column uses context-aware abbreviation:
  - If consecutive rows share common path prefix, use left brace grouping to show shared root
  - Split path across rows visually with mathematical grouping notation
  - ~ marker indicates abbreviation
  - When row is active/selected, full name displays in status line
- Signals are rightmost column (may require scrolling or show in statusbar)
- Columns: Name (with icons), Type, Direction, Value, Signal

### Real-time updates
- Throttled update rate at 5 fps (200ms intervals) to prevent flicker while feeling responsive
- Changed values update in-place at throttled rate
- No flicker indicators needed (throttling handles this)

### Claude's Discretion
- Exact brace rendering style for path grouping
- Status line layout and information density
- Keyboard shortcut specifics for panel resizing
- Icon choices that maintain terminal compatibility

## Specific Ideas

- Tree and table are "alternatively usable" - not tree-controls-table, but two views of same data that user can switch between
- Path grouping should visually convey hierarchy like mathematical notation (big left brace)
- 5 fps update rate prioritizes readability over instant feedback

## Deferred Ideas

- Value editing (will be addressed in Phase 4: Configuration & Editing)
- Bookmarking frequently-viewed items (Phase 5)

---

*Phase: 03-tui-core*
*Context gathered: 2026-01-29*
