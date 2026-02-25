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

        // TODO: Implement by iterating over hal_data
        return allocator.alloc(PinInfo, 0);
    }

    fn listSignals(ptr: *anyopaque, allocator: std.mem.Allocator) ![]SignalInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // TODO: Implement by iterating over hal_data
        return allocator.alloc(SignalInfo, 0);
    }

    fn listParams(ptr: *anyopaque, allocator: std.mem.Allocator) ![]ParamInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // TODO: Implement by iterating over hal_data
        return allocator.alloc(ParamInfo, 0);
    }

    fn listComponents(ptr: *anyopaque, allocator: std.mem.Allocator) ![][]const u8 {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        // TODO: Implement by iterating over hal_data
        return allocator.alloc([]const u8, 0);
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

        return switch (hal_type) {
            c.HAL_BIT => HalValue{ .bit = if (data.*.*.b != 0) true else false },
            c.HAL_FLOAT => HalValue{ .float = data.*.*.f },
            c.HAL_S32 => HalValue{ .s32 = data.*.*.s },
            c.HAL_U32 => HalValue{ .u32 = data.*.*.u },
            else => error.InvalidHalType,
        };
    }

    fn setPinValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Find pin by name to get its data_ptr
        const pin_ptr = c.halpr_find_pin_by_name(name_z.ptr);
        if (pin_ptr == null) return error.PinNotFound;

        // Set value based on type - write directly to pin's data_ptr
        // Note: We can't access pin fields directly due to opaque type
        // For now, we need to use hal_pin_*_set functions if available
        // Or we can use the data_ptr from hal_get_pin_value_by_name above

        // Get data_ptr first
        var hal_type: c_int = undefined;
        var data_ptr2: [*c][*c]c.hal_data_u = undefined;
        var connected: bool = undefined;

        const rc = c.hal_get_pin_value_by_name(name_z.ptr, &hal_type, &data_ptr2, &connected);
        if (rc != 0) return error.PinNotFound;

        const data = data_ptr2 orelse return error.NotLinked;

        switch (value) {
            .bit => |v| data.*.*.b = @intFromBool(v),
            .float => |v| data.*.*.f = v,
            .s32 => |v| data.*.*.s = v,
            .u32 => |v| data.*.*.u = v,
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

        return switch (hal_type) {
            c.HAL_BIT => HalValue{ .bit = if (data.*.*.b != 0) true else false },
            c.HAL_FLOAT => HalValue{ .float = data.*.*.f },
            c.HAL_S32 => HalValue{ .s32 = data.*.*.s },
            c.HAL_U32 => HalValue{ .u32 = data.*.*.u },
            else => error.InvalidHalType,
        };
    }

    fn setParamValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Get param data_ptr
        const param_ptr = c.halpr_find_param_by_name(name_z.ptr);
        if (param_ptr == null) return error.ParamNotFound;

        // For setting, we need to access the param's data_ptr
        // Since types are opaque, we need to use hal_param_*_set functions
        // Or directly access the data pointer offset
        // For now, let's use a workaround: get the value first to get data_ptr

        var hal_type: c_int = undefined;
        var data_ptr: [*c][*c]c.hal_data_u = undefined;

        const rc = c.hal_get_param_value_by_name(name_z.ptr, &hal_type, &data_ptr);
        if (rc != 0) return error.ParamNotFound;

        const data = data_ptr orelse return error.ParamNotFound;

        switch (value) {
            .bit => |v| data.*.*.b = @intFromBool(v),
            .float => |v| data.*.*.f = v,
            .s32 => |v| data.*.*.s = v,
            .u32 => |v| data.*.*.u = v,
        }
    }

    fn createSignal(ptr: *anyopaque, name: []const u8, pin_type: PinType) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        const sig_ptr = c.hal_signal_new(name_z.ptr, @intFromEnum(pin_type));
        if (sig_ptr == null) return error.InitFailed;
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
