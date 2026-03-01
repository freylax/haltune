# Plugin Tabbar UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace modal plugin dialog with persistent tabbar for seamless plugin integration into main TUI.

**Architecture:** Add TabBar widget at top, TabPanelLayout for split/full views, PluginContainer for wrapped plugin rendering. Model manages active tab state, PluginManager handles lifecycle (init/deinit) on tab switches.

**Tech Stack:** Zig 0.15.2, vaxis/vxfw TUI framework, existing HAL backend

---

## Task 1: Update TOML Config for Plugin Tab Configuration

**Files:**
- Modify: `src/config/toml_config.zig`

**Step 1: Add plugin tab configuration to TomlConfig**

Add to `TomlConfig` struct after `files` section (around line 40):

```zig
// Plugin configuration for tabbar
pub const PluginsConfig = struct {
    /// Which plugins appear as tabs (null = all plugins)
    enabled: ?[][]const u8 = null,
};

plugins: PluginsConfig = .{},
```

**Step 2: Update loadConfig to parse plugins section**

Add after `files` parsing (around line 120):

```zig
// Parse plugins section
if (toml_value.getObject("plugins")) |plugins_obj| {
    var enabled_list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (enabled_list.items) |s| allocator.free(s);
        enabled_list.deinit(allocator);
    }

    if (plugins_obj.get("enabled")) |enabled_val| {
        if (enabled_val != .array) return error.InvalidConfig;
        for (enabled_val.array) |item| {
            if (item != .string) return error.InvalidConfig;
            try enabled_list.append(allocator, try allocator.dupe(u8, item.string));
        }
    }

    result.plugins.enabled = try enabled_list.toOwnedSlice(allocator);
}
```

**Step 3: Update deinit to free plugins.enabled**

Add to `deinit` function after `files` cleanup:

```zig
if (toml.plugins.enabled) |enabled| {
    for (enabled) |s| allocator.free(s);
    allocator.free(enabled);
}
```

**Step 4: Build to verify**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 5: Commit**

```bash
git add src/config/toml_config.zig
git commit -m "feat: add plugins tab configuration to TOML parser

- Add plugins.enabled array to TomlConfig
- Parse which plugins appear as tabs from haltune.toml
- Free allocated strings in deinit"
```

---

## Task 2: Create TabBar Widget

**Files:**
- Create: `src/tui/widgets/tabbar.zig`

**Step 1: Create TabBar widget structure**

```zig
// TabBar Widget - Displays tabs at top of TUI
//
// Shows a list of tabs with one active. Handles keyboard (Alt+N) and
// mouse click selection.

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");

pub const TabBar = struct {
    allocator: std.mem.Allocator,
    tabs: std.ArrayList(Tab),
    selected_idx: usize = 0,
    scroll_offset: usize = 0,

    pub const Tab = struct {
        name: []const u8,
        key_hint: ?[]const u8 = null,  // e.g., "1" for Alt+1
    };

    pub fn init(allocator: std.mem.Allocator) TabBar {
        return .{
            .allocator = allocator,
            .tabs = std.ArrayList(Tab).init(allocator),
        };
    }

    pub fn deinit(self: *TabBar) void {
        for (self.tabs.items) |t| {
            if (t.key_hint) |h| self.allocator.free(h);
            self.allocator.free(t.name);
        }
        self.tabs.deinit(self.allocator);
    }

    pub fn addTab(self: *TabBar, name: []const u8, key_hint: ?[]const u8) !void {
        const hint = if (key_hint) |h| try self.allocator.dupe(u8, h) else null;
        errdefer if (hint) |h| self.allocator.free(h);
        try self.tabs.append(.{
            .name = try self.allocator.dupe(u8, name),
            .key_hint = hint,
        });
    }

    pub fn getSelected(self: *const TabBar) ?Tab {
        if (self.selected_idx >= self.tabs.items.len) return null;
        return self.tabs.items[self.selected_idx];
    }

    pub fn setSelected(self: *TabBar, idx: usize) void {
        if (idx < self.tabs.items.len) {
            self.selected_idx = idx;
        }
    }

    pub fn widget(self: *TabBar) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = null,  // Events handled by parent
            .drawFn = struct {
                fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
                    const tb: *TabBar = @ptrCast(@alignCast(ptr));
                    return tb.draw(ctx);
                }
            }.draw,
        };
    }

    pub fn draw(self: *TabBar, ctx: vxfw.DrawContext) !vxfw.Surface {
        const width = ctx.max.width orelse 80;
        const height = 1;

        var surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            .{ .width = @intCast(width), .height = height },
        );

        // Clear surface
        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        // Draw tabs
        var x: usize = 0;
        for (self.tabs.items, 0..) |tab, i| {
            const is_selected = (i == self.selected_idx);

            // Draw tab name
            for (tab.name, 0..) |c, j| {
                if (x + j >= width) break;
                surface.writeCell(@intCast(x + j), 0, .{
                    .char = .{ .grapheme = tab.name[j..j+1], .width = 1 },
                    .style = if (is_selected) .{ .reverse = true } else .{},
                });
            }

            // Draw key hint
            if (tab.key_hint) |hint| {
                const hint_x = x + tab.name.len + 1;
                surface.writeCell(@intCast(hint_x), 0, .{
                    .char = .{ .grapheme = hint[0..1], .width = 1 },
                    .style = .{ .dim = true },
                });
            }

            // Separator
            x += tab.name.len + 3;
            if (x < width and i < self.tabs.items.len - 1) {
                surface.writeCell(@intCast(x - 2), 0, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                });
            }
        }

        return surface;
    }
};
```

