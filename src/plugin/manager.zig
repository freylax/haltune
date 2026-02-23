// Plugin Manager - handles plugin lifecycle and dispatches events
//
// This module manages the runtime lifecycle of plugins:
// - Initializing plugins when activated
// - Deinitializing plugins when deactivated
// - Dispatching events to active plugins
// - Providing rendering context to plugins
//
// Plugins use HAL FFI directly - HAL is the communication channel.

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const interface = @import("interface.zig");
const registry = @import("registry.zig");

/// Plugin state - tracks whether a plugin is active
pub const PluginState = enum {
    /// Plugin is loaded but not active
    inactive,
    /// Plugin is active and receiving events
    active,
};

/// Active plugin instance
pub const ActivePlugin = struct {
    /// Pointer to the plugin definition
    plugin: *const interface.Plugin,

    /// Current state
    state: PluginState = .inactive,
};

/// Plugin Manager - manages active plugins and dispatches events
pub const PluginManager = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Reference to the plugin registry
    registry: *registry.PluginRegistry,

    /// All active plugins
    active_plugins: std.ArrayList(ActivePlugin),

    /// Currently focused plugin (index into active_plugins)
    focused_plugin: ?usize = null,

    /// Initialize the plugin manager
    pub fn init(
        allocator: std.mem.Allocator,
        reg: *registry.PluginRegistry,
    ) PluginManager {
        return .{
            .allocator = allocator,
            .registry = reg,
            .active_plugins = std.ArrayList(ActivePlugin).initCapacity(allocator, 0) catch unreachable,
        };
    }

    /// Clean up the plugin manager
    pub fn deinit(self: *PluginManager) void {
        // Deactivate all active plugins
        for (self.active_plugins.items) |*plugin| {
            if (plugin.state == .active) {
                plugin.plugin.deinit();
            }
        }
        self.active_plugins.deinit(self.allocator);
    }

    /// Activate a plugin by name
    pub fn activatePlugin(self: *PluginManager, name: []const u8) !void {
        const plugin = self.registry.getPlugin(name) orelse return error.PluginNotFound;

        // Check if already active
        for (self.active_plugins.items) |*p| {
            if (std.mem.eql(u8, p.plugin.name, name)) {
                if (p.state == .active) return; // Already active
                p.state = .active;
                p.plugin.init(self.allocator, self.logInfo, self.logError) catch |err| {
                    std.log.err("Failed to initialize plugin '{s}': {}", .{name, err});
                    return err;
                };
                return;
            }
        }

        // Create new active plugin
        const active_plugin = ActivePlugin{
            .plugin = plugin,
        };

        try self.active_plugins.append(active_plugin);

        // Initialize the plugin
        const last_idx = self.active_plugins.items.len - 1;
        self.active_plugins.items[last_idx].plugin.init(
            self.allocator,
            self.logInfo,
            self.logError,
        ) catch |err| {
            std.log.err("Failed to initialize plugin '{s}': {}", .{name, err});
            _ = self.active_plugins.pop();
            return err;
        };

        self.active_plugins.items[last_idx].state = .active;

        std.log.info("Activated plugin: {s}", .{name});
    }

    /// Deactivate a plugin by name
    pub fn deactivatePlugin(self: *PluginManager, name: []const u8) !void {
        for (self.active_plugins.items, 0..) |plugin, idx| {
            if (std.mem.eql(u8, plugin.plugin.name, name)) {
                if (plugin.state == .active) {
                    plugin.plugin.deinit();
                    plugin.state = .inactive;
                }
                if (self.focused_plugin) |focused| {
                    if (focused == idx) {
                        self.focused_plugin = null;
                    }
                }
                std.log.info("Deactivated plugin: {s}", .{name});
                return;
            }
        }
        return error.PluginNotFound;
    }

    /// Get list of active plugin names
    pub fn getActivePlugins(self: *const PluginManager, allocator: std.mem.Allocator) ![][]const u8 {
        const names = try allocator.alloc([]const u8, self.active_plugins.items.len);

        for (self.active_plugins.items, 0..) |plugin, i| {
            names[i] = try allocator.dupe(u8, plugin.plugin.name);
        }

        return names;
    }

    /// Dispatch an event to the focused plugin
    /// Returns true if event was handled
    pub fn dispatchEvent(self: *PluginManager, event: interface.PluginEvent) bool {
        const focused = self.focused_plugin orelse return false;
        const plugin = &self.active_plugins.items[focused];

        if (plugin.state != .active) return false;

        return plugin.plugin.handleEvent(event);
    }

    /// Render all active plugins
    pub fn render(self: *PluginManager, ctx: vxfw.DrawContext) !void {
        // For now, only render the focused plugin
        // In the future, we might support multiple visible plugins
        const focused = self.focused_plugin orelse return;
        const plugin = &self.active_plugins.items[focused];

        if (plugin.state != .active) return;

        if (plugin.plugin.render) |render_fn| {
            try render_fn(ctx);
        }
    }

    /// Set the focused plugin by index
    pub fn setFocusedPlugin(self: *PluginManager, idx: usize) !void {
        if (idx >= self.active_plugins.items.len) return error.InvalidIndex;
        self.focused_plugin = idx;

        // Send focus event to newly focused plugin
        const plugin = &self.active_plugins.items[idx];
        _ = plugin.plugin.handleEvent(.{ .focus = {} });
    }

    /// Set the focused plugin by name
    pub fn setFocusedPluginByName(self: *PluginManager, name: []const u8) !void {
        for (self.active_plugins.items, 0..) |plugin, i| {
            if (std.mem.eql(u8, plugin.plugin.name, name)) {
                self.focused_plugin = i;
                _ = plugin.plugin.handleEvent(.{ .focus = {} });
                return;
            }
        }
        return error.PluginNotFound;
    }

    /// Get the currently focused plugin (null if none)
    pub fn getFocusedPlugin(self: *const PluginManager) ?*const interface.Plugin {
        const focused = self.focused_plugin orelse return null;
        return self.active_plugins.items[focused].plugin;
    }

    /// Log function passed to plugins (info level)
    fn logInfo(comptime level: []const u8, msg: []const u8) void {
        _ = level;
        std.log.info("{s}", .{msg});
    }

    /// Log function passed to plugins (error level)
    fn logError(comptime level: []const u8, msg: []const u8) void {
        _ = level;
        std.log.err("{s}", .{msg});
    }
};
