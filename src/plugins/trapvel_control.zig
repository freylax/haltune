// Trapezoidal Velocity Control Plugin
//
// This plugin provides a trapezoidal velocity profile control.
// Based on the Python TrapVelControl plugin from riocfg/pidtune.
//
// Features:
// - Creates HAL component "trapvel-control"
// - Creates pins: enable, target-pos, max-velocity, acceleration
// - Uses HalBackend for HAL operations (works with local or remote HAL)

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const PluginInterface = @import("../plugin/interface.zig");

/// TrapVel control state
const TrapVelState = struct {
    /// HAL component ID (from backend.initComponent())
    comp_id: ?c_int = null,

    /// Pin names (for setPin/getPin calls via backend)
    enable_pin: []const u8 = "trapvel-control.enable",
    target_pos_pin: []const u8 = "trapvel-control.target-pos",
    max_velocity_pin: []const u8 = "trapvel-control.max-velocity",
    acceleration_pin: []const u8 = "trapvel-control.acceleration",

    /// Enable state
    enabled: bool = false,

    /// Target position
    target_pos: f64 = 0.0,

    /// Max velocity
    max_velocity: f64 = 100.0,

    /// Acceleration
    acceleration: f64 = 50.0,

    allocator: std.mem.Allocator,

    /// Write current state to HAL pins via backend
    pub fn writeToHAL(self: *TrapVelState, ctx: PluginInterface.PluginContext) !void {
        if (self.comp_id == null) return error.ComponentNotInitialized;

        // Write enable pin
        try ctx.setPin(self.enable_pin, .{ .bit = self.enabled });

        // Write target position
        try ctx.setPin(self.target_pos_pin, .{ .float = self.target_pos });

        // Write max velocity
        try ctx.setPin(self.max_velocity_pin, .{ .float = self.max_velocity });

        // Write acceleration
        try ctx.setPin(self.acceleration_pin, .{ .float = self.acceleration });
    }

    pub fn init(allocator: std.mem.Allocator) TrapVelState {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TrapVelState, ctx: PluginInterface.PluginContext) void {
        // Exit HAL component
        if (self.comp_id) |id| {
            ctx.exitComponent(id);
        }
    }
};

// Global state pointer (simplified - single instance)
var global_state_ptr: ?*TrapVelState = null;

/// Plugin initialization - receives PluginContext with backend access
fn pluginInit(ctx: PluginInterface.PluginContext) anyerror!void {
    // Allocate state
    const state = try ctx.allocator.create(TrapVelState);
    state.* = TrapVelState.init(ctx.allocator);
    global_state_ptr = state;

    ctx.logInfo("trapvel_control", "creating HAL component 'trapvel-control'");

    // Create HAL component via backend
    // Note: Remote backend returns fake comp_id (bridge already has its own component)
    const comp_id = try ctx.initComponent("trapvel-control");
    state.comp_id = comp_id;

    // Mark component as ready (no-op for remote backend)
    try ctx.readyComponent(comp_id);

    ctx.logInfo("trapvel_control", "component ready");

    // Create signals and link pins (works with both local and remote HAL)
    try ctx.createSignal("trapvel-control.enable", .bit);
    try ctx.linkPin("trapvel-control.enable", "trapvel-control.enable");

    try ctx.createSignal("trapvel-control.target-pos", .float);
    try ctx.linkPin("trapvel-control.target-pos", "trapvel-control.target-pos");

    try ctx.createSignal("trapvel-control.max-velocity", .float);
    try ctx.linkPin("trapvel-control.max-velocity", "trapvel-control.max-velocity");

    try ctx.createSignal("trapvel-control.acceleration", .float);
    try ctx.linkPin("trapvel-control.acceleration", "trapvel-control.acceleration");

    ctx.logInfo("trapvel_control", "created pins and signals: enable, target-pos, max-velocity, acceleration");

    // Write initial values
    try state.writeToHAL(ctx);
    ctx.logInfo("trapvel_control", "initialized");
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
    // TODO: Render TUI widget for trapvel control
}

/// Handle plugin events
fn pluginHandleEvent(event: PluginInterface.PluginEvent) bool {
    const state = global_state_ptr orelse return false;

    // Need a context for writeToHAL
    const ctx = PluginInterface.PluginContext{
        .allocator = state.allocator,
        .backend = null,
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
        },
        .key_press => |key| {
            const c = key.codepoint;

            if (c == 'e') {
                // Toggle enable
                state.enabled = !state.enabled;
                return true;
            }
            if (c == 't') {
                // Increase target position
                state.target_pos += 1.0;
                return true;
            }
            if (c == 'T') {
                // Decrease target position
                state.target_pos -= 1.0;
                return true;
            }
            if (c == 'v') {
                // Increase max velocity
                state.max_velocity += 10.0;
                if (state.max_velocity > 5000.0) state.max_velocity = 5000.0;
                return true;
            }
            if (c == 'V') {
                // Decrease max velocity
                state.max_velocity -= 10.0;
                if (state.max_velocity < 1.0) state.max_velocity = 1.0;
                return true;
            }
            if (c == 'a') {
                // Increase acceleration
                state.acceleration += 5.0;
                if (state.acceleration > 1000.0) state.acceleration = 1000.0;
                return true;
            }
            if (c == 'A') {
                // Decrease acceleration
                state.acceleration -= 5.0;
                if (state.acceleration < 1.0) state.acceleration = 1.0;
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
pub const trapvel_control_plugin = PluginInterface.Plugin{
    .name = "trapvel_control",
    .version = "0.1.0",
    .description = "Trapezoidal velocity profile control (HAL: trapvel-control)",
    .init = pluginInit,
    .deinit = pluginDeinit,
    .render = pluginRender,
    .handleEvent = pluginHandleEvent,
};