**Step 2: Build to verify**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 3: Commit**

```bash
git add src/tui/widgets/tabbar.zig
git commit -m "feat: add TabBar widget

- Create TabBar widget for displaying tabs at top of TUI
- Support tab selection, keyboard hints
- Draw tabs with highlighting for active tab"
```

---

## Task 3: Create PluginContainer Widget

**Files:**
- Create: `src/tui/widgets/plugin_container.zig`

**Step 1: Create PluginContainer widget**

```zig
// PluginContainer - Wraps plugin render with border and title
//
// Displays a plugin UI with a bordered box and title bar.

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");

pub const PluginContainer = struct {
    allocator: std.mem.Allocator,
    title: []const u8,
    plugin_widget: vxfw.Widget,

    pub fn init(allocator: std.mem.Allocator, title: []const u8, plugin_widget: vxfw.Widget) PluginContainer {
        return .{
            .allocator = allocator,
            .title = title,
            .plugin_widget = plugin_widget,
        };
    }

    pub fn widget(self: *PluginContainer) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = struct {
                fn handler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
                    const pc: *PluginContainer = @ptrCast(@alignCast(ptr));
                    // Forward events to plugin widget
                    if (pc.plugin_widget.eventHandler) |eh| {
                        try eh(pc.plugin_widget.userdata, ctx, event);
                    }
                }
            }.handler,
            .drawFn = struct {
                fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
                    const pc: *PluginContainer = @ptrCast(@alignCast(ptr));
                    return pc.draw(ctx);
                }
            }.draw,
        };
    }

    pub fn draw(self: *PluginContainer, ctx: vxfw.DrawContext) !vxfw.Surface {
        const max_size = ctx.max.size();
        const width = @min(max_size.width, 80);
        const height = @min(max_size.height, 20);

        // Create surface with padding for border
        var surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            .{ .width = @intCast(width), .height = @intCast(height) },
        );

        // Clear surface
        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        // Draw border box
        for (0..width) |i| {
            // Top border
            surface.writeCell(@intCast(i), 0, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .dim = true },
            });
            // Bottom border
            surface.writeCell(@intCast(i), height - 1, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .dim = true },
            });
        }
        for (1..height - 1) |i| {
            // Left border
            surface.writeCell(0, @intCast(i), .{
                .char = .{ .grapheme = "|", .width = 1 },
                .style = .{ .dim = true },
            });
            // Right border
            surface.writeCell(width - 1, @intCast(i), .{
                .char = .{ .grapheme = "|", .width = 1 },
                .style = .{ .dim = true },
            });
        }

        // Draw title in top border
        const title_start = @as(usize, @intCast((width - self.title.len) / 2));
        for (self.title, 0..) |c, i| {
            if (title_start + i < width) {
                surface.writeCell(@intCast(title_start + i), 0, .{
                    .char = .{ .grapheme = &[1]u8{c}, .width = 1 },
                    .style = .{ .bold = true },
                });
            }
        }

        // Draw plugin widget in inner area (if available)
        if (self.plugin_widget.drawFn) |drawFn| {
            if (width > 2 and height > 2) {
                const plugin_ctx = vxfw.DrawContext{
                    .arena = ctx.arena,
                    .max = .{
                        .width = width - 2,
                        .height = height - 2,
                    },
                };
                const plugin_surface = try drawFn(self.plugin_widget.userdata, plugin_ctx);

                // Copy plugin surface into our content area
                for (0..plugin_surface.size.height) |y| {
                    for (0..plugin_surface.size.width) |x| {
                        const cell = plugin_surface.buffer[y * plugin_surface.size.width + x];
                        if (x + 1 < width - 1 and y + 1 < height - 1) {
                            surface.writeCell(@intCast(x + 1), @intCast(y + 1), cell);
                        }
                    }
                }
            }
        }

        return surface;
    }
};
```

