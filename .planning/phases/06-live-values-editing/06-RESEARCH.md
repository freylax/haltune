# Phase 6: Live Values & Editing - Research

**Researched:** 2026-02-07
**Domain:** Real-time TUI value display and editing with Vaxis (Zig TUI framework)
**Confidence:** HIGH

## Summary

Phase 6 adds real-time value display and in-place editing capabilities to both tree and table views. The existing codebase already has foundational infrastructure:

1. **StateStore + pubsub system** - Thread-safe value cache with change notifications (Phase 01)
2. **DataTable widget** - Already implements basic in-place editing with edit buffers
3. **Vaxis TUI framework** - Provides vxfw widget system with text rendering
4. **HAL FFI bindings** - Safe wrapper functions for reading/writing HAL values

This phase extends existing patterns to tree view, adds value column display, implements signal CRUD operations, and refines the editing experience with proper validation and Unicode symbol display (●/○ for BIT values).

**Primary recommendation:** Reuse DataTable's existing edit_mode pattern (edit_buffer ArrayList + boolean flag) for both tree and table, add value column to tree draw function, and implement signal editing via Ctrl+S with completion UI using status line prompts.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vaxis (vxfw) | git main | TUI widget framework | Already integrated, provides Text/Surface/EventContext |
| Zig stdlib | 0.13.0 | ArrayList, StringHashMap, fmt | Core data structures and parsing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glob | git main | Pattern matching for signal name completion | Filter existing signals by type when editing |

**Installation:** Already configured in build.zig - no new dependencies needed.

## Architecture Patterns

### Existing In-Place Editing Pattern (HIGH confidence)

**Source:** `/home/robert/prog/zig/haltune/src/tui/widgets/data_table.zig` lines 562-640

```zig
// Edit mode state (already exists in DataTable)
edit_mode: bool,
edit_item: ?usize,  // Which item is being edited
edit_buffer: std.ArrayList(u8),  // User input buffer

// Edit mode event handling pattern
if (self.edit_mode) {
    // Escape: cancel
    if (key.matches(vaxis.Key.escape, .{})) {
        self.edit_mode = false;
        self.edit_item = null;
        self.edit_buffer.clearRetainingCapacity();
        ctx.consumeAndRedraw();
        return;
    }

    // Enter: confirm
    if (key.matches(vaxis.Key.enter, .{})) {
        const input = self.edit_buffer.items;
        // Parse and validate
        const value = std.fmt.parseFloat(f64, input) catch {
            try self.setError("Invalid float");
            return;
        };
        try self.writeValue(item, HalValue{ .float = value });
        self.edit_mode = false;
        ctx.consumeAndRedraw();
        return;
    }

    // Backspace: remove last char
    if (key.codepoint == 127) {
        if (self.edit_buffer.items.len > 0) {
            _ = self.edit_buffer.pop();
            ctx.consumeAndRedraw();
        }
        return;
    }

    // Regular character: add to buffer
    if (key.codepoint >= 32 and key.codepoint < 127) {
        const new_char = @as(u8, @intCast(key.codepoint));
        try self.edit_buffer.append(self.allocator, new_char);
        ctx.consumeAndRedraw();
        return;
    }
}
```

**Apply to tree view:** Add identical edit_mode state to TreeView, handle Enter on leaf nodes to enter edit mode.

### Value Column Display Pattern

**Source:** Existing DataTable formatting (lines 849-866)

```zig
// Get current value or edit buffer
const value_str = blk: {
    // If editing this item, show edit buffer
    if (self.edit_mode and self.edit_item != null and self.edit_item.? == idx) {
        break :blk self.edit_buffer.items;
    }

    // Otherwise show current value from StateStore
    const value = self.getItemValue(item) catch |err| {
        break :blk "ERR";
    };
    break :blk formatHalValue(value, ctx.arena);
};
```

**For BIT values (●/○ symbols):**
```zig
fn formatHalValue(value: HalValue, allocator: std.mem.Allocator) []const u8 {
    return switch (value) {
        .bit => |v| if (v) "●" else "○",  // Unicode symbols
        .float => |v| std.fmt.allocPrint(allocator, "{d:.6}", .{v}) catch "ERR",
        .s32 => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR",
        .u32 => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR",
    };
}
```

### Tree Value Column Integration

**Source:** TreeView drawFn (lines 385-512 in tree_view.zig)

