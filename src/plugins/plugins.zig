// Plugin registration
//
// This module registers all available plugins with the global plugin registry.
// Import this module after initializing the global registry to register all plugins.

const std = @import("std");
const registry = @import("../plugin/registry.zig");

// Import all available plugins
const velocity_control = @import("velocity_control.zig");
const trapvel_control = @import("trapvel_control.zig");

/// Register all available plugins with the global registry
///
/// This should be called after initGlobalRegistry() to make all plugins
/// available for activation.
pub fn registerAllPlugins(allocator: std.mem.Allocator) !void {
    try registry.registerPlugin(&velocity_control.velocity_control_plugin, allocator);
    try registry.registerPlugin(&trapvel_control.trapvel_control_plugin, allocator);
}

/// Get a list of all available plugin names
pub fn getAvailablePluginNames(allocator: std.mem.Allocator) ![][]const u8 {
    const registry_ptr = registry.getGlobalRegistry() orelse return error.RegistryNotInitialized;

    const plugins = registry_ptr.getAllPlugins();
    const names = try allocator.alloc([]const u8, plugins.len);

    for (plugins, 0..) |plugin, i| {
        names[i] = try allocator.dupe(u8, plugin.name);
    }

    return names;
}