**Step 2: Build to verify**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 3: Commit**

```bash
git add src/tui/widgets/plugin_container.zig
git commit -m "feat: add PluginContainer widget

- Wrap plugin render with border and title
- Forward events to plugin widget
- Draw plugin UI inside bordered box"
```

---

## Task 4: Create TabPanelLayout

**Files:**
- Create: `src/tui/layout/tab_panel.zig`

**Step 1: Create TabPanelLayout**

```zig
// TabPanelLayout - Layout manager for tab modes
//
// Manages full view (Clear tab) and split view (plugin tabs).

const std = @import("std");
const vxfw = @import("vaxis").vxfw;

pub const TabPanelLayout = struct {
    allocator: std.mem.Allocator,
    mode: Mode,

    pub const Mode = enum {
        /// Full screen for Clear tab
        full,
        /// Split view for plugin tabs (left + right panels)
        split,
    };

    pub const LayoutResult = struct {
        /// Main widget (tree or table) surface
        main: vxfw.Surface,
        /// Plugin widget surface (only valid in split mode)
        plugin: ?vxfw.Surface = null,
    };

    pub fn init(allocator: std.mem.Allocator, mode: Mode) TabPanelLayout {
        return .{
            .allocator = allocator,
            .mode = mode,
        };
    }

    /// Layout widgets for current mode
    pub fn layout(
        self: *TabPanelLayout,
        ctx: vxfw.DrawContext,
        main_widget: vxfw.Widget,
        plugin_widget: ?vxfw.Widget,
    ) !LayoutResult {
        return switch (self.mode) {
            .full => self.layoutFull(ctx, main_widget),
            .split => self.layoutSplit(ctx, main_widget, plugin_widget),
        };
    }

    fn layoutFull(self: *TabPanelLayout, ctx: vxfw.DrawContext, widget: vxfw.Widget) !LayoutResult {
        _ = self;
        const max = ctx.max.size();

        var surface = try vxfw.Surface.init(
            ctx.arena,
            widget,
            .{ .width = max.width, .height = max.height },
        );

        // Clear and forward to widget's draw function
        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        if (widget.drawFn) |drawFn| {
            const widget_surface = try drawFn(widget.userdata, ctx);
            // Copy widget surface
            for (0..widget_surface.size.height) |y| {
                for (0..widget_surface.size.width) |x| {
                    const cell = widget_surface.buffer[y * widget_surface.size.width + x];
                    if (x < surface.size.width and y < surface.size.height) {
                        surface.buffer[y * surface.size.width + x] = cell;
                    }
                }
            }
        }

        return .{ .main = surface };
    }

    fn layoutSplit(
        self: *TabPanelLayout,
        ctx: vxfw.DrawContext,
        main_widget: vxfw.Widget,
        plugin_widget: ?vxfw.Widget,
    ) !LayoutResult {
        _ = self;
        const max = ctx.max.size();

        // Split: 30% left, remaining right for plugin
        const left_width = max.width / 3;
        const right_width = max.width - left_width;

        // Layout main widget in left panel
        var main_surface = try vxfw.Surface.init(
            ctx.arena,
            main_widget,
            .{ .width = left_width, .height = max.height },
        );

        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(main_surface.buffer, base_cell);

        const left_ctx = vxfw.DrawContext{
            .arena = ctx.arena,
            .max = .{ .width = left_width, .height = max.height },
        };

        if (main_widget.drawFn) |drawFn| {
            const widget_surface = try drawFn(main_widget.userdata, left_ctx);
            for (0..widget_surface.size.height) |y| {
                for (0..widget_surface.size.width) |x| {
                    const cell = widget_surface.buffer[y * widget_surface.size.width + x];
                    if (x < main_surface.size.width and y < main_surface.size.height) {
                        main_surface.buffer[y * main_surface.size.width + x] = cell;
                    }
                }
            }
        }

        // Layout plugin in right panel if provided
        var plugin_surface: ?vxfw.Surface = null;
        if (plugin_widget) |pw| {
            var ps = try vxfw.Surface.init(
                ctx.arena,
                pw,
                .{ .width = right_width, .height = max.height },
            );
            @memset(ps.buffer, base_cell);

            const right_ctx = vxfw.DrawContext{
                .arena = ctx.arena,
                .max = .{ .width = right_width, .height = max.height },
            };

            if (pw.drawFn) |drawFn| {
                const pws = try drawFn(pw.userdata, right_ctx);
                for (0..pws.size.height) |y| {
                    for (0..pws.size.width) |x| {
                        const cell = pws.buffer[y * pws.size.width + x];
                        if (x < ps.size.width and y < ps.size.height) {
                            ps.buffer[y * ps.size.width + x] = cell;
                        }
                    }
                }
            }
            plugin_surface = ps;
        }

        return .{ .main = main_surface, .plugin = plugin_surface };
    }
};
```

