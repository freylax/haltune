# haltune Plugin API

**Version:** 1.0
**Last Updated:** 2026-02-15

## Overview

Plugins extend haltune with domain-specific workflows like PID tuning, velocity testing, and machine calibration. Plugins receive events, can read HAL values, and render custom UI.

## Architecture

**Compile-time registration:** Plugins are registered at compile time as Zig modules. No dynamic loading for MVP.

## Plugin Interface

Every plugin must implement the `Plugin` interface from `src/plugin/interface.zig`:

```zig
const std = @import("std");
const interface = @import("../plugin/interface.zig");

fn myPluginInit(ctx: *const interface.PluginContext) anyerror!void {
    ctx.logInfo("My plugin initialized!");
    // Subscribe to HAL values here
    try ctx.subscribe("motion.digital-in-00", struct {
        fn callback(name: []const u8, value: interface.HalValue) void {
            _ = name;
            _ = value;
            // Handle value change
        }
    });
}

fn myPluginDeinit(ctx: *const interface.PluginContext) void {
    _ = ctx;
    // Free resources, unsubscribe from HAL values
}

fn myPluginRender(ctx: *const interface.PluginContext, vctx: vxfw.Context) anyerror!void {
    _ = ctx;
    _ = try vctx.write(.{ .text = "Hello from my plugin!" });
}

fn myPluginHandleEvent(ctx: *const interface.PluginContext, event: interface.PluginEvent) bool {
    _ = ctx;
    if (event == .key_press) |kp| {
        if (kp.codepoint == 'q') {
            return true; // Handle 'q' key
        }
    }
    return false; // Don't handle other events
}

pub const my_plugin: interface.Plugin = .{
    .name = "My Plugin",
    .version = "1.0.0",
    .description = "Does something useful",
    .init = myPluginInit,
    .deinit = myPluginDeinit,
    .render = myPluginRender,
    .handleEvent = myPluginHandleEvent,
};
```

## Lifecycle

### 1. **Init** - Called when plugin is activated via UI
- Allocate resources
- Subscribe to HAL values
- Return error if initialization fails

### 2. **Render** - Called every TUI redraw cycle
- Draw plugin UI into provided context
- Use arena allocator for temporary strings
- Don't mutate HAL (read-only during render)

### 3. **HandleEvent** - Called for each event
- Return `true` if event was handled
- Return `false` to let event propagate

### 4. **Deinit** - Called when plugin is deactivated
- Free all allocated resources
- Unsubscribe from HAL values

## Plugin Context

The `PluginContext` provides read-only access to application state:

| Method | Purpose |
|--------|---------|
| `getValue(name)` | Get current HAL value (returns `?HalValue`) |
| `subscribe(pattern, callback)` | Subscribe to HAL value changes |
| `logInfo(msg)` | Log at info level |
| `logError(msg)` | Log at error level |

## Events

Plugins receive `PluginEvent` union:

| Event | Description |
|-------|-------------|
| `key_press` | User pressed a key (codepoint + modifiers) |
| `tick` | Timer tick (for periodic updates) |
| `hal_change` | HAL value changed |
| `focus` | Plugin gained focus |
| `blur` | Plugin lost focus |

## Example: Minimal Plugin

```zig
const std = @import("std");
const interface = @import("../../plugin/interface.zig");

fn init(ctx: *const interface.PluginContext) anyerror!void {
    ctx.logInfo("Hello plugin initialized!");
}

fn deinit(ctx: *const interface.PluginContext) void {
    _ = ctx;
}

fn render(ctx: *const interface.PluginContext, vctx: vxfw.Context) anyerror!void {
    _ = ctx;
    _ = try vctx.write(.{ .text = "Hello from plugin!" });
}

fn handleEvent(ctx: *const interface.PluginContext, event: interface.PluginEvent) bool {
    _ = ctx;
    if (event == .key_press) |kp| {
        if (kp.codepoint == 'q') {
            return true; // Handle 'q' key
        }
    }
    return false; // Don't handle other events
}

pub const hello_plugin: interface.Plugin = .{
    .name = "Hello",
    .version = "1.0.0",
    .description = "A minimal example plugin",
    .init = init,
    .deinit = deinit,
    .render = render,
    .handleEvent = handleEvent,
};
```

## Best Practices

1. **Use arena allocator for render strings** - Free automatically each frame
2. **Return errors from init()** - User sees error message, plugin doesn't load
3. **Subscribe only to needed values** - Performance matters
4. **Check event types carefully** - Union enum, wrong branch crashes
5. **Free resources in deinit()** - Memory leaks accumulate
6. **Don't mutate HAL in render()** - Read-only during render cycle

## Limitations

- No HAL write access in MVP (read-only)
- No plugin settings/persistence (yet)
- Compile-time registration only (no dynamic loading)
- Single active plugin at a time (MVP limitation)
