# Phase 3: TUI Core - Research

**Researched:** 2026-01-29
**Domain:** Terminal User Interface (TUI) Development with Zig
**Confidence:** HIGH

## Summary

This research investigated how to implement a Vaxis-based two-panel TUI for real-time HAL component browsing. The phase requires building a terminal interface with a left tree navigation panel (checkboxes for item selection, collapsible hierarchy) and a right data table panel (displaying selected items with real-time value updates), plus search/filter capabilities and in-place editing with type validation.

**Key findings:**
- **Vaxis (libvaxis) is the standard TUI library for Zig** - actively maintained, modern terminal feature support, provides both low-level API and high-level framework (vxfw)
- **Use vxfw framework for this phase** - Flutter-like widget system with event handling, focus management, and automatic redraw optimization
- **Two-panel layout requires custom implementation** - Vaxis doesn't provide built-in split panels; must create using child windows with manual sizing
- **Real-time updates need pubsub integration** - StateStore's SubscriptionManager can trigger redraws via ctx.consumeAndRedraw() when values change
- **No built-in glob in Zig stdlib** - Use third-party `glob.zig` library for pattern matching (wildcards, character classes)

**Primary recommendation:** Use Vaxis vxfw framework for TUI development, integrate with existing StateStore via pubsub callbacks, implement custom two-panel layout using child windows with SubSurface positioning, and use glob.zig for search pattern matching.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **libvaxis** | Latest (Zig 0.15.1) | Terminal UI framework | Actively maintained, modern terminal features, supports both low-level and high-level APIs, used by multiple production TUIs (Ghostty terminal, Vigil build watcher) |
| **vxfw** | Part of libvaxis | High-level widget framework | Flutter-like API with automatic redraw optimization, focus management, event bubbling - ideal for reactive TUI apps |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **glob.zig** | Latest | Glob pattern matching | Search functionality with wildcards (*, ?, [a-z]) - Zig stdlib lacks built-in glob support |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| libvaxis | TUI.zig | TUI.zig has 36+ widgets but less mature ecosystem; libvaxis has more real-world usage and active development |
| libvaxis | Custom ncurses | Hand-rolling is unnecessary complexity; Vaxis provides modern terminal features (RGB, Kitty protocol, bracketed paste) |

**Installation:**

```bash
# Add to build.zig
const vaxis = b.dependency("vaxis", .{
    .target = target,
    .optimize = optimize,
});

# Add glob.zig (fetch from GitHub)
zig fetch --save git+https://github.com/xcaeser/glob.zig.git
```

**Integration with existing codebase:**

```zig
// build.zig additions
const vaxis = b.dependency("vaxis", .{
    .target = target,
    .optimize = optimize,
});

// Create TUI module
const tui_module = b.createModule(.{
    .root_source_file = b.path("src/tui/app.zig"),
    .target = target,
    .optimize = optimize,
});

// Import existing modules
tui_module.addImport("ffi-errors", ffi_errors);
tui_module.addImport("ffi-types", ffi_types);
tui_module.addImport("state-cache", state_cache);
tui_module.addImport("state-pubsub", state_pubsub);

// Add Vaxis
tui_module.addImport("vaxis", vaxis.module("vaxis"));
```

## Architecture Patterns

### Recommended Project Structure

```
src/
├── tui/
│   ├── app.zig              # Main application entry point, vxfw.App init
│   ├── model.zig            # Application state (Model struct)
│   ├── widgets/
│   │   ├── tree_view.zig    # Left panel: component tree with checkboxes
│   │   ├── data_table.zig   # Right panel: tabular data display
│   │   └── input_modal.zig  # In-place editing popup for numeric values
│   └── layout.zig           # Two-panel split layout logic
```

### Pattern 1: Vxfw Application Structure

**What:** Flutter-like widget system where stateful widgets return `vxfw.Widget` structs with event handlers and draw functions. The vxfw runtime manages the event loop, focus, and redraw optimization.

**When to use:** All TUI components - this is the standard way to build Vaxis apps.

**Example:**

