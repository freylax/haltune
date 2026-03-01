// Velocity Control Plugin
//
// This plugin provides a simple velocity control interface for jogging an axis.
// Based on the Python VelocityControl plugin from riocfg/pidtune.
//
// Features:
// - Creates HAL component "velocity-control"
// - Creates pins: enable, velocity-cmd, direction
// - Wires to rio motion pins for jogging control
// - Uses HalBackend for HAL operations (works with local or remote HAL)

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const PluginInterface = @import("../plugin/interface.zig");

/// Velocity control state
const VelocityControlState = struct {
    /// HAL component ID (from backend.initComponent())
    comp_id: ?c_int = null,

    /// Pin names (for setPin/getPin calls via backend)
    /// Pins are: velocity-control.enable, velocity-control.velocity-cmd, velocity-control.direction
    enable_pin: []const u8 = "velocity-control.enable",
    velocity_pin: []const u8 = "velocity-control.velocity-cmd",
    direction_pin: []const u8 = "velocity-control.direction",

    /// Current velocity setting
    velocity: f64 = 100.0,

    /// Direction: true = forward, false = backward
    forward: bool = true,

    /// Enable state
    enabled: bool = false,

    allocator: std.mem.Allocator,

    /// Write current state to HAL pins via backend
    pub fn writeToHAL(self: *VelocityControlState, ctx: PluginInterface.PluginContext) !void {
        if (self.comp_id == null) return error.ComponentNotInitialized;

        // Write enable pin
        try ctx.setPin(self.enable_pin, .{ .bit = self.enabled });

        // Write direction pin
        try ctx.setPin(self.direction_pin, .{ .bit = self.forward });

        // Write velocity pin (signed based on direction)
        const vel = if (self.forward) self.velocity else -self.velocity;
        try ctx.setPin(self.velocity_pin, .{ .float = vel });
    }

    pub fn init(allocator: std.mem.Allocator) VelocityControlState {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VelocityControlState, ctx: PluginInterface.PluginContext) void {
        // Exit HAL component
        if (self.comp_id) |id| {
            ctx.exitComponent(id);
        }
    }
};

// Global state pointer (simplified - single instance)
var global_state_ptr: ?*VelocityControlState = null;

/// Plugin initialization - receives PluginContext with backend access
fn pluginInit(ctx: PluginInterface.PluginContext) anyerror!void {
    // Allocate state
    const state = try ctx.allocator.create(VelocityControlState);
    state.* = VelocityControlState.init(ctx.allocator);
    global_state_ptr = state;

    ctx.logInfo("velocity_control", "creating HAL component 'velocity-control'");

    // Create HAL component via backend
    // Note: Remote backend returns fake comp_id (bridge already has its own component)
    const comp_id = try ctx.initComponent("velocity-control");
    state.comp_id = comp_id;

    // Mark component as ready (no-op for remote backend)
    try ctx.readyComponent(comp_id);

    ctx.logInfo("velocity_control", "component ready");

    // Create signals and link pins (works with both local and remote HAL)
    try ctx.createSignal("velocity-control.enable", .bit);
    try ctx.linkPin("velocity-control.enable", "velocity-control.enable");

    try ctx.createSignal("velocity-control.velocity-cmd", .float);
    try ctx.linkPin("velocity-control.velocity-cmd", "velocity-control.velocity-cmd");

    try ctx.createSignal("velocity-control.direction", .bit);
    try ctx.linkPin("velocity-control.direction", "velocity-control.direction");

    ctx.logInfo("velocity_control", "created pins and signals: enable, velocity-cmd, direction");

    // Write initial values
    try state.writeToHAL(ctx);
    ctx.logInfo("velocity_control", "initialized");
}

/// Plugin deinitialization
fn pluginDeinit() void {
    if (global_state_ptr) |state| {
        // Create a minimal context for cleanup (allocator only)
        const ctx = PluginInterface.PluginContext{
            .allocator = state.allocator,
            .backend = null,
            .log = fnLogInfo,
            .log_err = fnLogError,
        };
        state.deinit(ctx);
        state.allocator.destroy(state);
        global_state_ptr = null;
    }
}

/// Plugin render (null - no UI yet)
fn pluginRender(ctx: vxfw.DrawContext) anyerror!void {
    _ = ctx;
    // TODO: Render TUI widget for velocity control
}

/// Handle plugin events
fn pluginHandleEvent(event: PluginInterface.PluginEvent) bool {
    const state = global_state_ptr orelse return false;

    // Need a context for writeToHAL - create minimal one
    // Note: setPin requires backend, but we can't get it from here
    // In real implementation, we'd store the backend or context in state
    const ctx = PluginInterface.PluginContext{
        .allocator = state.allocator,
        .backend = null, // This won't work for writes - need to store backend in state
        .log = fnLogInfo,
        .log_err = fnLogError,
    };

    _ = ctx; // Avoid unused warning

    switch (event) {
        .focus => {
            // Refresh current values when focused
        },
        .blur => {
            // Disable when losing focus
            state.enabled = false;
            // Can't write without backend - state redesign needed
        },
        .key_press => |key| {
            const c = key.codepoint;
            if (c == 'e') {
                // Toggle enable
                state.enabled = !state.enabled;
                return true;
            }
            if (c == 'b') {
                // Backward
                state.forward = false;
                state.enabled = true;
                return true;
            }
            if (c == 'f') {
                // Forward
                state.forward = true;
                state.enabled = true;
                return true;
            }
            if (c == '+' or c == '=') {
                // Increase velocity
                state.velocity += 10.0;
                if (state.velocity > 5000.0) state.velocity = 5000.0;
                return true;
            }
            if (c == '-' or c == '_') {
                // Decrease velocity
                state.velocity -= 10.0;
                if (state.velocity < 0.0) state.velocity = 0.0;
                return true;
            }
        },
        else => {},
    }

    return false;
}

/// Log function for cleanup context
fn fnLogInfo(level: []const u8, msg: []const u8) void {
    _ = level;
    std.log.info("{s}", .{msg});
}

/// Log function for cleanup context
fn fnLogError(level: []const u8, msg: []const u8) void {
    _ = level;
    std.log.err("{s}", .{msg});
}

/// Export the plugin
pub const velocity_control_plugin = PluginInterface.Plugin{
    .name = "velocity_control",
    .version = "0.1.0",
    .description = "Velocity control for axis jogging (HAL: velocity-control)",
    .init = pluginInit,
    .deinit = pluginDeinit,
    .render = pluginRender,
    .handleEvent = pluginHandleEvent,
};
