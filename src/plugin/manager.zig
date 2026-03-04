// Plugin Manager - handles plugin lifecycle and dispatches events
//
// This module manages the runtime lifecycle of plugins:
// - Initializing plugins when activated
// - Deinitializing plugins when deactivated
// - Dispatching events to active plugins
// - Providing rendering context to plugins
//
// Plugins use HalBackend for all HAL operations - backend abstraction handles
// routing to local or remote HAL.

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const interface = @import("interface.zig");
const registry = @import("registry.zig");

// Import backend via module name (manager.zig is imported from root module context)
const HalBackend = @import("backend").HalBackend;

/// Plugin state - tracks whether a plugin is active
pub const PluginState = enum {
    /// Plugin is loaded but not active
    inactive,
    /// Plugin is active and receiving events
    active,
};

/// Plugin lifecycle mode - determines when plugin stays initialized
pub const Lifecycle = enum {
    /// Deinitialize when leaving tab (default)
    deactivate,
    /// Keep initialized in background (receives no events)
    background,
    /// Always active regardless of tab switching
    always_active,
};

/// Active plugin instance
pub const ActivePlugin = struct {
    /// Pointer to the plugin definition
    plugin: *const interface.Plugin,

    /// Current state
    state: PluginState = .inactive,

    /// User context allocated during init (for plugin-specific state)
    user_context: ?*anyopaque = null,

    /// Lifecycle mode - when to deinitialize
    lifecycle: Lifecycle = .deactivate,
};

/// Plugin Manager - manages active plugins and dispatches events
pub const PluginManager = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Reference to the plugin registry
    registry: *registry.PluginRegistry,

    /// HAL backend (null = no HAL available)
    hal_backend: ?*HalBackend = null,

    /// All active plugins
    active_plugins: std.ArrayList(ActivePlugin),

    /// Currently focused plugin (index into active_plugins)
    focused_plugin: ?usize = null,

    /// Initialize the plugin manager
    pub fn init(
        allocator: std.mem.Allocator,
        reg: *registry.PluginRegistry,
        backend: ?*HalBackend,
    ) PluginManager {
        return .{
            .allocator = allocator,
            .registry = reg,
            .hal_backend = backend,
            .active_plugins = std.ArrayList(ActivePlugin).initCapacity(allocator, 0) catch unreachable,
        };
    }

    /// Set the HAL backend (can be called after init if backend created later)
    pub fn setBackend(self: *PluginManager, backend: *HalBackend) void {
        self.hal_backend = backend;
    }

    /// Clean up the plugin manager
    pub fn deinit(self: *PluginManager) void {
        // Deactivate all active plugins
        for (self.active_plugins.items) |*plugin| {
            if (plugin.state == .active) {
                plugin.plugin.deinit();
            }
            // Clean up user context if allocated
            if (plugin.user_context) |ctx| {
                const plugin_ctx: *interface.PluginContext = @ptrCast(@alignCast(ctx));
                self.allocator.destroy(plugin_ctx);
            }
        }
        self.active_plugins.deinit(self.allocator);
    }

    /// Activate a plugin by name
    pub fn activatePlugin(self: *PluginManager, name: []const u8) !void {
        // Check if already active
        for (self.active_plugins.items, 0..) |*p, i| {
            if (std.mem.eql(u8, p.plugin.name, name)) {
                if (p.state == .active) {
                    // Already active - just set as focused
                    self.focused_plugin = i;
                    return;
                }
                p.state = .active;
                self.focused_plugin = i;
                return;
            }
        }

        const plugin = self.registry.getPlugin(name) orelse return error.PluginNotFound;

        // Create and store user context for this plugin
        var user_context: ?*anyopaque = null;

        // Allocate PluginContext to store for later use
        const ctx = try self.allocator.create(interface.PluginContext);
        ctx.* = interface.PluginContext{
            .allocator = self.allocator,
            .backend = self.hal_backend,
            .log = logInfo,
            .log_err = logError,
        };
        user_context = ctx;

        // Call plugin.init with the context
        try plugin.init(ctx.*);

        // Add to active list
        try self.active_plugins.append(self.allocator, .{
            .plugin = plugin,
            .state = .active,
            .user_context = user_context,
            .lifecycle = .deactivate,
        });

        // Set as focused plugin
        self.focused_plugin = self.active_plugins.items.len - 1;

        std.log.info("Activated plugin: {s}, focused_plugin={any}, active_count={d}",
            .{name, self.focused_plugin, self.active_plugins.items.len});
    }

    /// Deactivate a plugin by name
    pub fn deactivatePlugin(self: *PluginManager, name: []const u8) !void {
        for (self.active_plugins.items, 0..) |*plugin, idx| {
            if (std.mem.eql(u8, plugin.plugin.name, name)) {
                if (plugin.state == .active) {
                    plugin.plugin.deinit();

                    // Clean up user context if allocated
                    if (plugin.user_context) |ctx| {
                        const plugin_ctx: *interface.PluginContext = @ptrCast(@alignCast(ctx));
                        self.allocator.destroy(plugin_ctx);
                    }
                }
                // Remove from active plugins list
                _ = self.active_plugins.swapRemove(idx);
                // Clear focused plugin if needed
                if (self.focused_plugin) |focused| {
                    if (focused == idx) {
                        self.focused_plugin = null;
                    } else if (focused > idx) {
                        self.focused_plugin = focused - 1;
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

    /// Get widget for the focused plugin (null if no widget available)
    pub fn getFocusedPluginWidget(self: *const PluginManager) ?vxfw.Widget {
        const focused = self.focused_plugin orelse {
            std.log.info("getFocusedPluginWidget: focused_plugin is null", .{});
            return null;
        };
        const plugin = &self.active_plugins.items[focused];
        std.log.info("getFocusedPluginWidget: focused={d}, plugin={s}, has_widget={any}",
            .{focused, plugin.plugin.name, plugin.plugin.getWidget != null});

        if (plugin.plugin.getWidget) |get_widget_fn| {
            return get_widget_fn();
        }
        return null;
    }

    /// Get widget for a plugin by name (null if plugin not found or has no widget)
    pub fn getPluginWidgetByName(self: *const PluginManager, name: []const u8) ?vxfw.Widget {
        for (self.active_plugins.items) |plugin| {
            if (std.mem.eql(u8, plugin.plugin.name, name)) {
                if (plugin.plugin.getWidget) |get_widget_fn| {
                    return get_widget_fn();
                }
                return null;
            }
        }
        return null;
    }
};

/// Log function passed to plugins (info level)
fn logInfo(level: []const u8, msg: []const u8) void {
    _ = level;
    std.log.info("{s}", .{msg});
}

/// Log function passed to plugins (error level)
fn logError(level: []const u8, msg: []const u8) void {
    _ = level;
    std.log.err("{s}", .{msg});
}

/// Global plugin manager instance
var global_plugin_manager: ?*PluginManager = null;

/// Set the global plugin manager
pub fn setGlobalPluginManager(manager: *PluginManager) void {
    global_plugin_manager = manager;
}

/// Get the global plugin manager
pub fn getGlobalPluginManager() ?*PluginManager {
    return global_plugin_manager;
}