Add value column after node name:
```zig
// In draw loop, after writing node name
const value = self.store.getPin(node.full_name) catch
              self.store.getSignal(node.full_name) catch
              self.store.getParam(node.full_name) catch null;

if (value) |v| {
    const value_str = formatHalValue(v, ctx.arena);

    // Right-align value in fixed-width column (8 chars)
    const value_col_start: u16 = @intCast(max_width - 8);
    if (col < value_col_start) {
        col = value_col_start;
    }

    // Write value string
    var char_iter = ctx.graphemeIterator(value_str);
    while (char_iter.next()) |char| {
        const grapheme = char.bytes(value_str);
        const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = grapheme, .width = grapheme_width },
            .style = .{},
        });
        col += grapheme_width;
    }
}
```

### Signal CRUD Operation Pattern

**Connect/Disconnect (Ctrl+S):**
```zig
// In TreeView event handler, on Ctrl+S
if (key.matches('s', .{ .ctrl = true })) {
    const node = self.visible_nodes.items[self.cursor_index];

    // Only pins can connect to signals
    if (node.item_type != .pin) {
        try self.setError("Only pins can connect to signals");
        return;
    }

    // Enter signal name editing mode (similar to edit_mode)
    self.signal_edit_mode = true;
    self.signal_edit_buffer.clearRetainingCapacity();

    // Pre-populate with current signal if connected
    if (self.store.pin_links.get(node.full_name)) |current_signal| {
        try self.signal_edit_buffer.appendSlice(self.allocator, current_signal);
    }

    ctx.consumeAndRedraw();
    return;
}

// In signal_edit_mode
if (self.signal_edit_mode) {
    // Tab: show completion (list matching signals)
    if (key.matches(vaxis.Key.tab, .{})) {
        try self.showSignalCompletion();
        return;
    }

    // Enter: connect to signal (empty = disconnect)
    if (key.matches(vaxis.Key.enter, .{})) {
        const signal_name = self.signal_edit_buffer.items;

        if (signal_name.len == 0) {
            // Disconnect
            try ffi.halUnlink(pin_name);
            try self.store.updatePinLink(pin_name, null);
        } else {
            // Connect to existing or new signal
            // Infer type from current pin
            const pin_value = try self.store.getPin(pin_name);
            const hal_type = halTypeFromHalValue(pin_value);

            // Create signal if doesn't exist
            if (self.store.getSignal(signal_name)) |_| {
                // Signal exists, validate type match
            } else |_| {
                try ffi.halSignalNew(signal_name, hal_type);
                try self.store.addSignal(signal_name, pin_value);
            }

            // Link pin to signal
            try ffi.halLink(pin_name, signal_name);
            try self.store.updatePinLink(pin_name, signal_name);
        }

        self.signal_edit_mode = false;
        ctx.consumeAndRedraw();
        return;
    }

    // Escape: cancel
    if (key.matches(vaxis.Key.escape, .{})) {
        self.signal_edit_mode = false;
        self.signal_edit_buffer.clearRetainingCapacity();
        ctx.consumeAndRedraw();
        return;
    }

    // Backspace + character input (same as edit_mode)
    // ...
}
```

### Status Line Pattern for Full Precision

**Source:** Model.error_message pattern (lines 283-309 in model.zig)

Add to status line display:
```zig
// In layout draw function
if (self.tree_view.visible_nodes.items.len > 0) {
    const cursor_node = self.tree_view.visible_nodes.items[
        self.tree_view.cursor_index
    ];

    // Get full precision value
    const value = self.store.getPin(cursor_node.full_name) catch
                  self.store.getSignal(cursor_node.full_name) catch
                  self.store.getParam(cursor_node.full_name) catch null;

    if (value) |v| {
        const full_value = switch (v) {
            .bit => |b| if (b) "TRUE" else "FALSE",
            .float => |f| try std.fmt.allocPrint(
                ctx.arena,
                "{d:.15}",  // Full float precision
                .{f}
            ),
            .s32 => |i| try std.fmt.allocPrint(ctx.arena, "{d}", .{i}),
            .u32 => |u| try std.fmt.allocPrint(ctx.arena, "{d}", .{u}),
        };

        // Show: "motion.digital-in-00: TRUE"
        const status_text = try std.fmt.allocPrint(
            ctx.arena,
            "{s}: {s}",
            .{ cursor_node.full_name, full_value }
        );

        // Draw status line at bottom
        const status_widget = try ctx.arena.create(vxfw.Text);
        status_widget.* = .{ .text = status_text };
        // ... add to surface
    }
}
```