```zig
// Source: https://github.com/rockorager/libvaxis
const Model = struct {
    count: u32 = 0,
    button: vxfw.Button,

    // Return a vxfw.Widget from application state
    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.typeErasedEventHandler,
            .drawFn = Model.typeErasedDrawFn,
        };
    }

    // Event handler for key presses, mouse, focus
    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event
    ) anyerror!void {
        const self: *Model = @ptrCast(@alignCast(ptr));
        switch (event) {
            .init => return ctx.requestFocus(self.button.widget()),
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
            },
            else => {},
        }
    }

    // Draw function called when redraw flag is set
    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));

        // Use arena for temporary allocations (freed next frame)
        const text = try std.fmt.allocPrint(ctx.arena, "{d}", .{self.count});

        // Return Surface with size, buffer, and children
        return .{
            .size = ctx.max.size().?,
            .widget = self.widget(),
            .buffer = &.{},
            .children = &.{
                .{ .origin = .{ .row = 0, .col = 0 }, .surface = try text_widget.draw(ctx) },
            },
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    const model = try allocator.create(Model);
    defer allocator.destroy(model);

    model.* = .{ .count = 0, .button = .{ .label = "Click me!" } };

    try app.run(model.widget(), .{});
}
```

### Pattern 2: Two-Panel Layout with Child Windows

**What:** Manually position child surfaces using SubSurface offsets to create split-panel layout. Left panel gets ~30% width, right panel gets remaining width.

**When to use:** Main application layout - no built-in split panel widget in Vaxis.

**Example:**

```zig
fn drawTwoPanelLayout(
    ptr: *anyopaque,
    ctx: vxfw.DrawContext
) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Model = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size().?;

    // Calculate split: 30% left panel, 70% right panel
    const left_width = max.width / 3;
    const right_width = max.width - left_width;

    // Left panel (tree view)
    const left_panel: vxfw.SubSurface = .{
        .origin = .{ .row = 0, .col = 0 },
        .surface = try self.tree_view.draw(ctx.withConstraints(
            .{ .width = left_width, .height = max.height },
            .{ .width = left_width, .height = max.height }
        )),
    };

    // Right panel (data table)
    const right_panel: vxfw.SubSurface = .{
        .origin = .{ .row = 0, .col = left_width },
        .surface = try self.data_table.draw(ctx.withConstraints(
            .{ .width = right_width, .height = max.height },
            .{ .width = right_width, .height = max.height }
        )),
    };

    const children = try ctx.arena.alloc(vxfw.SubSurface, 2);
    children[0] = left_panel;
    children[1] = right_panel;

    return .{
        .size = max,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}
```

### Pattern 3: Pubsub-Driven Redraws

**What:** Subscribe to StateStore changes via SubscriptionManager, call `ctx.consumeAndRedraw()` in callback to trigger redraw only when values change.

**When to use:** Real-time value updates - prevents unnecessary redraws and lag.

**Example:**

```zig
// Subscribe to pin changes
fn subscribeToPins(self: *Model, store: *StateStore) !void {
    // Callback triggers redraw on value change
    const callback = struct {
        fn fnPtr(
            item_name: []const u8,
            old_value: ?HalValue,
            new_value: HalValue
        ) void {
            _ = item_name;
            _ = old_value;
            _ = new_value;
            // Trigger redraw on next event loop iteration
            // (Access via global or passed context)
        }
    }.fnPtr;

    try store.pubsub.subscribe("motion.digital-in-00", callback);
}

// In event handler, redraw when pubsub signals change
fn typeErasedEventHandler(
    ptr: *anyopaque,
    ctx: *vxfw.EventContext,
    event: vxfw.Event
) ) anyerror!void {
    const self: *Model = @ptrCast(@alignCast(ptr));

    switch (event) {
        .init => {
            // Subscribe to state changes
            try self.subscribeToPins();
        },
        // Custom event from pubsub thread
        .value_change => {
            // Mark that redraw is needed
            return ctx.consumeAndRedraw();
        },
        else => {},
    }
}
```

### Anti-Patterns to Avoid