**Step 2: Build to verify**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 3: Commit**

```bash
git add src/tui/layout/tab_panel.zig
git add src/tui/layout/mod.zig  # Create mod.zig if needed
git commit -m "feat: add TabPanelLayout for tab modes

- Full mode: single widget takes entire screen
- Split mode: 30% left panel, remaining for plugin
- Handle widget composition and surface copying"
```

---

## Task 5: Integrate TabBar into Model

**Files:**
- Modify: `src/tui/model.zig`

**Step 1: Add TabBar imports and state**

Add to imports (around line 15):
```zig
const TabBar = @import("widgets/tabbar.zig").TabBar;
const PluginContainer = @import("widgets/plugin_container.zig").PluginContainer;
const TabPanelLayout = @import("layout/tab_panel.zig").TabPanelLayout;
```

Add to Model struct (after plugin_dialog around line 90):
```zig
tab_bar: TabBar,
active_tab_idx: usize = 0,  // 0 = Clear, 1+ = plugins
```

**Step 2: Initialize TabBar in Model.init**

After plugin_dialog creation (around line 170):
```zig
// Create TabBar
var tab_bar = TabBar.init(allocator);

// Add Clear tab (Alt+1)
try tab_bar.addTab("Clear", "1");

// Add plugin tabs for enabled plugins from config
if (config.plugins.enabled) |enabled_plugins| {
    const registry = @import("../plugin/registry.zig").getGlobalRegistry() orelse {
        return error.PluginRegistryNotAvailable;
    };

    for (enabled_plugins, 0..) |plugin_name, i| {
        if (registry.getPlugin(plugin_name)) |plugin| {
            const key_hint = try std.fmt.allocPrint(allocator, "{d}", .{i + 2});
            try tab_bar.addTab(plugin.name, key_hint);
        }
    }
}
```

Update Model construction (around line 190):
```zig
.tab_bar = tab_bar,
```

**Step 3: Add tab switching to Model**

Add function after `closePluginDialog` (around line 535):
```zig
/// Switch to a specific tab
pub fn switchTab(self: *Model, idx: usize) !void {
    if (idx == self.active_tab_idx) return;  // Already on this tab

    // Deactivate current plugin if leaving plugin tab
    if (self.active_tab_idx > 0) {
        // TODO: Call plugin deactivate based on lifecycle config
    }

    self.active_tab_idx = idx;
    self.tab_bar.setSelected(idx);

    // Activate new plugin if entering plugin tab
    if (idx > 0) {
        // TODO: Call plugin activate based on lifecycle config
    }
}
```

