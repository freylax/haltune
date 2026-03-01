// Plugin interface for haltune extensibility
//
// This module defines the plugin API that allows extending haltune with
// domain-specific workflows like PID tuning, velocity testing, and machine calibration.
//
// Design principles:
// - Compile-time registration only (no dynamic loading for MVP)
// - Plugins use HalBackend for all HAL operations (supports local and remote)
// - HAL is the communication channel - backend abstraction handles routing
// - Plugin interface is minimal: logging + lifecycle hooks

const std = @import("std");
const vxfw = @import("vaxis").vxfw;

// Import backend module (defined in build.zig)
const HalBackend = @import("backend").HalBackend;
const HalValue = @import("backend").HalValue;
const PinType = @import("backend").PinType;
const PinDir = @import("backend").PinDir;

/// Log function type passed to plugins
///
/// Plugins use this for logging instead of std.log directly,
///  allowing haltune to capture/format log output.
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

/// Plugin context - passed to plugin init with HAL backend access
pub const PluginContext = struct {
    allocator: std.mem.Allocator,
    backend: ?*HalBackend,
    log: LogFn,
    log_err: LogFn,

    /// Helper: Log info message
    pub fn logInfo(self: PluginContext, msg: []const u8, msg2: []const u8) void {
        _ = msg; // Prefix not used in simple log
        self.log("info", msg2);
    }

    /// Helper: Log error message
    pub fn logError(self: PluginContext, msg: []const u8, msg2: []const u8) void {
        _ = msg; // Prefix not used in simple log
        self.log_err("error", msg2);
    }

    /// Create a HAL component (uses backend if available)
    pub fn initComponent(self: PluginContext, name: []const u8) !c_int {
        if (self.backend) |backend| {
            return backend.initComponent(name);
        }
        return error.HalNotAvailable;
    }

    /// Mark component as ready
    pub fn readyComponent(self: PluginContext, comp_id: c_int) !void {
        if (self.backend) |backend| {
            return backend.readyComponent(comp_id);
        }
        return error.HalNotAvailable;
    }

    /// Exit a HAL component
    pub fn exitComponent(self: PluginContext, comp_id: c_int) void {
        if (self.backend) |backend| {
            backend.exitComponent(comp_id);
        }
    }

    /// Set pin value
    pub fn setPin(self: PluginContext, name: []const u8, value: HalValue) !void {
        if (self.backend) |backend| {
            return backend.setPinValue(name, value);
        }
        return error.HalNotAvailable;
    }

    /// Get pin value
    pub fn getPin(self: PluginContext, name: []const u8) !HalValue {
        if (self.backend) |backend| {
            return backend.getPinValue(name);
        }
        return error.HalNotAvailable;
    }

    /// Create a signal
    pub fn createSignal(self: PluginContext, name: []const u8, pin_type: PinType) !void {
        if (self.backend) |backend| {
            return backend.createSignal(name, pin_type);
        }
        return error.HalNotAvailable;
    }

    /// Link pin to signal
    pub fn linkPin(self: PluginContext, pin_name: []const u8, sig_name: []const u8) !void {
        if (self.backend) |backend| {
            return backend.linkPin(pin_name, sig_name);
        }
        return error.HalNotAvailable;
    }

    /// Unlink pin from signal
    pub fn unlinkPin(self: PluginContext, pin_name: []const u8) !void {
        if (self.backend) |backend| {
            return backend.unlinkPin(pin_name);
        }
        return error.HalNotAvailable;
    }
};

/// Plugin interface - all plugins must implement this
///
/// Plugins use the PluginContext to access HAL (via backend).
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
    /// - Create HAL component via context.initComponent()
    /// - Create pins (managed internally by backend)
    /// - Wire pins to signals via context.linkPin()
    /// - Store state for later access
    ///
    /// The context provides access to the HAL backend (local or remote).
    init: *const fn (ctx: PluginContext) anyerror!void,

    /// Deinitialize plugin - called when plugin is deactivated
    ///
    /// Plugins should:
    /// - Unwire pins from signals
    /// - Exit HAL component via context.exitComponent()
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
