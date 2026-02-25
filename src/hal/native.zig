// Native HAL Backend
//
// This implementation uses direct HAL FFI calls.

const std = @import("std");
const backend = @import("backend");
const HalBackend = backend.HalBackend;
const HalValue = backend.HalValue;
const PinInfo = backend.PinInfo;
const SignalInfo = backend.SignalInfo;
const ParamInfo = backend.ParamInfo;
const PinType = backend.PinType;
const PinDir = backend.PinDir;
const ParamDir = backend.ParamDir;

// HAL FFI imports
const c = @import("ffi-c").c;

// Discovery helpers using halcmd
const discovery = @import("../ffi/safe_discovery.zig");

/// Helper to create a null-terminated C string
fn toCStr(allocator: std.mem.Allocator, str: []const u8) ![:0]const u8 {
    const result = try allocator.allocSentinel(u8, str.len + 1, 0);
    @memcpy(result[0..str.len], str);
    return result;
}

/// Native backend state
pub const NativeBackend = struct {
    allocator: std.mem.Allocator,
    comp_id: c_int = -1,

    /// Create a new native HAL backend
    pub fn create(allocator: std.mem.Allocator) !HalBackend {
        const state = try allocator.create(State);
        state.* = .{
            .allocator = allocator,
            .comp_id = -1,
        };

        return HalBackend{
            .ptr = state,
            .vtable = &vtable,
        };
    }

    const State = struct {
        allocator: std.mem.Allocator,
        comp_id: c_int,
    };

    const vtable = HalBackend.VTable{
        .deinit = deinit,
        .initComponent = initComponent,
        .readyComponent = readyComponent,
        .exitComponent = exitComponent,
        .listPins = listPins,
        .listSignals = listSignals,
        .listParams = listParams,
        .listComponents = listComponents,
        .getPinValue = getPinValue,
        .setPinValue = setPinValue,
        .getParamValue = getParamValue,
        .setParamValue = setParamValue,
        .createSignal = createSignal,
        .deleteSignal = deleteSignal,
        .linkPin = linkPin,
        .unlinkPin = unlinkPin,
    };

    fn deinit(ptr: *anyopaque) void {
        const self: *State = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }

    fn initComponent(ptr: *anyopaque, name: []const u8) !c_int {
        const self: *State = @ptrCast(@alignCast(ptr));
        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Try the requested name first
        var comp_id = c.hal_init(name_z.ptr);

        // If that fails, try incrementing suffixes
        if (comp_id < 0) {
            var suffix: u32 = 1;
            while (suffix <= 100) : (suffix += 1) {
                const numbered_name = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}{d}",
                    .{ name, suffix },
                );
                defer self.allocator.free(numbered_name);
                const numbered_z = try toCStr(self.allocator, numbered_name);
                defer self.allocator.free(numbered_z);

                comp_id = c.hal_init(numbered_z.ptr);
                if (comp_id >= 0) {
                    std.debug.print("Using component name '{s}' (original '{s}' was in use)\n", .{ numbered_name, name });
                    break;
                }
            }
        }

        if (comp_id < 0) return error.InitFailed;
        self.comp_id = comp_id;
        return comp_id;
    }

    fn readyComponent(ptr: *anyopaque, comp_id: c_int) !void {
        _ = ptr;
        const rc = c.hal_ready(comp_id);
        if (rc < 0) return error.NotReady;
    }

    fn exitComponent(ptr: *anyopaque, comp_id: c_int) void {
        _ = ptr;
        _ = c.hal_exit(comp_id);
    }

    fn listPins(ptr: *anyopaque, allocator: std.mem.Allocator) ![]PinInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // Get all pin names using halcmd
        const pin_names = try discovery.listPinNames(allocator);
        defer {
            for (pin_names.items) |n| allocator.free(n);
            pin_names.deinit(allocator);
        }

        // Allocate result array
        const pins = try allocator.alloc(PinInfo, pin_names.items.len);
        errdefer allocator.free(pins);

        // Get details for each pin using HAL API
        for (pin_names.items, 0..) |pin_name, i| {
            const name_z = try toCStr(allocator, pin_name);
            defer allocator.free(name_z);

            const pin_ptr = c.halpr_find_pin_by_name(name_z.ptr);
            if (pin_ptr == null) continue;

            const pin = pin_ptr.*;

            // Get pin type
            const pin_type: PinType = switch (pin.type) {
                c.HAL_BIT => .bit,
                c.HAL_FLOAT => .float,
                c.HAL_S32 => .s32,
                c.HAL_U32 => .u32,
                else => .bit, // fallback
            };

            // Get pin direction
            const pin_dir: PinDir = switch (pin.dir) {
                c.HAL_IN => .in,
                c.HAL_OUT => .out,
                c.HAL_IO => .io,
                else => .in, // fallback
            };

            // Get pin value
            const pin_value: HalValue = switch (pin.type) {
                c.HAL_BIT => if (pin.data.ptr) |d| .{ .bit = d.*.b != 0 } else HalValue{ .bit = false },
                c.HAL_FLOAT => if (pin.data.ptr) |d| .{ .float = d.*.f } else HalValue{ .float = 0.0 },
                c.HAL_S32 => if (pin.data.ptr) |d| .{ .s32 = d.*.s } else HalValue{ .s32 = 0 },
                c.HAL_U32 => if (pin.data.ptr) |d| .{ .u32 = d.*.u } else HalValue{ .u32 = 0 },
                else => HalValue{ .bit = false },
            };

            pins[i] = PinInfo{
                .name = try allocator.dupe(u8, pin_name),
                .type = pin_type,
                .dir = pin_dir,
                .value = pin_value,
            };
        }

        return pins;
    }

    fn listSignals(ptr: *anyopaque, allocator: std.mem.Allocator) ![]SignalInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // Get all signal names using halcmd
        const sig_names = try discovery.listSignalNames(allocator);
        defer {
            for (sig_names.items) |n| allocator.free(n);
            sig_names.deinit(allocator);
        }

        // Allocate result array
        const signals = try allocator.alloc(SignalInfo, sig_names.items.len);
        errdefer allocator.free(signals);

        // Get details for each signal using HAL API
        for (sig_names.items, 0..) |sig_name, i| {
            const name_z = try toCStr(allocator, sig_name);
            defer allocator.free(name_z);

            const sig_ptr = c.halpr_find_sig_by_name(name_z.ptr);

            // Get signal type (default to float if not found)
            const sig_type: PinType = if (sig_ptr) |s| switch (s.type) {
                c.HAL_BIT => .bit,
                c.HAL_FLOAT => .float,
                c.HAL_S32 => .s32,
                c.HAL_U32 => .u32,
                else => .float,
            } else .float;

            // Get signal value
            const sig_value: HalValue = if (sig_ptr) |s| switch (s.type) {
                c.HAL_BIT => if (s.data.ptr) |d| .{ .bit = d.*.b != 0 } else HalValue{ .bit = false },
                c.HAL_FLOAT => if (s.data.ptr) |d| .{ .float = d.*.f } else HalValue{ .float = 0.0 },
                c.HAL_S32 => if (s.data.ptr) |d| .{ .s32 = d.*.s } else HalValue{ .s32 = 0 },
                c.HAL_U32 => if (s.data.ptr) |d| .{ .u32 = d.*.u } else HalValue{ .u32 = 0 },
                else => HalValue{ .float = 0.0 },
            } else HalValue{ .float = 0.0 };

            // Collect writers and readers (empty for now - would need more complex iteration)
            signals[i] = SignalInfo{
                .name = try allocator.dupe(u8, sig_name),
                .type = sig_type,
                .value = sig_value,
                .writers = &[_][]const u8{},
                .readers = &[_][]const u8{},
            };
        }

        return signals;
    }

    fn listParams(ptr: *anyopaque, allocator: std.mem.Allocator) ![]ParamInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // Get all param names using halcmd
        const param_names = try discovery.listParamNames(allocator);
        defer {
            for (param_names.items) |n| allocator.free(n);
            param_names.deinit(allocator);
        }

        // Allocate result array
        const params = try allocator.alloc(ParamInfo, param_names.items.len);
        errdefer allocator.free(params);

        // Get details for each param using HAL API
        for (param_names.items, 0..) |param_name, i| {
            const name_z = try toCStr(allocator, param_name);
            defer allocator.free(name_z);

            const param_ptr = c.halpr_find_param_by_name(name_z.ptr);
            if (param_ptr == null) continue;

            const param = param_ptr.*;

            // Get param type
            const param_type: PinType = switch (param.type) {
                c.HAL_BIT => .bit,
                c.HAL_FLOAT => .float,
                c.HAL_S32 => .s32,
                c.HAL_U32 => .u32,
                else => .float, // fallback
            };

            // Get param direction
            const param_dir: ParamDir = switch (param.dir) {
                c.HAL_RD => .in,
                c.HAL_WR => .out,
                c.HAL_RW => .rw,
                else => .rw, // fallback
            };

            // Get param value
            const param_value: HalValue = switch (param.type) {
                c.HAL_BIT => if (param.data.ptr) |d| .{ .bit = d.*.b != 0 } else HalValue{ .bit = false },
                c.HAL_FLOAT => if (param.data.ptr) |d| .{ .float = d.*.f } else HalValue{ .float = 0.0 },
                c.HAL_S32 => if (param.data.ptr) |d| .{ .s32 = d.*.s } else HalValue{ .s32 = 0 },
                c.HAL_U32 => if (param.data.ptr) |d| .{ .u32 = d.*.u } else HalValue{ .u32 = 0 },
                else => HalValue{ .float = 0.0 },
            };

            params[i] = ParamInfo{
                .name = try allocator.dupe(u8, param_name),
                .type = param_type,
                .dir = param_dir,
                .value = param_value,
            };
        }

        return params;
    }

    fn listComponents(ptr: *anyopaque, allocator: std.mem.Allocator) ![][]const u8 {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // Use halcmd to list components
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "halcmd", "list", "comp" },
        }) catch |err| {
            return err;
        };
        defer {
            allocator.free(result.stderr);
            allocator.free(result.stdout);
        }

        if (result.term != .Exited or result.term.Exited != 0) {
            return error.HalcmdFailed;
        }

        // Parse component names
        var components = std.ArrayList([]const u8).init(allocator);
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len > 0) {
                try components.append(try allocator.dupe(u8, trimmed));
            }
        }

        return components.toOwnedSlice();
    }

    fn getPinValue(ptr: *anyopaque, name: []const u8) !HalValue {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Use hal_get_pin_value_by_name
        var hal_type: c_int = undefined;
        var data_ptr: [*c][*c]c.hal_data_u = undefined;
        var connected: bool = undefined;

        const rc = c.hal_get_pin_value_by_name(name_z.ptr, &hal_type, &data_ptr, &connected);
        if (rc != 0) return error.PinNotFound;

        const data = data_ptr orelse return error.NotLinked;

        const hal_data = data.*.*;
        return switch (hal_type) {
            c.HAL_BIT => HalValue{ .bit = hal_data.b },
            c.HAL_FLOAT => HalValue{ .float = hal_data.f },
            c.HAL_S32 => HalValue{ .s32 = hal_data.s },
            c.HAL_U32 => HalValue{ .u32 = hal_data.u },
            else => error.InvalidHalType,
        };
    }

    fn setPinValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Get data_ptr using hal_get_pin_value_by_name
        var hal_type: c_int = undefined;
        var data_ptr: [*c][*c]c.hal_data_u = undefined;
        var connected: bool = undefined;

        const rc = c.hal_get_pin_value_by_name(name_z.ptr, &hal_type, &data_ptr, &connected);
        if (rc != 0) return error.PinNotFound;

        const data = data_ptr orelse return error.NotLinked;
        const hal_data = data.*;

        switch (value) {
            .bit => |v| hal_data.*.b = v,
            .float => |v| hal_data.*.f = v,
            .s32 => |v| hal_data.*.s = v,
            .u32 => |v| hal_data.*.u = v,
        }
    }

    fn getParamValue(ptr: *anyopaque, name: []const u8) !HalValue {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Use hal_get_param_value_by_name
        var hal_type: c_int = undefined;
        var data_ptr: [*c][*c]c.hal_data_u = undefined;

        const rc = c.hal_get_param_value_by_name(name_z.ptr, &hal_type, &data_ptr);
        if (rc != 0) return error.ParamNotFound;

        const data = data_ptr orelse return error.ParamNotFound;

        const hal_data = data.*;

        return switch (hal_type) {
            c.HAL_BIT => HalValue{ .bit = hal_data.*.b },
            c.HAL_FLOAT => HalValue{ .float = hal_data.*.f },
            c.HAL_S32 => HalValue{ .s32 = hal_data.*.s },
            c.HAL_U32 => HalValue{ .u32 = hal_data.*.u },
            else => error.InvalidHalType,
        };
    }

    fn setParamValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Get param data_ptr using hal_get_param_value_by_name
        var hal_type: c_int = undefined;
        var data_ptr: [*c][*c]c.hal_data_u = undefined;

        const rc = c.hal_get_param_value_by_name(name_z.ptr, &hal_type, &data_ptr);
        if (rc != 0) return error.ParamNotFound;

        const data = data_ptr orelse return error.ParamNotFound;
        const hal_data = data.*;

        switch (value) {
            .bit => |v| hal_data.*.b = v,
            .float => |v| hal_data.*.f = v,
            .s32 => |v| hal_data.*.s = v,
            .u32 => |v| hal_data.*.u = v,
        }
    }

    fn createSignal(ptr: *anyopaque, name: []const u8, pin_type: PinType) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        const rc = c.hal_signal_new(name_z.ptr, @intFromEnum(pin_type));
        if (rc < 0) return error.InitFailed;
    }

    fn deleteSignal(ptr: *anyopaque, name: []const u8) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        const rc = c.hal_signal_delete(name_z.ptr);
        if (rc < 0) return error.SignalNotFound;
    }

    fn linkPin(ptr: *anyopaque, pin_name: []const u8, sig_name: []const u8) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const pin_z = try toCStr(self.allocator, pin_name);
        defer self.allocator.free(pin_z);
        const sig_z = try toCStr(self.allocator, sig_name);
        defer self.allocator.free(sig_z);

        const rc = c.hal_link(pin_z.ptr, sig_z.ptr);
        if (rc < 0) return error.LinkFailed;
    }

    fn unlinkPin(ptr: *anyopaque, pin_name: []const u8) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, pin_name);
        defer self.allocator.free(name_z);

        const rc = c.hal_unlink(name_z.ptr);
        if (rc < 0) return error.UnlinkFailed;
    }
};

// Additional errors
const LinkFailed = error.LinkFailed;
const UnlinkFailed = error.UnlinkFailed;
const SignalNotFound = error.SignalNotFound;
const InitFailed = error.InitFailed;
const NotReady = error.NotReady;