### Anti-Patterns to Avoid

- **Don't use C strings for editing** - Always use ArrayList(u8) for mutable input
- **Don't parse before validation** - Check editability before entering edit mode
- **Don't block on HAL writes** - Use pending_edits HashMap to mark items awaiting update
- **Don't ignore Unicode width** - Use ctx.graphemeIterator() and ctx.stringWidth() for symbols

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Float parsing | Manual string parsing | std.fmt.parseFloat(f64, input) | Handles scientific notation, validates format |
| Int parsing | Manual digit loop | std.fmt.parseInt(i32/u32, input, 10) | Handles overflow, signs, base conversion |
| Unicode display | Manual UTF-8 handling | ctx.graphemeIterator() + ctx.stringWidth() | Vaxis handles grapheme clusters correctly |
| Signal name completion | Custom matching | glob.match() library | Already integrated, handles wildcards |
| Input buffer | Fixed-size array | std.ArrayList(u8) | Growable, memory-safe, no truncation bugs |

**Key insight:** Zig's stdlib and Vaxis provide battle-tested implementations for all text handling. Custom string parsing code is a common source of bugs (overflow, buffer truncation, UTF-8 violations).

## Common Pitfalls

### Pitfall 1: Editing Read-Only Values

**What goes wrong:** User presses Enter on an input pin connected to a signal, tries to edit, changes don't take effect.

**Why it happens:** Input pins linked to signals get their value from the signal, not from direct writes. Editing should be disabled for connected pins.

**How to avoid:**
```zig
// Check if pin is connected before allowing edit
const is_connected = self.store.pin_links.get(pin_name) != null;
if (item.item_type == .pin and item.direction == .in and is_connected) {
    try self.setError("Cannot edit connected pin - edit signal instead");
    return;
}
```

**Warning signs:** Edit succeeds but value immediately reverts, or pubsub notifications keep resetting the value.

### Pitfall 2: Unicode Symbol Display Width

**What goes wrong:** ● or ○ symbols render as two characters, breaking column alignment.

**Why it happens:** Unicode symbols can be multi-column (width 2) or single-column (width 1) depending on terminal font. Vaxis requires correct width for cell rendering.

**How to avoid:**
```zig
// Use graphemeIterator and stringWidth
var char_iter = ctx.graphemeIterator("●");
while (char_iter.next()) |char| {
    const grapheme = char.bytes("●");
    const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));
    surface.writeCell(col, row, .{
        .char = .{ .grapheme = grapheme, .width = grapheme_width },
    });
    col += grapheme_width;  // May be 1 or 2
}
```

**Warning signs:** Columns misaligned after adding symbols, cursor position wrong, text overlaps.

### Pitfall 3: Edit State Persistence

**What goes wrong:** Edit mode stays active when switching views, or editing carries over to wrong item.

**Why it happens:** edit_mode and edit_item aren't reset when context changes (view switch, tree rebuild, item added/removed).

**How to avoid:**
```zig
// Reset edit mode when tree rebuilds
pub fn buildTree(self: *TreeView) !void {
    self.edit_mode = false;
    self.edit_item = null;
    self.edit_buffer.clearRetainingCapacity();
    // ... rest of buildTree
}

// Reset edit mode when switching views
fn typeErasedEventHandler(...) {
    if (key.matches('t', .{ .ctrl = true })) {
        self.current_view = self.current_view.next();
        self.tree_view.edit_mode = false;
        self.data_table.edit_mode = false;
        ctx.consumeAndRedraw();
        return;
    }
}
```

**Warning signs:** Editing wrong item, edit buffer carries over, crashes when edit_item is out of bounds.

### Pitfall 4: Float Precision Loss in Display

**What goes wrong:** Status line shows "3.14159" but actual value is "3.141592653589793".

**Why it happens:** formatHalValue uses fixed precision (e.g., `{d:.2}`) for compact display, but status line should show full precision.

**How to avoid:**
```zig
// Compact display (column): {d:.6} or {d:.2}
// Full precision (status line): {d}  (no precision specifier)

const full_value = switch (v) {
    .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}),  // Full precision
    // ...
};
```

