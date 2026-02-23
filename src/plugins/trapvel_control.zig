// Trapezoidal Velocity Control Plugin
//
// This plugin provides a trapezoidal velocity profile control.
// Based on the Python TrapVelControl plugin from riocfg/pidtune.
//
// Features:
// - Creates HAL component "trapvel-control"
// - Creates pins: enable, target-pos, max-velocity, acceleration
// - Uses HAL as communication channel

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const PluginInterface = @import("../plugin/interface.zig");

// Import HAL FFI modules directly
const Component = @import("../ffi/component.zig").Component;
const Pin = @import("../ffi/pin.zig").Pin;
const PinType = @import("../ffi/pin.zig").PinType;
const PinDir = @import("../ffi/pin.zig").PinDir;
const HalError = @import("../ffi/errors.zig").HalError;

/// TrapVel control state
const TrapVelState = struct {
    /// HAL component (owned)
    component: ?*Component = null,

    /// Pin handles (for fast direct access)
    enable_pin: ?*Pin = null,
    target_pos_pin: ?*Pin = null,
    max_velocity_pin: ?*Pin = null,
    acceleration_pin: ?*Pin = null,

    /// Enable state
    enabled: bool = false,

    /// Target position
    target_pos: f64 = 0.0,

    /// Max velocity
    max_velocity: f64 = 100.0,

    /// Acceleration
    acceleration: f64 = 50.0,

    allocator: std.mem.Allocator,

    /// Write current state to HAL pins
    pub fn writeToHAL(self: *TrapVelState) !void {
        if (self.enable_pin) |pin| {
            try pin.setBit(self.enabled);
        }
        if (self.target_pos_pin) |pin| {
            try pin.setFloat(self.target_pos);
        }
        if (self.max_velocity_pin) |pin| {
            try pin.setFloat(self.max_velocity);
        }
        if (self.acceleration_pin) |pin| {
            try pin.setFloat(self.acceleration);
        }
    }

    pub fn init(allocator: std.mem.Allocator) TrapVelState {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TrapVelState) void {
        const allocator = self.allocator;

        // Exit and free component
        if (self.component) |comp| {
            comp.exit();
            allocator.destroy(comp);
        }
    }
};

// Global state pointer (simplified - single instance)
var global_state_ptr: ?*TrapVelState = null;

/// Plugin initialization
fn pluginInit(allocator: std.mem.Allocator, log: PluginInterface.LogFn, log_err: PluginInterface.LogFn) anyerror!void {
    _ = log_err;
    _ = allocator;

    // Allocate state
    const state = try std.heap.c_allocator.create(TrapVelState);
    state.* = TrapVelState.init(std.heap.c_allocator);
    global_state_ptr = state;

    // Create HAL component
    log("info", "trapvel_control: creating HAL component");
    const comp_ptr = try std.heap.c_allocator.create(Component);
    comp_ptr.* = try Component.init(std.heap.c_allocator, "trapvel-control");
    try comp_ptr.ready();
    state.component = comp_ptr;

    // Create pins
    state.enable_pin = try comp_ptr.newPin("enable", .bit, .out);
    log("info", "trapvel_control: created pin 'enable'");

    state.target_pos_pin = try comp_ptr.newPin("target-pos", .float, .out);
    log("info", "trapvel_control: created pin 'target-pos'");

    state.max_velocity_pin = try comp_ptr.newPin("max-velocity", .float, .out);
    log("info", "trapvel_control: created pin 'max-velocity'");

    state.acceleration_pin = try comp_ptr.newPin("acceleration", .float, .out);
    log("info", "trapvel_control: created pin 'acceleration'");

    // Wire to signals (if they exist)
    if (state.enable_pin) |pin| {
        pin.link("trapvel-control.enable") catch |err| {
            if (err != HalError.NotFound) {
                log("info", "trapvel_control: couldn't link enable pin");
            }
        };
    }

    // Write initial values
    try state.writeToHAL();
    log("info", "trapvel_control: initialized");
}

/// Plugin deinitialization
fn pluginDeinit() void {
    if (global_state_ptr) |state| {
        state.deinit();
        std.heap.c_allocator.destroy(state);
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

    switch (event) {
        .focus => {
            // Refresh current values when focused
        },
        .blur => {
            // Disable when losing focus
            state.enabled = false;
            state.writeToHAL() catch {};
        },
        .key_press => |key| {
            const c = key.codepoint;

            if (c == 'e') {
                // Toggle enable
                state.enabled = !state.enabled;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == 't') {
                // Increase target position
                state.target_pos += 1.0;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == 'T') {
                // Decrease target position
                state.target_pos -= 1.0;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == 'v') {
                // Increase max velocity
                state.max_velocity += 10.0;
                if (state.max_velocity > 5000.0) state.max_velocity = 5000.0;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == 'V') {
                // Decrease max velocity
                state.max_velocity -= 10.0;
                if (state.max_velocity < 1.0) state.max_velocity = 1.0;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == 'a') {
                // Increase acceleration
                state.acceleration += 5.0;
                if (state.acceleration > 1000.0) state.acceleration = 1000.0;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == 'A') {
                // Decrease acceleration
                state.acceleration -= 5.0;
                if (state.acceleration < 1.0) state.acceleration = 1.0;
                state.writeToHAL() catch {};
                return true;
            }
        },
        else => {},
    }

    return false;
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