**Step 4: Build to verify**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 5: Commit**

```bash
git add src/tui/model.zig
git commit -m "feat: integrate TabBar into Model

- Add TabBar widget to Model state
- Initialize with Clear tab + enabled plugin tabs
- Add switchTab function for tab switching
- Track active_tab_idx for current selection"
```

---

## Task 6: Update TUI App Layout for TabBar

**Files:**
- Modify: `src/tui/app.zig`

**Step 1: Reserve top row for TabBar**

In main function, modify Vaxis initialization (around line 220):
```zig
// Reserve 1 row for TabBar at top
const tab_bar_height: u16 = 1;
const available_height = if (rows > tab_bar_height) rows - tab_bar_height else rows;
```

**Step 2: Add TabBar to widget tree**

Modify widget draw loop (around line 250):
```zig
// Draw TabBar at top
const tab_bar_surface = try tab_bar_widget.drawFn.?(tab_bar_widget.userdata, ctx);
for (0..tab_bar_surface.size.height) |y| {
    for (0..tab_bar_surface.size.width) |x| {
        const cell = tab_bar_surface.buffer[y * tab_bar_surface.size.width + x];
        try win.writeCell(x, @intCast(y), cell);
    }
}

// Offset remaining content by TabBar height
const content_offset_y = tab_bar_surface.size.height;
```

**Step 3: Update key handler for Alt+Number**

In Model.eventHandler, add Alt key detection (around line 660):
```zig
// Alt+Number for tab switching
if (key.matches('1', .{ .alt = true })) {
    try self.switchTab(0);
    ctx.consumeAndRedraw();
    return;
}
// Handle Alt+2 through Alt+9
for (2..9) |i| {
    const char = @as(u8, @intCast('0' + i));
    if (key.matches(char, .{ .alt = true })) {
        try self.switchTab(i - 1);
        ctx.consumeAndRedraw();
        return;
    }
}
```

**Step 4: Build and test**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 5: Commit**

```bash
git add src/tui/app.zig
git commit -m "feat: integrate TabBar into TUI layout

- Draw TabBar at top of screen
- Reserve 1 row for tabs, offset content below
- Add Alt+Number key bindings for tab switching"
```

---

## Task 7: Implement Plugin Lifecycle Management

**Files:**
- Modify: `src/plugin/manager.zig`

**Step 1: Add lifecycle enum and tracking**

Add to ActivePlugin struct (around line 30):
```zig
lifecycle: Lifecycle = .deactivate,

pub const Lifecycle = enum {
    /// Call deinit on leave, init on enter (default)
    deactivate,
    /// Keep initialized but don't render/events when not visible
    background,
    /// Always active regardless of visibility
    always_active,
};
```

**Step 2: Update activatePlugin to handle lifecycle**

Modify activatePlugin (around line 150):
```zig
// Check if already active
for (self.active_plugins.items) |*p| {
    if (std.mem.eql(u8, p.plugin.name, name)) {
        // Already active, just bring to front
        p.state = .active;
        return;
    }
}

// Get plugin from registry
const plugin = self.registry.?.getPlugin(name) orelse return error.PluginNotFound;

// Create user context for plugin
var user_context: ?*anyopaque = null;
if (plugin.init) |init_fn| {
    // Create plugin context
    const ctx = try self.allocator.create(PluginContext);
    ctx.* = PluginContext{
        .allocator = self.allocator,
        .hal_backend = self.hal_backend orelse return error.HalBackendNotAvailable,
    };
    user_context = ctx;

    // Call plugin init
    try init_fn(ctx);
}

// Add to active list
try self.active_plugins.append(self.allocator, .{
    .plugin = plugin,
    .state = .active,
    .user_context = user_context,
    .lifecycle = .deactivate,  // TODO: Load from config
});
```

**Step 3: Add deactivatePlugin function**

Add after activatePlugin:
```zig
pub fn deactivatePlugin(self: *PluginManager, name: []const u8) !void {
    for (self.active_plugins.items, 0..) |*p, i| {
        if (std.mem.eql(u8, p.plugin.name, name)) {
            // Call plugin deinit
            if (p.plugin.deinit) |deinit_fn| {
                if (p.user_context) |ctx| {
                    const plugin_ctx: *PluginContext = @ptrCast(@alignCast(ctx));
                    deinit_fn(plugin_ctx);
                    self.allocator.destroy(plugin_ctx);
                }
            }

            // Remove from active list
            _ = self.active_plugins.orderedRemove(i);
            return;
        }
    }
    return error.PluginNotActive;
}
```

