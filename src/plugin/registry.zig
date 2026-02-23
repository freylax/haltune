// Plugin Registry - compile-time plugin registration
//
// This module provides a central registry of all available plugins.
// Plugins are registered at compile time using the registerPlugin function.
//
// Usage:
//   1. Import your plugin module
//   2. Call plugin_registry.registerPlugin(&my_plugin.plugin)
//   3. Plugin manager will initialize it when activated

const std = @import("std");
const interface = @import("interface.zig");

/// Plugin registry - stores all registered plugins
pub const PluginRegistry = struct {
    /// List of all registered plugins
    plugins: std.ArrayList(*const interface.Plugin),

    /// Map from plugin name to plugin pointer
    plugin_map: std.StringHashMap(*const interface.Plugin),

    /// Initialize the registry
    pub fn init(allocator: std.mem.Allocator) PluginRegistry {
        return .{
            .plugins = std.ArrayList(*const interface.Plugin).initCapacity(allocator, 0) catch unreachable,
            .plugin_map = std.StringHashMap(*const interface.Plugin).init(allocator),
        };
    }

    /// Clean up the registry
    pub fn deinit(self: *PluginRegistry, allocator: std.mem.Allocator) void {
        self.plugins.deinit(allocator);
        self.plugin_map.deinit();
    }

    /// Register a plugin
    ///
    /// Returns error if a plugin with the same name is already registered
    pub fn registerPlugin(self: *PluginRegistry, plugin: *const interface.Plugin, allocator: std.mem.Allocator) !void {
        if (self.plugin_map.get(plugin.name)) |_| {
            std.log.err("Plugin '{s}' already registered", .{plugin.name});
            return error.PluginAlreadyRegistered;
        }

        try self.plugins.append(allocator, plugin);
        try self.plugin_map.put(plugin.name, plugin);
        std.log.info("Registered plugin: {s} v{s}", .{ plugin.name, plugin.version });
    }

    /// Get a plugin by name
    pub fn getPlugin(self: *const PluginRegistry, name: []const u8) ?*const interface.Plugin {
        return self.plugin_map.get(name);
    }

    /// Get all registered plugins
    pub fn getAllPlugins(self: *const PluginRegistry) []const *const interface.Plugin {
        return self.plugins.items;
    }

    /// Count of registered plugins
    pub fn count(self: *const PluginRegistry) usize {
        return self.plugins.items.len;
    }
};

/// Global plugin registry instance
/// Initialized at startup, populated by plugin modules
var global_registry: PluginRegistry = undefined;
var global_registry_allocator: ?std.mem.Allocator = null;

/// Get the global plugin registry
pub fn getGlobalRegistry() ?*PluginRegistry {
    if (global_registry_allocator == null) return null;
    return &global_registry;
}

/// Initialize the global plugin registry
pub fn initGlobalRegistry(allocator: std.mem.Allocator) !void {
    global_registry = PluginRegistry.init(allocator);
    global_registry_allocator = allocator;
    std.log.info("Global plugin registry initialized", .{});
}

/// Cleanup global plugin registry
pub fn deinitGlobalRegistry() void {
    if (global_registry_allocator) |allocator| {
        global_registry.deinit(allocator);
        global_registry_allocator = null;
    }
}

/// Register a plugin with the global registry
pub fn registerPlugin(plugin: *const interface.Plugin, allocator: std.mem.Allocator) !void {
    const registry = getGlobalRegistry() orelse return error.RegistryNotInitialized;
    try registry.registerPlugin(plugin, allocator);
}
