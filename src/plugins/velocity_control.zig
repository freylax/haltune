// Velocity Control Plugin
//
// This plugin provides a simple velocity control interface for jogging an axis.
// Based on the Python VelocityControl plugin from riocfg/pidtune.
//
// Features:
// - Creates HAL component "velocity-control"
// - Creates pins: enable, velocity-cmd, direction
// - Wires to rio motion pins for jogging control
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

/// Velocity control state
const VelocityControlState = struct {
    /// HAL component (owned)
    component: ?*Component = null,

    /// Pin handles (for fast direct access)
    enable_pin: ?*Pin = null,
    velocity_pin: ?*Pin = null,
    direction_pin: ?*Pin = null,

    /// Current velocity setting
    velocity: f64 = 100.0,

    /// Direction: true = forward, false = backward
    forward: bool = true,

    /// Enable state
    enabled: bool = false,

    allocator: std.mem.Allocator,

    /// Write current state to HAL pins
    pub fn writeToHAL(self: *VelocityControlState) !void {
        if (self.enable_pin) |pin| {
            try pin.setBit(self.enabled);
        }
        if (self.direction_pin) |pin| {
            try pin.setBit(self.forward);
        }
        if (self.velocity_pin) |pin| {
            const vel = if (self.forward) self.velocity else -self.velocity;
            try pin.setFloat(vel);
        }
    }

    pub fn init(allocator: std.mem.Allocator) VelocityControlState {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VelocityControlState) void {
        const allocator = self.allocator;

        // Exit and free component
        if (self.component) |comp| {
            comp.exit();
            allocator.destroy(comp);
        }
    }
};

// Global state pointer (simplified - single instance)
var global_state_ptr: ?*VelocityControlState = null;

/// Plugin initialization
fn pluginInit(allocator: std.mem.Allocator, log: PluginInterface.LogFn, log_err: PluginInterface.LogFn) anyerror!void {
    _ = log_err;
    _ = allocator;

    // Allocate state
    const state = try std.heap.c_allocator.create(VelocityControlState);
    state.* = VelocityControlState.init(std.heap.c_allocator);
    global_state_ptr = state;

    // Create HAL component
    log("info", "velocity_control: creating HAL component");
    const comp_ptr = try std.heap.c_allocator.create(Component);
    comp_ptr.* = try Component.init(std.heap.c_allocator, "velocity-control");
    try comp_ptr.ready();
    state.component = comp_ptr;

    // Create pins
    state.enable_pin = try comp_ptr.newPin("enable", .bit, .out);
    log("info", "velocity_control: created pin 'enable'");

    state.velocity_pin = try comp_ptr.newPin("velocity-cmd", .float, .out);
    log("info", "velocity_control: created pin 'velocity-cmd'");

    state.direction_pin = try comp_ptr.newPin("direction", .bit, .out);
    log("info", "velocity_control: created pin 'direction'");

    // Wire to signals (if they exist)
    // Note: link returns error if signal doesn't exist, which is OK
    if (state.enable_pin) |pin| {
        pin.link("velocity-control.enable") catch |err| {
            if (err != HalError.NotFound) {
                log("info", "velocity_control: couldn't link enable pin");
            }
        };
    }

    // Write initial values
    try state.writeToHAL();
    log("info", "velocity_control: initialized");
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
    // TODO: Render TUI widget for velocity control
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
            if (c == 'b') {
                // Backward
                state.forward = false;
                state.enabled = true;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == 'f') {
                // Forward
                state.forward = true;
                state.enabled = true;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == '+' or c == '=') {
                // Increase velocity
                state.velocity += 10.0;
                if (state.velocity > 5000.0) state.velocity = 5000.0;
                state.writeToHAL() catch {};
                return true;
            }
            if (c == '-' or c == '_') {
                // Decrease velocity
                state.velocity -= 10.0;
                if (state.velocity < 0.0) state.velocity = 0.0;
                state.writeToHAL() catch {};
                return true;
            }
        },
        else => {},
    }

    return false;
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
