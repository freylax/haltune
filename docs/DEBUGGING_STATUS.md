# Haltune Debugging Status

## Current State (2025-02-03)

### What's Working ✅
- Tree building is successful (2 components: `test` and `motion`)
- Test pins are added to StateStore in Model.init()
- Tree displays in left panel with component names
- TUI starts and displays (no immediate crash)
- **Memory management FIXED** - All issues resolved:
  - Double-free fixed (name/full_name pointer comparison)
  - HashMap key leaks fixed (free keys in defer block)
- Clean shutdown without memory errors or leaks
- Terminal size validation prevents division by zero

### What's NOT Working ❌
- **Navigation untested** - Need to verify arrow keys/Enter work on proper TTY
- ENXIO errors when running without proper TTY (expected behavior)

## RESOLVED ISSUES ✅

### Double-Free (FIXED 2025-02-03)

**Root Cause 1:** `buildTree()` was being called twice - fixed by removing call from `TreeView.init()`.

**Root Cause 2:** Component nodes had `name` and `full_name` pointing to the same memory, but `freeNode()` freed both.

**Fix:** Added pointer comparison in `freeNode()`:
```zig
self.allocator.free(node.name);
// Only free full_name if it's a different allocation
if (node.full_name.ptr != node.name.ptr) {
    self.allocator.free(node.full_name);
}
```

**Commit:** c269bad + follow-up

### Memory Leak (FIXED 2025-02-03)

**Root Cause:** `StringHashMap` doesn't automatically free key memory. The `component_map` stored keys allocated by `extractComponentName()`, but the defer block only freed values.

**Fix:** Added `self.allocator.free(entry.key_ptr.*)` to the defer block:
```zig
defer {
    var iter = component_map.iterator();
    while (iter.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);  // Free the key
        entry.value_ptr.*.deinit();
    }
    component_map.deinit();
}
```

### Division by Zero (FIXED 2025-02-03)

**Root Cause:** vaxis `doLayout()` divides by screen width/height. When running via `script` or non-interactive SSH, terminal dimensions are 0x0, causing panic.

**Fix:** Added terminal size validation in `src/tui/app.zig` before `app.run()`. Uses `ioctl(TIOCGWINSZ)` to get terminal dimensions and exits with helpful error if invalid.

**Error message:** "ERROR: Terminal size unavailable or too small"

## Current Error

None - app now validates terminal size before running TUI.

## How to Continue Next Session

### Test Navigation on Proper TTY
```bash
# Directly on pib console (not via ssh)
ssh pib  # interactive login
cd ~/prog/haltune
./zig-out/bin/haltune
```

## Build and Run Commands

```bash
# Sync from local to Pi
rsync -av src/ pib:prog/haltune/src/

# Build on Pi
ssh pib 'cd ~/prog/haltune && ~/bin/zig build -Dtarget=aarch64-linux-gnu'

# Run on pib (direct console, not via script)
ssh pib 'cd ~/prog/haltune && ./zig-out/bin/haltune'

# Run with PTY for testing (may trigger division by zero)
ssh pib 'cd ~/prog/haltune && echo "q" | script -q -c "timeout 3 ./zig-out/bin/haltune" /dev/null'
```

## Clean Up HAL (if stuck)

```bash
# Kill all processes
pkill -9 -f 'haltune|halrun'

# Clear shared memory
ipcs -m | awk '/0x/{print $2}' | xargs -r ipcrm -m
```

## Git Status Summary

Key modified files:
- `src/tui/widgets/tree_view.zig` - Memory management fixes, removed buildTree() from init
- `src/tui/model.zig` - Test pin addition, single buildTree() call
- `src/tui/layout.zig` - Layout rendering

## Next Session Goals

1. ~~**Fix division by zero**~~ - DONE
2. **Test navigation** - Verify arrow keys and Enter work on proper TTY
3. **Enable RefreshThread** - Get live HAL data updates (disabled for testing)
4. **Display actual HAL data** - Replace test pins with real HAL pins

## Files to Check First

1. ~~`src/tui/app.zig`~~ - Screen size validation added
2. ~~`src/tui/widgets/tree_view.zig`~~ - Double-free fixed (pointer comparison)
3. `src/tui/model.zig` - Event routing to widgets
4. `src/tui/widgets/tree_view.zig` - Event handler and navigation (test on TTY)

## Debug Session Reference

- `.planning/debug/resolved/double-free-tree-view.md` - Full debug session with test case