- **Don't redraw on every event:** Only call `ctx.consumeAndRedraw()` when state actually changes. Vaxis won't redraw until this flag is set.
- **Don't block the event loop:** Keep event handlers fast. Heavy operations (HAL reads) happen in refresh thread, not TUI thread.
- **Don't ignore arena allocator:** Use `ctx.arena` for temporary allocations (strings, slices) - it's freed automatically after each frame.
- **Don't hardcode terminal size:** Use `ctx.max/min` constraints and dynamic sizing for responsive layout (TUI-02 requires 80x24 minimum).

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Terminal feature detection | Custom terminal query code | Vaxis capabilities detection | Vaxis queries terminal automatically for RGB, Kitty protocol, bracketed paste, synchronized output |
| Event loop with threading | Manual pthread/std.Thread spawning | vaxis.Loop | Thread-safe event loop with SIGWINCH handling, query response processing |
| Input parsing | Manual byte parsing | vaxis event parser | Handles escape sequences, UTF-8, mouse events, function keys correctly |
| Widget focus management | Custom focus tracking | vxfw focus system | Handles focus bubbles, capture phase, requestFocus API |
| Screen double buffering | Manual screen buffer diffing | vaxis.Screen | Compares frames and only redraws changed cells (optimization built-in) |

**Key insight:** Vaxis provides a complete TUI stack - building custom terminal handling is unnecessary and error-prone. The library handles low-level terminal details (escape sequences, feature detection, screen buffering) so you can focus on application logic.

## Common Pitfalls

### Pitfall 1: Excessive Redraws Causing Lag

**What goes wrong:** Redrawing the entire screen on every event causes stutter, especially on Raspberry Pi 5. Users experience lag during HAL refresh.

**Why it happens:** Calling redraw in event handlers for non-state-changing events (mouse motion, unhandled keys) wastes CPU cycles rendering identical frames.

**How to avoid:** Only call `ctx.consumeAndRedraw()` when state actually changes. Use pubsub callbacks to trigger redraws only when values update, not on every event.

**Warning signs:** TUI stuttering during typing, high CPU usage, visible delay between value changes and screen updates.

### Pitfall 2: Blocking Event Loop with HAL Reads

**What goes wrong:** TUI freezes because event handler calls HAL FFI functions directly, blocking the event loop thread.

**Why it happens:** HAL reads can be slow (mutex locks, memory access). Doing this in the event thread prevents key/mouse events from being processed.

**How to avoid:** Never call HAL functions from TUI event handlers. The refresh thread (Phase 2) updates StateStore. TUI only reads from StateStore via thread-safe RwLock.

**Example:**
```zig
// WRONG - blocks event loop
.key_press => |key| {
    const value = halGetPin("motion.0.in"); // SLOW!
    try self.displayValue(value);
}

// CORRECT - reads from cache
.key_press => |key| {
    const value = try store.getPin("motion.0.in"); // FAST (cached)
    try self.displayValue(value);
}
```

### Pitfall 3: Memory Leaks from Arena Misuse

**What goes wrong:** Memory usage grows indefinitely because temporary allocations aren't freed.

**Why it happens:** Using general-purpose allocator instead of `ctx.arena` for per-frame allocations. Arena allocator is reset after each frame.

**How to avoid:** Always use `ctx.arena` for temporary allocations (formatted strings, slices) in draw functions.

**Example:**
```zig
// WRONG - memory leak
fn typeErasedDrawFn(...) !vxfw.Surface {
    const text = try std.fmt.allocPrint(self.allocator, "{d}", .{self.count});
    // text is never freed!
}

// CORRECT - auto-freed next frame
fn typeErasedDrawFn(...) !vxfw.Surface {
    const text = try std.fmt.allocPrint(ctx.arena, "{d}", .{self.count});
    // text freed automatically after frame
}
```

### Pitfall 4: Incorrect Glob Pattern Matching

**What goes wrong:** Search functionality fails to match patterns like "*pid*" or "*.enabled".

**Why it happens:** Zig's stdlib doesn't include glob pattern matching. Using `std.mem.eql` or simple string comparison doesn't support wildcards.

**How to avoid:** Use third-party `glob.zig` library for proper glob matching.

**Example:**
```zig
// WRONG - no wildcard support
if (std.mem.eql(u8, pin_name, "pid.*")) { ... }

// CORRECT - glob.zig
const glob = @import("glob");
if (glob.match("pid.*", pin_name)) { ... }
```

### Pitfall 5: Tree View State Management

