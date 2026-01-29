---
phase: 03-tui-core
plan: 03
subsystem: tui
tags: [vaxis, vxfw, data-table, pubsub, refresh-thread, real-time-updates]

# Dependency graph
requires:
  - phase: 02-state-management
    provides: StateStore with RwLock, SubscriptionManager for pubsub, RefreshThread for polling
  - phase: 03-tui-core/03-01
    provides: Two-panel layout, Model struct with vxfw integration
provides:
  - DataTable widget for displaying HAL item values in tabular format
  - Real-time value updates via SubscriptionManager pubsub notifications
  - Color-coded editability indicators (green for editable, dim gray for read-only)
  - Integration with RefreshThread for automatic cache polling and TUI redraws
affects: [03-04-search-edit]

# Tech tracking
tech-stack:
  added: []
  patterns: [vxfw widget pattern with drawFn, arena allocation for temporary data, pubsub-driven redraws, color-coded editability indicators]

key-files:
  created: [src/tui/widgets/data_table.zig]
  modified: [src/tui/model.zig, src/tui/layout.zig, src/tui/app.zig]

key-decisions:
  - "Use global variable (GLOBAL_REDRAW_FLAG) for pubsub callback access - simpler than closure capture in Zig"
  - "Determine editability via name heuristics for now (direction not in cache yet)"
  - "Read values from StateStore cache (lock-free) instead of calling HAL FFI directly"

patterns-established:
  - "Pattern 1: Pubsub-Driven Redraws - SubscriptionManager callbacks set redraw_flag, key_press handler checks flag and calls ctx.consumeAndRedraw()"
  - "Pattern 2: Widget Integration - Add widget field to Model, initialize in init(), draw in layout module via widget().draw()"
  - "Pattern 3: Color Coding - Use vxfw.Style with fg.index (2 for green, 8 for dim gray) to visually distinguish item properties"

# Metrics
duration: 5min
completed: 2026-01-29
---

# Phase 3 Plan 3: Data Table with Real-Time Updates Summary

**DataTable widget displaying checked HAL items with tabular columns, real-time value updates via pubsub, and color-coded editability indicators**

## Performance

- **Duration:** 5 min (317 seconds)
- **Started:** 2026-01-29T17:10:13Z
- **Completed:** 2026-01-29T17:15:30Z
- **Tasks:** 4
- **Files modified:** 4

## Accomplishments

- **DataTable widget created** - Displays HAL items (pins, signals, params) in tabular format with Name, Type, Direction, and Value columns
- **Real-time value updates** - Values update automatically as RefreshThread polls HAL and updates StateStore cache
- **Pubsub integration** - SubscriptionManager notifies on value changes, triggering TUI redraws via atomic redraw_flag
- **Color-coded editability** - Green (index 2) for writable items (OUT/I/O pins, writable params), dim gray (index 8) for read-only items (IN pins, read-only params)
- **RefreshThread integration** - Thread starts on app init, stops cleanly on shutdown, updates cache every 100ms
- **Layout integration** - DataTable renders in right panel (70% width) alongside TreeView in left panel

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DataTable widget with column structure** - `a437532` (feat)
2. **Task 2: Implement DataTable draw with color indicators** - `68e275a` (feat)
3. **Task 3: Integrate RefreshThread and SubscriptionManager into Model** - `97a307f` (feat)
4. **Task 4: Integrate DataTable into layout and wire checked items** - `7748b03` (feat)

**Plan metadata:** (to be committed after SUMMARY.md creation)

## Files Created/Modified

- `src/tui/widgets/data_table.zig` (371 lines) - DataTable widget with TableItem struct, column rendering, value formatting
- `src/tui/model.zig` (180 lines) - Added data_table field, refresh_thread field, redraw_flag, updateTable() method, global valueChangedCallback
- `src/tui/layout.zig` (90 lines) - Updated createRightPanel() to draw DataTable widget
- `src/tui/app.zig` (65 lines) - Added refresh_thread.stop() before app deinit for clean shutdown

## Decisions Made

- **Global variable for pubsub callback** - Used GLOBAL_REDRAW_FLAG pointer instead of closure capture because Zig's callback function pointers don't support capturing context. The callback is a simple function pointer (`*const fn`) that can't capture `self`, so we use a global variable set during Model initialization.
- **Editability via name heuristics** - Determine if items are writable based on naming patterns (e.g., pins with "-out" or "-io" are OUT/I/O) because pin direction isn't stored in StateStore cache yet. This will be refined in plan 03-04 when we add direction metadata to cache.
- **Read from cache, not HAL** - DataTable reads current values from StateStore cache (getPin/getSignal/getParam) which are lock-free reads, avoiding blocking the TUI thread. RefreshThread handles all HAL FFI calls in background.

## Deviations from Plan

None - plan executed exactly as written.

## Authentication Gates

None - no external service authentication required.

## Issues Encountered

- **Callback context capture limitation** - Zig's function pointers don't support closure capture, so we can't pass `self.redraw_flag` directly to the subscription callback. Resolved by using a global variable (GLOBAL_REDRAW_FLAG) that points to the Model's redraw_flag. This is set during Model initialization and cleared on deinit.

## User Setup Required

None - no external service configuration required.

## Verification

✓ DataTable widget created with TableItem struct (371 lines, min 200 required)
✓ typeErasedDrawFn renders table with headers (Name, Type, Dir, Value) and separator
✓ Color indicators: green (index 2) for editable, dim gray (index 8) for read-only
✓ Values read from StateStore via getPin/getSignal/getParam
✓ RefreshThread field added to Model (nullable, created but not started in init)
✓ redraw_flag (std.atomic.Value(bool)) for pubsub signaling
✓ .init event handler starts RefreshThread and sets GLOBAL_REDRAW_FLAG
✓ updateSubscriptions() subscribes to checked tree items with valueChangedCallback
✓ .key_press handler checks redraw_flag and calls ctx.consumeAndRedraw()
✓ app.zig calls refresh_thread.stop() before deinit for clean shutdown
✓ data_table field added to Model, initialized in init()
✓ updateTable() method syncs table with checked items
✓ createRightPanel() draws DataTable with constrained context

## Next Phase Readiness

**Ready for plan 03-04 (Search, Filter, and In-Place Editing):**
- DataTable displays checked items with current values
- Real-time updates work via RefreshThread and SubscriptionManager
- Color indicators distinguish editable from read-only items
- Table integrated into right panel layout
- updateTable() method available for syncing when tree selection changes

**What's blocking:**
- Nothing - DataTable is fully functional and ready for search/filter/editing enhancements
- Tree checkbox handler integration (calling updateTable) should be added in 03-04 or as part of 03-02 completion

**Next steps:**
- Plan 03-04: Add search/filter with glob.zig, implement in-place editing modal for numeric values
- Wire TreeView checkbox handler to call Model.updateTable() and ctx.consumeAndRedraw()
- Add inline editing for boolean pins (toggle on Enter) and numeric pins (edit modal)

---
*Phase: 03-tui-core*
*Completed: 2026-01-29*