**Warning signs:** User confused why "exact" value from status line doesn't match input, precision-related test failures.

### Pitfall 5: Signal Name Type Mismatch

**What goes wrong:** Connect BIT pin to FLOAT signal, link succeeds but values are corrupted.

**Why it happens:** hal_link() in LinuxCNC doesn't validate type matching - it will link any pin to any signal, causing undefined behavior.

**How to avoid:**
```zig
// Before linking, validate types match
const pin_value = try self.store.getPin(pin_name);
const pin_type = halTypeFromHalValue(pin_value);

if (self.store.getSignal(signal_name)) |sig_value| {
    const sig_type = halTypeFromHalValue(sig_value);
    if (pin_type != sig_type) {
        return error.TypeMismatch;
    }
}

try ffi.halLink(pin_name, signal_name);
```

**Warning signs:** Values garbage after linking, crashes in refresh thread, HAL log warnings.

## Code Examples

### Type-Specific Input Validation

```zig
// In edit_mode, validate characters before adding to buffer
if (key.codepoint >= 32 and key.codepoint < 127) {
    const new_char = @as(u8, @intCast(key.codepoint));

    // Type-specific validation
    const allowed = switch (item.hal_type) {
        .bit => false,  // BIT doesn't use text edit (toggle only)
        .float => {
            // Allow: digits, minus (start only), decimal point (once)
            if (new_char == '-') self.edit_buffer.items.len == 0
            else if (new_char == '.') !std.mem.indexOfScalar(u8, self.edit_buffer.items, '.')
            else new_char >= '0' and new_char <= '9'
        },
        .s32 => {
            // Allow: digits, minus (start only)
            if (new_char == '-') self.edit_buffer.items.len == 0
            else new_char >= '0' and new_char <= '9'
        },
        .u32 => {
            // Allow: digits only
            new_char >= '0' and new_char <= '9'
        },
    };

    if (allowed) {
        try self.edit_buffer.append(self.allocator, new_char);
        ctx.consumeAndRedraw();
    } else {
        // Invalid character for type - maybe show error
    }
    return;
}
```

### BIT Toggle Implementation

```zig
// Enter on BIT value: simple toggle, no edit mode
if (key.matches(vaxis.Key.enter, .{})) {
    const item = &self.items.items[idx];

    if (item.hal_type == .bit) {
        // Toggle: read current value, invert, write back
        const current_value = self.getItemValue(item.*) catch {
            try self.setError("Failed to read value");
            return;
        };

        const new_value = switch (current_value) {
            .bit => |v| !v,
            else => return error.TypeMismatch,
        };

        self.writeValue(item.*, HalValue{ .bit = new_value }) catch {
            try self.setError("Write failed");
            return;
        };

        try self.pending_edits.put(item.name, {});
        ctx.consumeAndRedraw();
        return;
    }

    // Non-BIT types: enter edit mode
    self.edit_mode = true;
    self.edit_item = idx;
    self.edit_buffer.clearRetainingCapacity();
    ctx.consumeAndRedraw();
}
```

### Signal Completion UI

```zig
// Tab in signal_edit_mode: show available signals
fn showSignalCompletion(self: *TreeView, ctx: *vxfw.EventContext) !void {
    const prefix = self.signal_edit_buffer.items;

    // Get all signals matching prefix and type
    var matches = std.ArrayList([]const u8).init(self.allocator);
    defer {
        for (matches.items) |m| self.allocator.free(m);
        matches.deinit(self.allocator);
    }

    const all_signals = try self.store.listSignals(self.allocator);
    defer self.allocator.free(all_signals);

    for (all_signals) |sig_name| {
        // Match prefix
        if (prefix.len == 0 or std.mem.startsWith(u8, sig_name, prefix)) {
            // TODO: Filter by type (match current pin's type)
            try matches.append(try self.allocator.dupe(u8, sig_name));
        }
    }

    if (matches.items.len == 0) {
        try self.setError("No matching signals");
    } else if (matches.items.len == 1) {
        // Exact match: autocomplete
        self.signal_edit_buffer.clearRetainingCapacity();
        try self.signal_edit_buffer.appendSlice(self.allocator, matches.items[0]);
    } else {
        // Multiple matches: show in status line
        const match_list = try std.mem.join(self.allocator, ", ", matches.items);
        defer self.allocator.free(match_list);
        try self.setError(match_list);
    }

    ctx.consumeAndRedraw();
}
```

