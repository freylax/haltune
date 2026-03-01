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
const ffi_c_module = @import("ffi-c");
const c = ffi_c_module.c;

// Direct HAL enumeration using iterate module
const iterate = @import("ffi-iterate");

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

        std.log.scoped(.hal_native).info("listPins: calling iterate.iterPins", .{});

        // Use direct HAL enumeration
        const result = try iterate.iterPins(allocator);
        std.log.scoped(.hal_native).info("listPins: got {d} pins", .{result.len});
        return result;
    }

    fn listSignals(ptr: *anyopaque, allocator: std.mem.Allocator) ![]SignalInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // Use direct HAL enumeration
        return iterate.iterSignals(allocator);
    }

    fn listParams(ptr: *anyopaque, allocator: std.mem.Allocator) ![]ParamInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // Use direct HAL enumeration
        return iterate.iterParams(allocator);
    }

    fn listComponents(ptr: *anyopaque, allocator: std.mem.Allocator) ![][]const u8 {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // Use halcmd to list components
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "halcmd", "list", "comp" },
        }) catch |err| {
            std.log.scoped(.hal_native).err("halcmd list comp failed: {}", .{err});
            return error.UnexpectedResponse;
        };
        defer {
            allocator.free(result.stderr);
            allocator.free(result.stdout);
        }

        if (result.term != .Exited or result.term.Exited != 0) {
            return error.UnexpectedResponse;
        }

        // Parse component names
        var components = try std.ArrayList([]const u8).initCapacity(allocator, 8);
        defer components.deinit(allocator);
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len > 0) {
                try components.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }

        return components.toOwnedSlice(allocator);
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
