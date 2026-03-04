// Velocity Control Plugin
//
// This plugin provides a simple velocity control interface for jogging an axis.
// Based on the Python VelocityControl plugin from riocfg/pidtune.
//
// Features:
// - Creates HAL component "velocity-control"
// - Creates pins: enable, velocity-cmd, direction
// - Wires to rio motion pins for jogging control
// - Uses HalBackend for HAL operations (works with local and remote HAL)
// - UI widget showing current state and key hints

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const PluginInterface = @import("../plugin/interface.zig");

/// Velocity control widget state
const VelocityControlState = struct {
    /// HAL component ID (from backend.initComponent())
    comp_id: ?c_int = null,

    /// Pin names (for setPin/getPin calls via backend)
    enable_pin: []const u8 = "velocity-control.enable",
    velocity_pin: []const u8 = "velocity-control.velocity-cmd",
    direction_pin: []const u8 = "velocity-control.direction",

    /// Backend pointer (for HAL operations)
    backend: ?*const PluginInterface.HalBackend = null,

    /// Allocator (for memory operations)
    allocator: std.mem.Allocator,

    /// Current velocity setting
    velocity: f64 = 100.0,

    /// Direction: true = forward, false = backward
    forward: bool = true,

    /// Enable state
    enabled: bool = false,

    /// Whether HAL is available (connected)
    hal_available: bool = false,

    /// Write current state to HAL pins via backend
    /// Silently does nothing if HAL is not available
    pub fn writeToHAL(self: *VelocityControlState) !void {
        // Silently return if HAL is not available
        if (!self.hal_available) return;

        const backend = self.backend orelse return;

        // Write enable pin (ignore errors)
        backend.setPinValue(self.enable_pin, .{ .bit = self.enabled }) catch {};

        // Write direction pin (ignore errors)
        backend.setPinValue(self.direction_pin, .{ .bit = self.forward }) catch {};

        // Write velocity pin (signed based on direction) (ignore errors)
        const vel = if (self.forward) self.velocity else -self.velocity;
        backend.setPinValue(self.velocity_pin, .{ .float = vel }) catch {};
    }

    pub fn init(allocator: std.mem.Allocator) VelocityControlState {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VelocityControlState) void {
        if (self.comp_id) |id| {
            if (self.backend) |backend| {
                backend.exitComponent(id);
            }
        }
    }

    /// Toggle enable state
    pub fn toggleEnable(self: *VelocityControlState) !void {
        self.enabled = !self.enabled;
        try self.writeToHAL();
    }

    /// Set forward direction and enable
    pub fn setForward(self: *VelocityControlState) !void {
        self.forward = true;
        self.enabled = true;
        try self.writeToHAL();
    }

    /// Set backward direction and enable
    pub fn setBackward(self: *VelocityControlState) !void {
        self.forward = false;
        self.enabled = true;
        try self.writeToHAL();
    }

    /// Increase velocity
    pub fn increaseVelocity(self: *VelocityControlState) !void {
        self.velocity += 10.0;
        if (self.velocity > 5000.0) self.velocity = 5000.0;
        try self.writeToHAL();
    }

    /// Decrease velocity
    pub fn decreaseVelocity(self: *VelocityControlState) !void {
        self.velocity -= 10.0;
        if (self.velocity < 0.0) self.velocity = 0.0;
        try self.writeToHAL();
    }
};

// Global state pointer (single instance)
var global_state_ptr: ?*VelocityControlState = null;