### Value Truncation for Overflow

```zig
// Format value with max width (6-8 chars for column)
fn formatHalValueCompact(value: HalValue, allocator: std.mem.Allocator) ![]const u8 {
    return switch (value) {
        .bit => |v| if (v) "●" else "○",
        .float => |f| {
            // Try full precision first
            const full = try std.fmt.allocPrint(allocator, "{d:.6}", .{f});

            // Truncate if too long
            if (full.len > 8) {
                // Show "1234.56" format or "1.2e+05" for large numbers
                if (@abs(f) >= 100000.0) {
                    return try std.fmt.allocPrint(allocator, "{d:.1e}", .{f});
                }
                // Truncate decimal places
                const truncated = full[0..8];
                // Add ellipsis if truncated
                if (full.len > 8) {
                    return try std.fmt.allocPrint(allocator, "{s}...", .{truncated[0..5]});
                }
                return truncated;
            }
            return full;
        },
        .s32 => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
        .u32 => |u| std.fmt.allocPrint(allocator, "{d}", .{u}),
    };
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Edit dialog popup | In-place editing with edit_buffer | Phase 05 | Faster workflow, less modal disruption |
| Full precision everywhere | Compact column + full precision status line | Phase 06 (planned) | Cleaner UI, more information density |
| Signal creation only | Full CRUD (connect, create, disconnect, delete) | Phase 06 (planned) | Complete signal management from TUI |

**Implemented in current codebase:**
- DataTable edit_mode (lines 562-640): HIGH confidence working pattern
- pubsub system for live updates (Phase 01): Verified working
- Vaxis vxfw widget system: Well-established, stable API

## Open Questions

1. **Signal completion UI design**
   - What we know: Tab should trigger completion, need to show matching signals
   - What's unclear: Display completion in popup vs status line vs inline overlay
   - Recommendation: Start with status line display (simplest), consider popup for Phase 07

2. **Signal delete confirmation UX**
   - What we know: Disconnecting last pin from signal should prompt for signal deletion
   - What's unclear: Wording, whether to use "y/n" prompt or dedicated dialog
   - Recommendation: Use status line prompt "Signal 'xxx' has no pins. Delete? [y/n]"

3. **Float truncation character**
   - What we know: Values wider than column need truncation indicator
   - What's unclear: Use "..." (Unicode ellipsis U+2026) or "..." (three periods) or ">"
   - Recommendation: Test "..." (three periods) for terminal compatibility, Phase 07 can refine

## Sources

### Primary (HIGH confidence)
- `/home/robert/prog/zig/haltune/src/tui/widgets/data_table.zig` - Existing edit_mode implementation (lines 562-640)
- `/home/robert/prog/zig/haltune/src/tui/widgets/tree_view.zig` - TreeView structure and draw function (lines 385-512)
- `/home/robert/prog/zig/haltune/src/state/cache.zig` - StateStore API for value access
- `/home/robert/prog/zig/haltune/src/state/pubsub.zig` - SubscriptionManager for live updates
- `/home/robert/prog/zig/haltune/src/ffi/safe.zig` - Safe FFI wrappers for HAL operations
- [libvaxis GitHub](https://github.com/rockorager/libvaxis) - Vaxis TUI framework documentation and examples

### Secondary (MEDIUM confidence)
- [Working with Strings in Zig (2025)](https://pmbanugo.me/blog/zig-working-with-strings) - Modern Zig string handling patterns
- [Zig robust float parsing discussion](https://github.com/ziglang/zig/issues/2207) - Float parsing validation patterns

### Tertiary (LOW confidence)
- [Zig best practices discussion (Reddit)](https://www.reddit.com/r/Zig/comments/sanpzf/zig_best_practices_emerging_patterns/) - Community patterns (not directly verified)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Vaxis and Zig stdlib are well-established, already integrated
- Architecture: HIGH - Existing codebase demonstrates working patterns (DataTable edit_mode)
- Pitfalls: HIGH - Based on direct inspection of codebase and common TUI editing bugs
- Signal CRUD: MEDIUM - HAL FFI functions verified, but completion UI needs exploration

**Research date:** 2026-02-07
**Valid until:** 2026-03-09 (30 days - Vaxis API is stable, codebase patterns won't change)