**Step 4: Build to verify**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 5: Commit**

```bash
git add src/plugin/manager.zig
git commit -m "feat: add plugin lifecycle management

- Add lifecycle enum (deactivate/background/always_active)
- Update activatePlugin to call plugin.init
- Add deactivatePlugin to call plugin.deinit
- Track user context per active plugin"
```

---

## Task 8: Connect Tab Switching to Plugin Lifecycle

**Files:**
- Modify: `src/tui/model.zig`

**Step 1: Complete switchTab implementation**

Replace TODO comments in switchTab (around line 540):
```zig
/// Switch to a specific tab
pub fn switchTab(self: *Model, idx: usize) !void {
    if (idx == self.active_tab_idx) return;

    const manager = @import("../plugin/manager.zig").getGlobalPluginManager() orelse {
        return error.PluginManagerNotAvailable;
    };

    // Get plugin names from config
    const plugin_names = self.config.plugins.enabled orelse &[_][]const u8{};

    // Deactivate current plugin if leaving plugin tab
    if (self.active_tab_idx > 0 and self.active_tab_idx - 1 < plugin_names.len) {
        const old_plugin = plugin_names[self.active_tab_idx - 1];
        manager.deactivatePlugin(old_plugin) catch |err| {
            std.log.err("Failed to deactivate plugin '{s}': {}", .{old_plugin, err});
        };
    }

    self.active_tab_idx = idx;
    self.tab_bar.setSelected(idx);

    // Activate new plugin if entering plugin tab
    if (idx > 0 and idx - 1 < plugin_names.len) {
        const new_plugin = plugin_names[idx - 1];
        manager.activatePlugin(new_plugin) catch |err| {
            std.log.err("Failed to activate plugin '{s}': {}", .{new_plugin, err});
        };
    }
}
```

**Step 2: Build to verify**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 3: Commit**

```bash
git add src/tui/model.zig
git commit -m "feat: connect tab switching to plugin lifecycle

- Call deactivatePlugin when leaving plugin tab
- Call activatePlugin when entering plugin tab
- Handle errors gracefully with logging"
```

---

## Task 9: Update haltune.toml Example

**Files:**
- Modify: `haltune.toml`

**Step 1: Add plugins section**

Append to haltune.toml:
```toml
[plugins]
# Which plugins appear as tabs in the tabbar
enabled = ["velocity_control", "trapvel_control"]
```

**Step 2: Commit**

```bash
git add haltune.toml
git commit -m "docs: add plugins configuration example to haltune.toml"
```

---

## Task 10: Remove Old Plugin Dialog

**Files:**
- Modify: `src/tui/model.zig`, `src/tui/app.zig`

**Step 1: Remove plugin dialog from Model**

Remove `plugin_dialog` field from Model struct (around line 85).

**Step 2: Remove Ctrl+O handler**

Remove plugin dialog key handler (around line 664-677).

**Step 3: Update deinit**

Remove plugin_dialog.deinit() call (around line 300).

**Step 4: Build and test**

Run: `zig build -Dskip-hal-link=true`
Expected: No errors

**Step 5: Commit**

```bash
git add src/tui/model.zig src/tui/app.zig
git commit -m "refactor: remove modal plugin dialog

- Remove PluginDialog widget from Model
- Remove Ctrl+O key binding for dialog
- Tabbar now handles plugin activation"
```

---

## Testing Checklist

After implementation, verify:

1. **TabBar appears at top** with Clear tab + enabled plugin tabs
2. **Alt+1** switches to Clear tab (full screen)
3. **Alt+2, Alt+3** switch to plugin tabs (split view)
4. **Ctrl+T** toggles left panel between TreeView and DataTable
5. **Plugin init/deinit** called on tab switch
6. **haltune.toml plugins.enabled** controls which tabs appear
7. **No crash** when switching tabs rapidly
8. **Plugin UI** appears in right panel with border and title

Run manual test on laura with LinuxCNC running.