**What goes wrong:** Tree view loses expand/collapse state or checkbox selections when redraw happens.

**Why it happens:** Not storing tree state in Model struct. Draw function creates new state each frame instead of rendering persistent state.

**How to avoid:** Store tree state (expanded nodes, checked items) in Model as ArrayLists or HashMaps. Draw function renders this state, doesn't modify it.

**Example:**
```zig
const Model = struct {
    // Persistent state
    expanded_nodes: std.StringHashMap(void),
    checked_items: std.StringHashMap(void),

    // Draw renders state, doesn't modify
    fn typeErasedDrawFn(...) !vxfw.Surface {
        // Read from self.expanded_nodes, self.checked_items
        // Don't modify them here
    }

    // Event handlers modify state
    fn typeErasedEventHandler(...) !void {
        // Update self.expanded_nodes, self.checked_items
        // Then request redraw
    }
};
```

### Pitfall 6: Editable vs Read-Only Visual Distinction

**What goes wrong:** Users can't tell which items are editable (writable parameters, OUT/I/O pins) vs read-only (IN pins, RO parameters), leading to confusion.

**Why it happens:** Not using color or icon indicators to visually distinguish editability.

**How to avoid:** Use Vaxis Style to color-code editable items differently (e.g., green text for editable, dim gray for read-only).

**Example:**
```zig
const is_editable = isParamWritable(param) or isPinOutOrIO(pin);

const style: vaxis.Style = if (is_editable)
    .{ .fg = .{ .index = 2 } }  // Green for editable
else
    .{ .fg = .{ .index = 8 } }; // Dim gray for read-only

const text = vxfw.Text{
    .text = name,
    .style = style,
};
```

## Code Examples

Verified patterns from official sources:

### Example 1: Basic Vxfw Application

```zig
// Source: https://github.com/rockorager/libvaxis (counter example)
const vxfw = vaxis.vxfw;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    const model = try allocator.create(Model);
    defer allocator.destroy(model);

    model.* = .{
        .count = 0,
        .button = .{ .label = "Click me!" },
    };

    try app.run(model.widget(), .{});
}
```

### Example 2: Button with Click Handler

```zig
// Source: https://github.com/rockorager/libvaxis
const Model = struct {
    button: vxfw.Button,

    fn onClick(maybe_ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
        const ptr = maybe_ptr orelse return;
        const self: *Model = @ptrCast(@alignCast(ptr));
        self.count +|= 1;
        return ctx.consumeAndRedraw();
    }
};

model.* = .{
    .count = 0,
    .button = .{
        .label = "Click me!",
        .onClick = Model.onClick,
        .userdata = model,
    },
};
```

### Example 3: Text Widget with Styling

```zig
// Source: https://github.com/rockorager/libvaxis
const text: vxfw.Text = .{
    .text = "Hello, Vaxis!",
    .style = .{
        .fg = .{ .index = 2 }, // Green foreground
        .bold = true,
    },
};

// Text implements Widget interface
const surface = try text.draw(ctx);
```

### Example 4: Child Window with Border

```zig
// Source: https://github.com/rockorager/libvaxis (low-level API)
const win = vx.window();

const child = win.child(.{
    .x_off = 10,
    .y_off = 5,
    .width = 40,
    .height = 10,
    .border = .{
        .where = .all,
        .style = .{ .fg = .{ .index = 4 } }, // Blue border
    },
});

// Draw content in child window
child.writeStr("Hello from child window!");
```

### Example 5: Event Loop with Custom Events

