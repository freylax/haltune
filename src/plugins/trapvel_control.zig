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
const vaxis = @import("vaxis");
const PluginInterface = @import("../plugin/interface.zig");
const HalBackend = @import("backend").HalBackend;

/// TrapVel control state
const TrapVelState = struct {
    /// HAL component ID (from backend.initComponent())
    comp_id: ?c_int = null,

    /// Pin names (for setPin/getPin calls via backend)
    enable_pin: []const u8 = "trapvel-control.enable",
    target_pos_pin: []const u8 = "trapvel-control.target-pos",
    max_velocity_pin: []const u8 = "trapvel-control.max-velocity",
    acceleration_pin: []const u8 = "trapvel-control.acceleration",

    /// HAL backend reference (for setPin/getPin calls from handleEvent)
    backend: ?*HalBackend = null,

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
    pub fn writeToHAL(self: *TrapVelState) !void {
        if (self.backend) |backend| {
            // Write enable pin
            try backend.setPinValue(self.enable_pin, .{ .bit = self.enabled });

            // Write target position
            try backend.setPinValue(self.target_pos_pin, .{ .float = self.target_pos });

            // Write max velocity
            try backend.setPinValue(self.max_velocity_pin, .{ .float = self.max_velocity });

            // Write acceleration
            try backend.setPinValue(self.acceleration_pin, .{ .float = self.acceleration });
        }
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

    // Store backend reference for later use in handleEvent
    state.backend = ctx.backend;

    ctx.logInfo("trapvel_control", "creating HAL component 'trapvel-control'");

    // Create HAL component via backend
    // Note: Remote backend returns fake comp_id (bridge already has its own component)
    // For testing without HAL, skip HAL operations and just initialize the UI state
    if (ctx.backend) |backend| {
        const comp_id = backend.initComponent("trapvel-control") catch 0;
        state.comp_id = comp_id;
        _ = backend.readyComponent(comp_id) catch {};
        ctx.logInfo("trapvel_control", "component ready");

        // Create signals and link pins (works with both local and remote HAL)
        backend.createSignal("trapvel-control.enable", .bit) catch {};
        backend.linkPin("trapvel-control.enable", "trapvel-control.enable") catch {};

        backend.createSignal("trapvel-control.target-pos", .float) catch {};
        backend.linkPin("trapvel-control.target-pos", "trapvel-control.target-pos") catch {};

        backend.createSignal("trapvel-control.max-velocity", .float) catch {};
        backend.linkPin("trapvel-control.max-velocity", "trapvel-control.max-velocity") catch {};

        backend.createSignal("trapvel-control.acceleration", .float) catch {};
        backend.linkPin("trapvel-control.acceleration", "trapvel-control.acceleration") catch {};

        // Write initial values
        state.writeToHAL() catch {};
    } else {
        ctx.logInfo("trapvel_control", "no HAL backend available, running in UI-only mode");
        state.comp_id = 0;
    }

    ctx.logInfo("trapvel_control", "initialized");
}

/// Plugin deinitialization
fn pluginDeinit() void {
    if (global_state_ptr) |state| {
        // Create a minimal context for cleanup (allocator only)
        const ctx = PluginInterface.PluginContext{
            .allocator = state.allocator,
            .backend = state.backend,
            .log = fnLogInfo,
            .log_err = fnLogError,
        };
        state.deinit(ctx);
        state.allocator.destroy(state);
        global_state_ptr = null;
    }
}

/// Render plugin UI - displays current state
/// TODO: This needs to return a Widget for TUI integration
fn pluginRender(ctx: vxfw.DrawContext) anyerror!void {
    _ = ctx;
    const state = global_state_ptr orelse return;

    // For now, just log the current state
    // The TUI integration needs to be updated to display plugin widgets
    std.log.debug("TrapVel: enable={} target={d:.1} vel={d:.1} acc={d:.1}", .{
        state.enabled, state.target_pos, state.max_velocity, state.acceleration,
    });
}

/// Get a Widget for displaying this plugin in the TUI
pub fn getWidget() vxfw.Widget {
    // Pass global_state_ptr directly as userdata (it's ?*TrapVelState)
    return .{
        .userdata = @ptrCast(global_state_ptr),
        .eventHandler = struct {
            fn handler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
                _ = ctx;
                _ = ptr;
                // Forward vxfw events to plugin event system
                switch (event) {
                    .key_press => |key| {
                        if (key.codepoint != 0) {
                            const plugin_event = PluginInterface.PluginEvent{
                                .key_press = .{ .codepoint = key.codepoint },
                            };
                            _ = pluginHandleEvent(plugin_event);
                        }
                    },
                    else => {},
                }
            }
        }.handler,
        .drawFn = struct {
            fn draw(ptr: *anyopaque, draw_ctx: vxfw.DrawContext) !vxfw.Surface {
                // ptr is ?*TrapVelState
                const state_ptr: ?*TrapVelState = @ptrCast(@alignCast(ptr));

                const max = draw_ctx.max.size();

                // Create a minimal widget for surface reference
                // This widget just returns an empty surface - actual content is drawn to buffer
                const placeholder_widget = vxfw.Widget{
                    .userdata = ptr,
                    .captureHandler = null,
                    .eventHandler = null,
                    .drawFn = struct {
                        fn placeholderDraw(widget_ptr: *anyopaque, widget_ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
                            _ = widget_ptr;
                            return vxfw.Surface.init(widget_ctx.arena, undefined, .{ .width = 0, .height = 0 });
                        }
                    }.placeholderDraw,
                };

                // Check if plugin is initialized
                std.log.info("trapvel drawFn: checking state_ptr", .{});
                const state = state_ptr orelse {
                    std.log.info("trapvel drawFn: state is NULL, showing error", .{});
                    // Plugin not initialized - show error message
                    const height: u16 = 4;
                    var surface = try vxfw.Surface.init(
                        draw_ctx.arena,
                        placeholder_widget,
                        .{ .width = max.width, .height = height },
                    );

                    const base_cell: vaxis.Cell = .{ .default = true };
                    @memset(surface.buffer, base_cell);

                    const msg = "PLUGIN NOT INITIALIZED";
                    const start_col = @as(u16, @intCast((max.width -| msg.len) / 2));
                    for (msg, 0..) |c, i| {
                        const grapheme_bytes = [_]u8{c};
                        surface.writeCell(start_col + @as(u16, @intCast(i)), 1, .{
                            .char = .{ .grapheme = &grapheme_bytes, .width = 1 },
                            .style = .{},
                        });
                    }
                    return surface;
                };

                // Plugin is initialized - build full UI using actual state values
                const height: u16 = max.height;

                std.log.info("trapvel drawFn: creating surface with size {}x{}", .{max.width, height});

                var surface = try vxfw.Surface.init(
                    draw_ctx.arena,
                    placeholder_widget,
                    .{ .width = max.width, .height = height },
                );

                // Initialize with default cells
                const base_cell: vaxis.Cell = .{ .default = true };
                @memset(surface.buffer, base_cell);

                // Format strings with actual state values
                var enable_buf: [32]u8 = undefined;
                const enable_str = std.fmt.bufPrintZ(&enable_buf, "Enable: {s}", .{if (state.enabled) "ENABLED" else "DISABLED"}) catch "Enable: ?";

                var target_buf: [32]u8 = undefined;
                const target_str = std.fmt.bufPrintZ(&target_buf, "Target: {d:.1}", .{state.target_pos}) catch "Target: ?";

                var vel_buf: [32]u8 = undefined;
                const vel_str = std.fmt.bufPrintZ(&vel_buf, "Max Velocity: {d:.1}", .{state.max_velocity}) catch "Velocity: ?";

                var accel_buf: [32]u8 = undefined;
                const accel_str = std.fmt.bufPrintZ(&accel_buf, "Acceleration: {d:.1}", .{state.acceleration}) catch "Accel: ?";

                // Title
                const msg1 = "TRAPVEL CONTROL PLUGIN";
                const start_col1 = @as(u16, @intCast((max.width -| msg1.len) / 2));
                var col: u16 = start_col1;
                for (msg1) |c| {
                    const grapheme_bytes = [_]u8{c};
                    surface.writeCell(col, 2, .{
                        .char = .{ .grapheme = &grapheme_bytes, .width = 1 },
                        .style = .{ .bold = true },
                    });
                    col += 1;
                }

                // Enable status
                const col2: u16 = 4;
                col = col2;
                for (enable_str) |c| {
                    const grapheme_bytes = [_]u8{c};
                    surface.writeCell(col, 5, .{
                        .char = .{ .grapheme = &grapheme_bytes, .width = 1 },
                        .style = if (state.enabled) .{ .fg = .{ .index = 2 } } else .{}, // Green if enabled
                    });
                    col += 1;
                }

                // Target position
                col = col2;
                for (target_str) |c| {
                    const grapheme_bytes = [_]u8{c};
                    surface.writeCell(col, 7, .{
                        .char = .{ .grapheme = &grapheme_bytes, .width = 1 },
                        .style = .{},
                    });
                    col += 1;
                }

                // Max velocity
                col = col2;
                for (vel_str) |c| {
                    const grapheme_bytes = [_]u8{c};
                    surface.writeCell(col, 9, .{
                        .char = .{ .grapheme = &grapheme_bytes, .width = 1 },
                        .style = .{},
                    });
                    col += 1;
                }

                // Acceleration
                col = col2;
                for (accel_str) |c| {
                    const grapheme_bytes = [_]u8{c};
                    surface.writeCell(col, 11, .{
                        .char = .{ .grapheme = &grapheme_bytes, .width = 1 },
                        .style = .{},
                    });
                    col += 1;
                }

                // Help text at bottom
                const help_msg = "e=Toggle t/T=Target±1 v/V=Vel±10 a/A=Accel±5";
                const start_help = @as(u16, @intCast((max.width -| help_msg.len) / 2));
                col = start_help;
                for (help_msg) |c| {
                    const grapheme_bytes = [_]u8{c};
                    surface.writeCell(col, @intCast(max.height -| 2), .{
                        .char = .{ .grapheme = &grapheme_bytes, .width = 1 },
                        .style = .{ .dim = true },
                    });
                    col += 1;
                }

                std.log.info("trapvel drawFn: finished writing text, returning surface", .{});

                return surface;
            }
        }.draw,
    };
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
            var handled = false;

            if (c == 'e') {
                // Toggle enable
                state.enabled = !state.enabled;
                handled = true;
            }
            if (c == 't') {
                // Increase target position
                state.target_pos += 1.0;
                handled = true;
            }
            if (c == 'T') {
                // Decrease target position
                state.target_pos -= 1.0;
                handled = true;
            }
            if (c == 'v') {
                // Increase max velocity
                state.max_velocity += 10.0;
                if (state.max_velocity > 5000.0) state.max_velocity = 5000.0;
                handled = true;
            }
            if (c == 'V') {
                // Decrease max velocity
                state.max_velocity -= 10.0;
                if (state.max_velocity < 1.0) state.max_velocity = 1.0;
                handled = true;
            }
            if (c == 'a') {
                // Increase acceleration
                state.acceleration += 5.0;
                if (state.acceleration > 1000.0) state.acceleration = 1000.0;
                handled = true;
            }
            if (c == 'A') {
                // Decrease acceleration
                state.acceleration -= 5.0;
                if (state.acceleration < 1.0) state.acceleration = 1.0;
                handled = true;
            }

            // Write to HAL after any change
            if (handled) {
                state.writeToHAL() catch {};
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
    .getWidget = getWidget,
    .handleEvent = pluginHandleEvent,
};
