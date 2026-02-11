# Refresh Thread Initialization - Critical Timing Issue

## Problem

The tree view showed 0 or partial components at startup because:

1. `Model.init()` calls `buildTree()` BEFORE the refresh thread starts
2. Tree is built with empty StateStore → 0 components
3. Refresh thread starts in background and populates StateStore
4. `rebuildTreeIfNeeded()` rebuilds tree when data is available
5. **BUT** vaxis doesn't call the draw function until there's USER INPUT
6. User sees empty tree until they press a key (like Ctrl+T)

## Solution

**File: `src/tui/app.zig`**

After starting the refresh thread, add a delay BEFORE starting the TUI:

```zig
// Create and start RefreshThread for HAL polling AFTER vaxis is ready
const refresh_thread = try thread_safe_allocator.create(RefreshThread);
refresh_thread.* = RefreshThread.init(thread_safe_allocator, &store);
refresh_thread.setRedrawFlag(&model.redraw_flag);
_ = try refresh_thread.start();

// Give refresh thread time to populate StateStore before first draw
// This ensures the tree is built with actual data, not empty
std.log.info("Waiting for refresh thread to populate StateStore...", .{});
std.Thread.sleep(200 * std.time.ns_per_ms); // 200ms delay
std.log.info("Refresh thread started, continuing to TUI", .{});

// Then continue with app.run()...
```

The 200ms delay gives the refresh thread enough time to:
1. Complete at least one refresh cycle
2. Call `halcmd list pin/signal/param` to discover all HAL items
3. Populate StateStore with pins, signals, and params
4. Set the `populated` flag

When the TUI then starts and `buildTree()` is called, StateStore already has data!

## Key Files

- `src/tui/app.zig` - Main entry point, delay added here
- `src/state/refresh.zig` - Refresh thread that populates StateStore
- `src/tui/widgets/tree_view.zig` - `rebuildTreeIfNeeded()` called from `typeErasedDrawFn()`
- `src/tui/model.zig` - Model initialization

## Why redraw_flag alone doesn't work

The refresh thread sets `redraw_flag` when StateStore is populated, but vaxis
only calls the event handler when there's user input (key press, mouse event, etc.).
Without user input, the draw function never runs, so the tree never rebuilds.

The delay ensures StateStore is populated BEFORE the first draw, so the initial
tree build has all the components.

## Testing

To verify this works:
1. Start haltune
2. Tree should immediately show all 4 components (trapvel, pid, servo-thread, rio)
3. No need to press Ctrl+T or any other key

## History

- Fixed on 2026-02-09 after multiple attempts
- Previous attempts with tick handlers, redraw flags, and various conditions failed
- The simple 200ms delay after starting refresh thread was the solution
- This is commit f0a83ad "fix: add delay after starting refresh thread..."