/// Widget for velocity control UI
const VelocityControlWidget = struct {
    state: *VelocityControlState,

    const Self = @This();

    pub fn widget(self: *Self) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.handleEvent(ctx, event);
    }

    fn handleEvent(self: *Self, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const state = self.state;

        switch (event) {
            .init => {
                // Initial render
                ctx.consumeAndRedraw();
            },
            .focus_in => {
                // Refresh when focused
                state.writeToHAL() catch {};
                ctx.consumeAndRedraw();
            },
            .focus_out => {
                // Disable when losing focus
                state.enabled = false;
                state.writeToHAL() catch {};
                ctx.consumeAndRedraw();
            },
            .key_press => |key| {
                const c = key.codepoint;
                switch (c) {
                    'e' => {
                        state.toggleEnable() catch {};
                        ctx.consumeAndRedraw();
                    },
                    'f' => {
                        state.setForward() catch {};
                        ctx.consumeAndRedraw();
                    },
                    'b' => {
                        state.setBackward() catch {};
                        ctx.consumeAndRedraw();
                    },
                    '+', '=' => {
                        state.increaseVelocity() catch {};
                        ctx.consumeAndRedraw();
                    },
                    '-', '_' => {
                        state.decreaseVelocity() catch {};
                        ctx.consumeAndRedraw();
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    fn draw(self: *Self, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const state = self.state;
        const max = ctx.max.size();

        std.log.info("VelocityControlWidget.draw() called: hal_available={}, max={}x{}", .{state.hal_available, max.width, max.height});

        // Create surface
        var surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            max,
        );

        // Initialize with default cells (no background color)
        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        // Simple styles - use bold for emphasis, avoid custom colors
        const title_style = vaxis.Style{ .bold = true };
        const label_style = vaxis.Style{};
        const value_style = vaxis.Style{ .bold = true };
        const disabled_style = vaxis.Style{ .dim = true };
        const enabled_style = vaxis.Style{ .reverse = true };  // Reverse video for enabled
        const error_style = vaxis.Style{ .bold = true };

        var row: u16 = 2;
        const col_start: u16 = 4;

        // Title
        const title = "Velocity Control";
        const title_col = if (max.width > title.len + 4)
            @as(u16, @intCast((max.width - title.len) / 2))
        else
            2;
        try writeText(&surface, title, title_col, row, title_style, ctx.arena);
        std.log.info("VelocityControl: wrote title '{s}' at col={}, row={}", .{title, title_col, row});
        row += 2;

        // Show HAL status
        if (!state.hal_available) {
            const msg = "*** HAL NOT CONNECTED ***";
            const msg_col = if (max.width > msg.len + 4)
                @as(u16, @intCast((max.width - msg.len) / 2))
            else
                2;
            try writeText(&surface, msg, msg_col, row, error_style, ctx.arena);
            row += 1;
            const hint = "(Start HAL or bridge server to enable control)";
            const hint_col = if (max.width > hint.len + 4)
                @as(u16, @intCast((max.width - hint.len) / 2))
            else
                2;
            try writeText(&surface, hint, hint_col, row, disabled_style, ctx.arena);
            row += 3;
            std.log.info("VelocityControl: HAL not connected, displayed warning at row={}", .{row});
        }

        // Enable status
        const enable_text = if (state.enabled) "ENABLED" else "DISABLED";
        const enable_style = if (state.enabled) enabled_style else disabled_style;
        try writeText(&surface, "Enable Status:", col_start, row, label_style, ctx.arena);
        try writeText(&surface, enable_text, col_start + 15, row, enable_style, ctx.arena);
        std.log.info("VelocityControl: wrote '{s}' at row={}", .{enable_text, row});
        row += 2;

        // Direction
        const dir_text = if (state.forward) "FORWARD >>" else "<< BACKWARD";
        try writeText(&surface, "Direction:", col_start, row, label_style, ctx.arena);
        try writeText(&surface, dir_text, col_start + 11, row, value_style, ctx.arena);
        std.log.info("VelocityControl: wrote '{s}' at row={}", .{dir_text, row});
        row += 2;

        // Velocity
        try writeText(&surface, "Velocity:", col_start, row, label_style, ctx.arena);
        const vel_str = try std.fmt.allocPrint(ctx.arena, "{d:.0} units/s", .{state.velocity});
        try writeText(&surface, vel_str, col_start + 10, row, value_style, ctx.arena);
        std.log.info("VelocityControl: wrote '{s}' at row={}", .{vel_str, row});
        row += 2;

        // Separator
        row += 1;
        const sep = "────────────────────────────────────────";
        try writeText(&surface, sep, col_start, row, disabled_style, ctx.arena);
        row += 2;

        // Key hints
        const hints = [_][]const u8{
            "e - Toggle enable",
            "f - Forward",
            "b - Backward",
            "+ - Increase velocity",
            "- - Decrease velocity",
        };

        for (hints) |hint| {
            try writeText(&surface, hint, col_start, row, label_style, ctx.arena);
            row += 1;
        }
        std.log.info("VelocityControl: wrote {} hints, final row={}", .{hints.len, row});

        // Debug: Check if buffer has content
        std.log.info("VelocityControl: buffer.len={}, size={}x{}, first cell char={}",
            .{surface.buffer.len, surface.size.width, surface.size.height,
                if (surface.buffer.len > 0) surface.buffer[0].char.grapheme.len else 0});
        // Check a few specific positions
        if (surface.buffer.len > 0) {
            const title_idx = (2 * surface.size.width) + 32; // Row 2, Col 32 (title position)
            std.log.info("VelocityControl: cell at title position has char_len={}",
                .{if (title_idx < surface.buffer.len) surface.buffer[title_idx].char.grapheme.len else 0});
        }

        return surface;
    }
};

/// Helper to write text to surface
/// We need to allocate the grapheme data so it persists after this function returns
fn writeText(
    surface: *vxfw.Surface,
    text: []const u8,
    col: u16,
    row: u16,
    style: vaxis.Style,
    allocator: std.mem.Allocator,
) !void {
    const max_col = surface.size.width;
    var c = col;
    for (text) |byte| {
        if (c >= max_col) break;
        // Only handle ASCII for simplicity
        if (byte >= 128) continue;
        // Allocate a single byte on the arena so the slice persists
        const char_buf = try allocator.create(u8);
        char_buf.* = byte;
        const char_slice = std.mem.asBytes(char_buf);
        surface.writeCell(c, row, .{
            .char = .{ .grapheme = char_slice, .width = 1 },
            .style = style,
        });
        c += 1;
    }
}

// Global widget pointer (for getWidget callback)
var global_widget_ptr: ?*VelocityControlWidget = null;

// Dummy userdata for empty widget (Widget requires *anyopaque, not optional)
var empty_widget_userdata: u8 = 0;

/// Plugin initialization
fn pluginInit(ctx: PluginInterface.PluginContext) anyerror!void {
    // Allocate state
    const state = try ctx.allocator.create(VelocityControlState);
    state.* = VelocityControlState.init(ctx.allocator);
    global_state_ptr = state;

    // Store backend pointer for later HAL writes
    state.backend = ctx.backend;

    ctx.logInfo("velocity_control", "plugin init starting\n");

    // Try to initialize HAL component, but don't fail if unavailable
    if (ctx.backend) |_| {
        // Try to create HAL component
        if (ctx.initComponent("velocity-control")) |comp_id| {
            state.comp_id = comp_id;
            ctx.logInfo("velocity_control", "created HAL component 'velocity-control'\n");

            // Try to mark component as ready
            if (ctx.readyComponent(comp_id)) {
                ctx.logInfo("velocity_control", "component ready\n");
            } else |_| {}

            // Try to create signals and link pins (may fail for remote backend)
            ctx.createSignal("velocity-control.enable", .bit) catch {};
            ctx.linkPin("velocity-control.enable", "velocity-control.enable") catch {};
            ctx.createSignal("velocity-control.velocity-cmd", .float) catch {};
            ctx.linkPin("velocity-control.velocity-cmd", "velocity-control.velocity-cmd") catch {};
            ctx.createSignal("velocity-control.direction", .bit) catch {};
            ctx.linkPin("velocity-control.direction", "velocity-control.direction") catch {};

            // Mark HAL as available if we got this far
            state.hal_available = true;
            ctx.logInfo("velocity_control", "HAL initialization complete\n");
        } else |_| {
            ctx.logInfo("velocity_control", "HAL not available - running in display-only mode\n");
        }
    } else {
        ctx.logInfo("velocity_control", "No backend available - running in display-only mode\n");
    }

    const vel_msg = try std.fmt.allocPrint(ctx.allocator, "plugin initialized with velocity={d:.0}\n", .{state.velocity});
    ctx.logInfo("velocity_control", vel_msg);
}

/// Plugin deinitialization
fn pluginDeinit() void {
    if (global_state_ptr) |state| {
        state.deinit();
        state.allocator.destroy(state);
        global_state_ptr = null;
    }
    global_widget_ptr = null;
}

/// Get widget for this plugin
fn pluginGetWidget() vxfw.Widget {
    if (global_state_ptr) |state| {
        // Create widget if not exists
        if (global_widget_ptr == null) {
            // Create widget in arena allocator (won't need manual free)
            const widget = state.allocator.create(VelocityControlWidget) catch {
                // Fall back to empty widget on allocation failure
                return .{
                    .userdata = &empty_widget_userdata,
                    .eventHandler = &emptyEventHandler,
                    .drawFn = &emptyDrawFn,
                };
            };
            widget.* = .{ .state = state };
            global_widget_ptr = widget;
        }
        return global_widget_ptr.?.widget();
    }
    // Return empty widget if no state
    return .{
        .userdata = &empty_widget_userdata,
        .eventHandler = &emptyEventHandler,
        .drawFn = &emptyDrawFn,
    };
}

fn emptyEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    _ = ptr;
    _ = event;
    // Do nothing - just consume the event
    ctx.consumeEvent();
}

fn emptyDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    _ = ptr;
    const max = ctx.max.size();
    const surface = try vxfw.Surface.init(ctx.arena, undefined, max);
    const base_cell: vaxis.Cell = .{ .default = true };
    @memset(surface.buffer, base_cell);
    return surface;
}

/// Handle plugin events (for focus/blur from main event loop)
fn pluginHandleEvent(event: PluginInterface.PluginEvent) bool {
    const state = global_state_ptr orelse return false;

    switch (event) {
        .focus => {
            // Refresh when focused
            state.writeToHAL() catch {};
            return true;
        },
        .blur => {
            // Disable when losing focus
            state.enabled = false;
            state.writeToHAL() catch {};
            return true;
        },
        else => return false,
    }
}

/// Export the plugin
pub const velocity_control_plugin = PluginInterface.Plugin{
    .name = "velocity_control",
    .version = "0.2.0",
    .description = "Velocity control for axis jogging (HAL: velocity-control)",
    .init = pluginInit,
    .deinit = pluginDeinit,
    .render = null, // Using widget instead
    .getWidget = pluginGetWidget,
    .handleEvent = pluginHandleEvent,
};