```zig
// Source: https://github.com/rockorager/libvaxis (low-level API)
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    value_change: []const u8, // Custom event
};

while (true) {
    const event = loop.nextEvent();
    switch (event) {
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true })) break;
        },
        .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
        .value_change => |name| {
            // Redraw when value changes
            try redrawTable(name);
        },
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ncurses/terminfo | Vaxis (no terminfo) | 2023+ | Vaxis detects features via terminal queries, not database - more reliable on modern terminals |
| Manual redraw management | vxfw automatic redraw optimization | 2024+ | Only redraw when ctx.consumeAndRedraw() called - prevents excessive rendering |
| Single-threaded TUI | Multi-threaded with Loop | 2023+ | Vaxis.Loop reads TTY in separate thread - prevents blocking |
| Limited terminal features | Full modern feature support | 2023+ | RGB colors, Kitty keyboard protocol, bracketed paste, synchronized output |

**Deprecated/outdated:**
- **ncurses**: Older TUI library, requires terminfo database, less reliable feature detection
- **Manual escape sequence handling**: Error-prone, Vaxis handles this automatically
- **Sync I/O for terminal input**: Blocks application, Vaxis.Loop provides async event handling

## Open Questions

1. **Vaxis widget library completeness for complex widgets**
   - What we know: Vaxis provides basic widgets (Button, Text, TextInput), TreeView and Table widgets must be implemented manually
   - What's unclear: Whether Vaxis community has shared implementations of tree/table widgets we can reference
   - Recommendation: Implement custom TreeView and DataTable widgets following vxfw widget pattern (store state in Model, implement eventHandler and drawFn)

2. **Performance on Raspberry Pi 5 with high refresh rates**
   - What we know: StateStore refreshes at 100ms default, pubsub notifies on change
   - What's unclear: Whether Vaxis redraws at 100ms cause noticeable lag on Pi 5 hardware
   - Recommendation: Implement refresh rate throttling in TUI - don't redraw faster than 10-15 FPS (human perception limit), even if HAL refreshes faster

3. **Glob pattern matching integration**
   - What we know: glob.zig library provides pattern matching, needs to be added as dependency
   - What's unclear: Performance of glob.zig for large item lists (1000+ pins/signals)
   - Recommendation: Benchmark glob.zig performance with typical HAL component counts; if slow, consider indexed search (build HashMap on first search, reuse for subsequent searches)

## Sources

### Primary (HIGH confidence)

- **libvaxis GitHub repository** - Complete API documentation, examples, vxfw framework guide (counter example, low-level API)
  - URL: https://github.com/rockorager/libvaxis
  - Verified: Actively maintained, official source, contains working examples
- **Vaxis vxfw framework documentation** - Flutter-like widget system API with event handling and draw functions
  - URL: https://github.com/rockorager/libvaxis (vxfw section)
  - Verified: Official documentation, code examples compile and run

### Secondary (MEDIUM confidence)

- **TodoMVC TUI implementations** - Multiple TUI frameworks compared including Vaxis implementation (326 LOC Zig version)
  - URL: https://github.com/hedyhli/todomvc-tui
  - Verified: Real-world Vaxis app example, demonstrates state management and widget patterns
- **glob.zig library** - Pure Zig glob pattern matching implementation
  - URL: https://github.com/xcaeser/glob.zig
  - Verified: Community-vetted library, supports standard glob wildcards (*, ?, [a-z])
- **Ziggit forum discussion on glob patterns** - Community guidance on glob pattern matching in Zig
  - URL: https://ziggit.dev/t/how-do-i-match-glob-patterns-in-zig/4769
  - Verified: Community consensus that stdlib lacks glob, third-party solutions needed

### Tertiary (LOW confidence)

- **Terminal GUI documentation** - TUI design patterns for checkboxes and tree navigation
  - URL: https://gui-cs.github.io/Terminal.Gui/docs/views.html
  - Note: Different framework (.NET Terminal.Gui), patterns may not translate directly to Vaxis
- **Data table UX best practices** - Scrollable vs paginated table design guidelines
  - URL: https://www.designrelax.com/design/data-table-design-best-practices-for-better-ux/
  - Note: Web-focused design, terminal constraints differ (limited screen real estate)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Vaxis is the de facto standard for Zig TUIs, confirmed by multiple production uses
- Architecture: HIGH - Vxfw framework is well-documented with working examples, patterns are clear
- Pitfalls: MEDIUM - Based on general TUI best practices and Vaxis design patterns, some speculation on Pi 5 performance

**Research date:** 2026-01-29
**Valid until:** 2026-03-01 (30 days - Vaxis is stable but fast-moving ecosystem)

**Key assumptions:**
- Zig 0.15.1 compatibility (Vaxis requirement)
- Raspberry Pi 5 terminal supports modern terminal features (RGB, Kitty keyboard protocol)
- HAL refresh rate (100ms) is faster than required TUI refresh rate (10-15 FPS)
