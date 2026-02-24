// Plugin Dialog - displays and manages available plugins
//
// This dialog shows:
// - List of all available plugins from the registry
// - Active/inactive status for each plugin
// - Activate/deactivate with Enter key
// - Close with q or Escape

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const registry_mod = @import("../../plugin/registry.zig");
const plugin_manager_mod = @import("../../plugin/manager.zig");

/// Plugin list dialog
pub const PluginDialog = struct {
    allocator: std.mem.Allocator,
    registry: *registry_mod.PluginRegistry,
    manager: ?*plugin_manager_mod.PluginManager,

    /// Dialog visibility
    visible: bool = false,

    /// Currently selected plugin index
    selected_idx: usize = 0,

    /// Scroll offset for plugin list
    scroll_offset: usize = 0,

    /// Height of the dialog content area
    content_height: usize = 10,

    /// Error message to display (null = no error)
    error_message: ?[]const u8 = null,

    /// Initialize a new PluginDialog
    pub fn init(
        allocator: std.mem.Allocator,
        registry: *registry_mod.PluginRegistry,
    ) PluginDialog {
        return .{
            .allocator = allocator,
            .registry = registry,
            .manager = null,
            .visible = false,
            .selected_idx = 0,
            .scroll_offset = 0,
            .content_height = 10,
            .error_message = null,
        };
    }

    /// Set the plugin manager (call after manager is created)
    pub fn setManager(self: *PluginDialog, manager: *plugin_manager_mod.PluginManager) void {
        self.manager = manager;
    }

    /// Clean up resources
    pub fn deinit(self: *PluginDialog) void {
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Open the dialog
    pub fn open(self: *PluginDialog) void {
        self.visible = true;
        self.selected_idx = 0;
        self.scroll_offset = 0;
        self.clearError();
    }

    /// Close the dialog
    pub fn close(self: *PluginDialog) void {
        self.visible = false;
    }

    /// Set an error message
    pub fn setError(self: *PluginDialog, msg: []const u8) !void {
        if (self.error_message) |old| {
            self.allocator.free(old);
        }
        self.error_message = try self.allocator.dupe(u8, msg);
    }

    /// Clear error message
    pub fn clearError(self: *PluginDialog) void {
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }
    }

    /// Handle key press events
    pub fn handleKey(self: *PluginDialog, key: vaxis.Key) !bool {
        if (!self.visible) return false;

        const plugin_count = self.registry.count();

        // q to close
        if (key.matches('q', .{})) {
            self.close();
            return true;
        }

        // Ctrl+O to close (toggle)
        if (key.matches('o', .{ .ctrl = true })) {
            self.close();
            return true;
        }

        // Navigation
        if (key.matches(vaxis.Key.up, .{})) {
            if (self.selected_idx > 0) {
                self.selected_idx -= 1;
                // Scroll up if needed
                if (self.selected_idx < self.scroll_offset) {
                    self.scroll_offset = self.selected_idx;
                }
            }
            return true;
        }

        if (key.matches(vaxis.Key.down, .{})) {
            if (self.selected_idx + 1 < plugin_count) {
                self.selected_idx += 1;
                // Scroll down if needed
                if (self.selected_idx >= self.scroll_offset + self.content_height) {
                    self.scroll_offset = self.selected_idx - self.content_height + 1;
                }
            }
            return true;
        }

        if (key.matches(vaxis.Key.page_up, .{})) {
            if (self.selected_idx > self.content_height) {
                self.selected_idx -= self.content_height;
            } else {
                self.selected_idx = 0;
            }
            if (self.selected_idx < self.scroll_offset) {
                self.scroll_offset = self.selected_idx;
            }
            return true;
        }

        if (key.matches(vaxis.Key.page_down, .{})) {
            if (self.selected_idx + self.content_height < plugin_count) {
                self.selected_idx += self.content_height;
            } else {
                self.selected_idx = if (plugin_count > 0) plugin_count - 1 else 0;
            }
            if (self.selected_idx >= self.scroll_offset + self.content_height) {
                self.scroll_offset = self.selected_idx - self.content_height + 1;
            }
            return true;
        }

        // Enter to toggle plugin activation
        if (key.matches(vaxis.Key.enter, .{})) {
            if (plugin_count == 0) return true;

            const plugin = self.registry.getPluginByIndex(self.selected_idx) orelse return true;
            const manager = self.manager orelse {
                try self.setError("Plugin manager not available");
                return true;
            };

            // Check if plugin is currently active
            const is_active = self.isPluginActive(plugin.name);

            if (is_active) {
                // Deactivate
                manager.deactivatePlugin(plugin.name) catch |err| {
                    try self.setError("Failed to deactivate plugin");
                    std.log.err("Failed to deactivate plugin '{s}': {}", .{ plugin.name, err });
                };
                self.clearError();
            } else {
                // Activate
                manager.activatePlugin(plugin.name) catch |err| {
                    try self.setError("Failed to activate plugin");
                    std.log.err("Failed to activate plugin '{s}': {}", .{ plugin.name, err });
                };
                self.clearError();
            }
            return true;
        }

        return false;
    }

    /// Check if a plugin is currently active
    fn isPluginActive(self: *const PluginDialog, name: []const u8) bool {
        const manager = self.manager orelse return false;
        for (manager.active_plugins.items) |*p| {
            if (std.mem.eql(u8, p.plugin.name, name) and p.state == .active) {
                return true;
            }
        }
        return false;
    }

    /// Draw the plugin dialog
    pub fn draw(self: *PluginDialog, ctx: vxfw.DrawContext, max_len: usize) !vxfw.Surface {
        const width = @min(max_len, 60);
        const max_height = ctx.max.height orelse 24;
        const height = @min(20, max_height - 4);

        // Store content height for scrolling
        self.content_height = if (height > 4) height - 4 else 10;

        // Create surface
        var surface = try vxfw.Surface.init(
            ctx.arena,
            makeWidget(self),
            .{ .width = @intCast(width), .height = @intCast(height) },
        );

        // Initialize with default cells
        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        const plugin_count = self.registry.count();

        // Draw simple ASCII border and title
        const title = "Available Plugins (Ctrl+O to close, q=quit)";

        // Title row
        for (title, 0..) |c, i| {
            if (i < width) surface.writeCell(@intCast(i), 0, .{
                .char = .{ .grapheme = &[1]u8{c}, .width = 1 },
                .style = .{ .bold = true },
            });
        }

        // Separator
        for (0..width) |i| {
            surface.writeCell(@intCast(i), 1, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{},
            });
        }

        // Draw plugin list
        const end_idx = @min(self.scroll_offset + self.content_height, plugin_count);
        for (self.scroll_offset..end_idx) |i| {
            const plugin = self.registry.getPluginByIndex(i) orelse continue;
            const is_active = self.isPluginActive(plugin.name);
            const is_selected = (i == self.selected_idx);
            const row = 3 + (i - self.scroll_offset);

            // Clear row
            for (0..width) |col| {
                surface.writeCell(@intCast(col), @intCast(row), if (is_selected) .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .reverse = true },
                } else base_cell);
            }

            // Selection indicator
            surface.writeCell(1, @intCast(row), .{
                .char = .{ .grapheme = if (is_selected) ">" else " ", .width = 1 },
                .style = if (is_selected) .{ .reverse = true } else .{},
            });

            // Status indicator
            const status = if (is_active) "[x]" else "[ ]";
            const status_style: vaxis.Style = if (is_active) .{ .fg = .{ .rgb = .{ 0, 255, 0 } } } else .{ .dim = true };
            for (status, 0..) |c, j| {
                surface.writeCell(@intCast(3 + j), @intCast(row), .{
                    .char = .{ .grapheme = &[1]u8{c}, .width = 1 },
                    .style = if (is_selected) .{ .reverse = true } else status_style,
                });
            }

            // Plugin name
            const name_start = 8;
            for (plugin.name, 0..) |c, j| {
                if (name_start + j >= width - 2) break;
                surface.writeCell(@intCast(name_start + j), @intCast(row), .{
                    .char = .{ .grapheme = &[1]u8{c}, .width = 1 },
                    .style = if (is_selected) .{ .reverse = true } else .{},
                });
            }

            // Version (if available)
            if (plugin.version.len > 0) {
                const ver_start = name_start + plugin.name.len + 2;
                const ver_str = try std.fmt.allocPrint(ctx.arena, "v{s}", .{plugin.version});
                for (ver_str, 0..) |c, j| {
                    if (ver_start + j >= width - 2) break;
                    surface.writeCell(@intCast(ver_start + j), @intCast(row), .{
                        .char = .{ .grapheme = &[1]u8{c}, .width = 1 },
                        .style = if (is_selected) .{ .reverse = true } else .{ .dim = true },
                    });
                }
            }
        }

        // Bottom help
        if (height > 5) {
            const help_row = @min(height - 2, 3 + @as(u16, @intCast(end_idx - self.scroll_offset)));
            const help = "Enter: Toggle | +/-: Navigate";
            for (help, 0..) |c, i| {
                if (i < width) surface.writeCell(@intCast(i), help_row, .{
                    .char = .{ .grapheme = &[1]u8{c}, .width = 1 },
                    .style = .{ .dim = true },
                });
            }
        }

        return surface;
    }
};

fn makeWidget(self: *PluginDialog) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = struct {
            fn handler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
                _ = ptr;
                _ = ctx;
                _ = event;
            }
        }.handler,
        .drawFn = struct {
            fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
                const dialog: *PluginDialog = @ptrCast(@alignCast(ptr));
                const max = ctx.max.size();
                return dialog.draw(ctx, @min(max.width, 60));
            }
        }.draw,
    };
}
