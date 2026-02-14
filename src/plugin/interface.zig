// Plugin interface for haltune extensibility
//
// This module defines the plugin API that allows extending haltune with
// domain-specific workflows like PID tuning, velocity testing, and machine calibration.
//
// Design principles:
// - Compile-time registration only (no dynamic loading for MVP)
// - Read-only HAL access in render() phase
// - Arena allocator for temporary strings in render()
// - Event-driven with explicit return values

const std = @import("std");
const vxfw = @import("vaxis").vxfw;

/// Plugin context - provides read-only access to application state
///
/// The context is passed to all plugin lifecycle methods and provides
/// controlled access to application functionality without giving plugins
/// direct access to internal state.
pub const PluginContext = struct {
    /// Memory allocator for plugin use
    allocator: std.mem.Allocator,

    /// User context pointer (for plugin-specific state)
    user_context: ?*anyopaque = null,

    /// Get current HAL value (read-only)
    ///
    /// Returns the current value for a HAL item by name.
    /// Returns null if item doesn't exist or on error.
    getValue: *const fn (*const PluginContext, []const u8) ?HalValue,

    /// Subscribe to HAL value changes
    ///
    /// Registers a callback to be invoked when a HAL value changes.
    /// The callback receives the item name and new value.
    subscribe: *const fn (*const PluginContext, []const u8, *const fn ([]const u8, HalValue) void) anyerror!void,

    /// Log message at info level
    logInfo: *const fn (*const PluginContext, []const u8) void,

    /// Log message at error level
    logError: *const fn (*const PluginContext, []const u8) void,
};

/// Plugin event - events sent to plugins
///
/// Plugins receive events through their handleEvent() method and can
/// choose to handle or propagate each event.
pub const PluginEvent = union(enum) {
    /// User pressed a key
    key_press: struct {
        codepoint: u21,
        mods: vxfw.Key.Modifiers,
    },

    /// Timer tick (for periodic updates)
    tick: struct {
        timestamp: u64,
    },

    /// HAL value changed
    hal_change: struct {
        name: []const u8,
        old_value: ?HalValue,
        new_value: HalValue,
    },

    /// Plugin gained focus
    focus: void,

    /// Plugin lost focus
    blur: void,
};

/// HAL value type (simplified for plugin API)
///
/// A simplified version of the full HalValue union that plugins
/// can use without importing the HAL module.
pub const HalValue = union(enum) {
    /// Boolean value (HAL_BIT pins/signals)
    bit: bool,

    /// Floating-point value (HAL_FLOAT pins/signals)
    float: f64,

    /// Signed 32-bit integer (HAL_S32 pins/signals)
    s32: i32,

    /// Unsigned 32-bit integer (HAL_U32 pins/signals)
    u32: u32,
};

/// Plugin interface - all plugins must implement this
///
/// Every plugin must provide a const of this type with all
/// required function pointers filled in.
pub const Plugin = struct {
    /// Plugin name (must be unique)
    name: []const u8,

    /// Plugin version
    version: []const u8,

    /// Plugin description
    description: []const u8,

    /// Initialize plugin - called when plugin is activated
    ///
    /// This is called once when the plugin is first activated.
    /// Plugins should allocate resources and subscribe to HAL values here.
    ///
    /// Returns error if initialization fails (plugin won't be activated).
    init: *const fn (*PluginContext) anyerror!void,

    /// Deinitialize plugin - called when plugin is deactivated
    ///
    /// This is called when the plugin is being deactivated or haltune
    /// is shutting down. Plugins must free all resources and unsubscribe
    /// from HAL value changes.
    deinit: *const fn (*PluginContext) void,

    /// Render plugin UI - called during TUI render cycle
    ///
    /// This is called every time the UI is redrawn. Plugins can use
    /// the vxfw.Context to draw their interface. Use the arena allocator
    /// for temporary strings as it's freed each frame.
    ///
    /// Returns error if rendering fails.
    render: *const fn (*PluginContext, vxfw.Context) anyerror!void,

    /// Handle event - called for keyboard/timer events
    ///
    /// This is called for each event that occurs. Plugins should return
    /// true if they handled the event (stops propagation) or false to
    /// let other plugins handle it.
    ///
    /// Returns true if event was handled, false to propagate.
    handleEvent: *const fn (*PluginContext, PluginEvent) bool,
};
