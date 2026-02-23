// Plugin interface for haltune extensibility
//
// This module defines the plugin API that allows extending haltune with
// domain-specific workflows like PID tuning, velocity testing, and machine calibration.
//
// Design principles:
// - Compile-time registration only (no dynamic loading for MVP)
// - Plugins use HAL FFI directly for all operations
// - HAL is the communication channel - no direct coupling to haltune
// - Plugin interface is minimal: logging + lifecycle hooks

const std = @import("std");
const vxfw = @import("vaxis").vxfw;

/// Log function type passed to plugins
///
/// Plugins use this for logging instead of std.log directly,
//  allowing haltune to capture/format log output.
pub const LogFn = *const fn ([]const u8, []const u8) void;

/// Plugin event - events sent to plugins
pub const PluginEvent = union(enum) {
    /// User pressed a key
    key_press: struct {
        codepoint: u21,
    },

    /// Timer tick (for periodic updates)
    tick: struct {
        timestamp: u64,
    },

    /// Plugin gained focus
    focus: void,

    /// Plugin lost focus
    blur: void,
};

/// Plugin interface - all plugins must implement this
///
/// Plugins import FFI modules directly (@import("ffi/component"), etc.)
/// to create HAL components, pins, and handle wiring.
pub const Plugin = struct {
    /// Plugin name (must be unique)
    name: []const u8,

    /// Plugin version
    version: []const u8,

    /// Plugin description
    description: []const u8,

    /// Initialize plugin - called when plugin is activated
    ///
    /// Plugins should:
    /// - Create HAL component via Component.init()
    /// - Create pins via component.newPin()
    /// - Wire pins to signals via pin.link()
    /// - Store pin handles for fast access
    ///
    /// The allocator is for plugin-managed memory only.
    /// HAL manages its own memory.
    init: *const fn (allocator: std.mem.Allocator, log: LogFn, log_err: LogFn) anyerror!void,

    /// Deinitialize plugin - called when plugin is deactivated
    ///
    /// Plugins should:
    /// - Unwire pins from signals
    /// - Exit HAL component via component.exit()
    /// - Free any allocated memory
    deinit: *const fn () void,

    /// Render plugin UI - called during TUI render cycle
    ///
    /// Optional - if null, plugin has no UI component.
    /// This is called every time the UI is redrawn.
    render: ?*const fn (ctx: vxfw.DrawContext) anyerror!void = null,

    /// Handle event - called for keyboard/timer events
    ///
    /// Returns true if event was handled, false to propagate.
    handleEvent: *const fn (event: PluginEvent) bool,
};
