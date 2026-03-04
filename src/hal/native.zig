// Native HAL Backend
//
// This implementation uses direct HAL FFI calls with halpr_find_pin_by_name
// to access pin structures directly, avoiding name-based lookup issues.

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
const c = @import("ffi/c.zig").c;

// Discovery helpers using halcmd (for now - direct HAL access needs more work)
const discovery = @import("ffi-safe-discovery");

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

    /// Find a pin by name using halpr_find_pin_by_name
    fn findPinByName(name: [*:0]const u8) ?*const c.hal_pin_t {
        const pin_opaque = c.halpr_find_pin_by_name(name);
        if (pin_opaque == null) {
            std.log.err("DEBUG: halpr_find_pin_by_name('{s}') returned null", .{name});
            return null;
        }
        return @as(*const c.hal_pin_t, @alignCast(@ptrCast(pin_opaque)));
    }

    /// Read pin value using direct structure access
    /// When pin is linked, value is at data_ptr_addr
    /// When pin is unlinked, value is in dummysig field
    fn readPinValue(pin: *const c.hal_pin_t, pin_type: c_int) HalValue {
        // Check if pin is linked to a signal (signal field is non-null)
        const is_linked = pin.signal != null;

        if (is_linked and pin.data_ptr_addr != null) {
            // Pin is linked - read from signal data via data_ptr_addr
            const data_ptr = @as([*c]c.hal_data_u, @alignCast(@ptrCast(pin.data_ptr_addr)));
            return switch (pin_type) {
                c.HAL_BIT => HalValue{ .bit = data_ptr.*.b },
                c.HAL_FLOAT => HalValue{ .float = data_ptr.*.f },
                c.HAL_S32 => HalValue{ .s32 = data_ptr.*.s },
                c.HAL_U32 => HalValue{ .u32 = data_ptr.*.u },
                else => HalValue{ .float = 0.0 },
            };
        } else {
            // Pin is unlinked - read from dummysig field in pin structure
            const dummy = pin.dummysig;
            return switch (pin_type) {
                c.HAL_BIT => HalValue{ .bit = dummy.b },
                c.HAL_FLOAT => HalValue{ .float = dummy.f },
                c.HAL_S32 => HalValue{ .s32 = dummy.s },
                c.HAL_U32 => HalValue{ .u32 = dummy.u },
                else => HalValue{ .float = 0.0 },
            };
        }
    }

    fn listPins(ptr: *anyopaque, allocator: std.mem.Allocator) ![]PinInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;

        std.log.scoped(.hal_native).info("listPins: Starting discovery via halcmd show pin", .{});

        // Use halcmd show pin to get all pins with details in a single call
        var pin_details = discovery.listPinsDetail(allocator) catch |err| {
            std.log.scoped(.hal_native).err("listPinsDetail failed: {}", .{err});
            return error.UnexpectedResponse;
        };
        defer {
            for (pin_details.items) |p| allocator.free(p.name);
            pin_details.deinit(allocator);
        }

        // Allocate result array
        const pins = try allocator.alloc(PinInfo, pin_details.items.len);
        errdefer allocator.free(pins);

        // Convert discovery.PinDetail to backend.PinInfo
        for (pin_details.items, 0..) |detail, i| {
            const pin_type: PinType = switch (detail.type) {
                .bit => .bit,
                .float => .float,
                .s32 => .s32,
                .u32 => .u32,
            };

            const pin_dir: PinDir = switch (detail.dir) {
                .in => .in,
                .out => .out,
                .io => .io,
                .unspecified => .in,
            };

            // Convert f64 to appropriate HalValue based on type
            const pin_value: HalValue = switch (detail.type) {
                .bit => HalValue{ .bit = detail.value != 0 },
                .float => HalValue{ .float = detail.value },
                .s32 => HalValue{ .s32 = @intFromFloat(detail.value) },
                .u32 => HalValue{ .u32 = @intFromFloat(detail.value) },
            };

            // Debug: Log first few pins
            if (i < 5) {
                std.log.err("DEBUG: pin {} name='{s}' type={} dir={} value={}", .{ i, detail.name, pin_type, pin_dir, pin_value });
            }

            pins[i] = PinInfo{
                .name = try allocator.dupe(u8, detail.name),
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
        var sig_names = discovery.listSignalNames(allocator) catch |err| {
            std.log.scoped(.hal_native).err("listSignalNames failed: {}", .{err});
            return error.UnexpectedResponse;
        };
        defer {
            for (sig_names.items) |n| allocator.free(n);
            sig_names.deinit(allocator);
        }

        // Allocate result array
        const signals = try allocator.alloc(SignalInfo, sig_names.items.len);
        errdefer allocator.free(signals);

        // Get details for each signal using halpr_find_sig_by_name
        for (sig_names.items, 0..) |sig_name, i| {
            const name_z = try toCStr(allocator, sig_name);
            defer allocator.free(name_z);

            // Use halpr_find_sig_by_name to get signal structure
            const sig_ptr = c.halpr_find_sig_by_name(name_z.ptr);

            const sig_value: HalValue = if (sig_ptr) |p| blk: {
                const sig = @as(*const c.hal_sig_t, @alignCast(@ptrCast(p)));
                // Signal value is stored directly in the data union
                break :blk switch (sig.type) {
                    c.HAL_BIT => HalValue{ .bit = sig.data.b },
                    c.HAL_FLOAT => HalValue{ .float = sig.data.f },
                    c.HAL_S32 => HalValue{ .s32 = sig.data.s },
                    c.HAL_U32 => HalValue{ .u32 = sig.data.u },
                    else => HalValue{ .float = 0.0 },
                };
            } else HalValue{ .float = 0.0 };

            const sig_type: PinType = if (sig_ptr) |p| blk: {
                const sig = @as(*const c.hal_sig_t, @alignCast(@ptrCast(p)));
                break :blk switch (sig.type) {
                    c.HAL_BIT => .bit,
                    c.HAL_FLOAT => .float,
                    c.HAL_S32 => .s32,
                    c.HAL_U32 => .u32,
                    else => .float,
                };
            } else .float;

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
        var param_names = discovery.listParamNames(allocator) catch |err| {
            std.log.scoped(.hal_native).err("listParamNames failed: {}", .{err});
            return error.UnexpectedResponse;
        };
        defer {
            for (param_names.items) |n| allocator.free(n);
            param_names.deinit(allocator);
        }

        // Allocate result array
        const params = try allocator.alloc(ParamInfo, param_names.items.len);
        errdefer allocator.free(params);

        // Get details for each param using halpr_find_param_by_name
        for (param_names.items, 0..) |param_name, i| {
            const name_z = try toCStr(allocator, param_name);
            defer allocator.free(name_z);

            // Use halpr_find_param_by_name to get param structure
            const param_ptr = c.halpr_find_param_by_name(name_z.ptr);

            const param_value: HalValue = if (param_ptr) |p| blk: {
                const param = @as(*const c.hal_param_t, @alignCast(@ptrCast(p)));
                if (param.data_ptr) |data_ptr| {
                    const data = @as(*c.hal_data_u, @alignCast(@ptrCast(data_ptr)));
                    break :blk switch (param.type) {
                        c.HAL_BIT => HalValue{ .bit = data.b },
                        c.HAL_FLOAT => HalValue{ .float = data.f },
                        c.HAL_S32 => HalValue{ .s32 = data.s },
                        c.HAL_U32 => HalValue{ .u32 = data.u },
                        else => HalValue{ .float = 0.0 },
                    };
                } else break :blk HalValue{ .float = 0.0 };
            } else HalValue{ .float = 0.0 };

            const param_type: PinType = if (param_ptr) |p| blk: {
                const param = @as(*const c.hal_param_t, @alignCast(@ptrCast(p)));
                break :blk switch (param.type) {
                    c.HAL_BIT => .bit,
                    c.HAL_FLOAT => .float,
                    c.HAL_S32 => .s32,
                    c.HAL_U32 => .u32,
                    else => .float,
                };
            } else .float;

            // Get direction from param structure
            const param_dir: ParamDir = if (param_ptr) |p| blk: {
                const param = @as(*const c.hal_param_t, @alignCast(@ptrCast(p)));
                break :blk switch (param.dir) {
                    c.HAL_RO => .in,
                    c.HAL_RW => .out,
                    else => .in,
                };
            } else .in;

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

        // Parse component names, sanitizing null bytes and other control characters
        var components = try std.ArrayList([]const u8).initCapacity(allocator, 8);
        defer components.deinit(allocator);
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            // Split by whitespace to get individual component names
            var iter = std.mem.tokenizeScalar(u8, line, ' ');
            while (iter.next()) |comp_name| {
                // Filter out null bytes and other non-printable characters
                var sanitized = try std.ArrayList(u8).initCapacity(allocator, comp_name.len);
                defer sanitized.deinit(allocator);
                for (comp_name) |char| {
                    if (char >= 32 and char <= 126) { // Printable ASCII
                        try sanitized.append(allocator, char);
                    }
                }
                if (sanitized.items.len > 0) {
                    try components.append(allocator, try allocator.dupe(u8, sanitized.items));
                }
            }
        }

        return components.toOwnedSlice(allocator);
    }

    fn getPinValue(ptr: *anyopaque, name: []const u8) !HalValue {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Use halpr_find_pin_by_name to get pin structure
        const pin_ptr = c.halpr_find_pin_by_name(name_z.ptr);
        if (pin_ptr == null) return error.PinNotFound;

        const pin = @as(*const c.hal_pin_t, @alignCast(@ptrCast(pin_ptr)));
        return readPinValue(pin, pin.type);
    }

    fn setPinValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Use halpr_find_pin_by_name to get pin structure
        const pin_ptr = c.halpr_find_pin_by_name(name_z.ptr);
        if (pin_ptr == null) return error.PinNotFound;

        const pin = @as(*c.hal_pin_t, @alignCast(@ptrCast(pin_ptr)));

        // Check if pin is linked
        const is_linked = pin.signal != null;

        if (is_linked and pin.data_ptr_addr != null) {
            // Pin is linked - write to signal data via data_ptr_addr
            const data_ptr = @as([*c]c.hal_data_u, @alignCast(@ptrCast(pin.data_ptr_addr)));
            switch (value) {
                .bit => |v| data_ptr.*.b = v,
                .float => |v| data_ptr.*.f = v,
                .s32 => |v| data_ptr.*.s = v,
                .u32 => |v| data_ptr.*.u = v,
            }
        } else {
            // Pin is unlinked - write to dummysig field
            switch (value) {
                .bit => |v| pin.dummysig.b = v,
                .float => |v| pin.dummysig.f = v,
                .s32 => |v| pin.dummysig.s = v,
                .u32 => |v| pin.dummysig.u = v,
            }
        }
    }

    fn getParamValue(ptr: *anyopaque, name: []const u8) !HalValue {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Use halpr_find_param_by_name to get param structure
        const param_ptr = c.halpr_find_param_by_name(name_z.ptr);
        if (param_ptr == null) return error.ParamNotFound;

        const param = @as(*const c.hal_param_t, @alignCast(@ptrCast(param_ptr)));
        const data_ptr = param.data_ptr orelse return error.ParamNotFound;

        const data = @as(*c.hal_data_u, @alignCast(@ptrCast(data_ptr)));

        return switch (param.type) {
            c.HAL_BIT => HalValue{ .bit = data.b },
            c.HAL_FLOAT => HalValue{ .float = data.f },
            c.HAL_S32 => HalValue{ .s32 = data.s },
            c.HAL_U32 => HalValue{ .u32 = data.u },
            else => error.InvalidHalType,
        };
    }

    fn setParamValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        // Use halpr_find_param_by_name to get param structure
        const param_ptr = c.halpr_find_param_by_name(name_z.ptr);
        if (param_ptr == null) return error.ParamNotFound;

        const param = @as(*c.hal_param_t, @alignCast(@ptrCast(param_ptr)));
        const data_ptr = param.data_ptr orelse return error.ParamNotFound;

        const data = @as(*c.hal_data_u, @alignCast(@ptrCast(data_ptr)));

        switch (value) {
            .bit => |v| data.b = v,
            .float => |v| data.f = v,
            .s32 => |v| data.s = v,
            .u32 => |v| data.u = v,
        }
    }

    fn createSignal(ptr: *anyopaque, name: []const u8, pin_type: PinType) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const name_z = try toCStr(self.allocator, name);
        defer self.allocator.free(name_z);

        const rc = c.hal_signal_new(name_z.ptr, @intFromEnum(pin_type));
        if (rc < 0) {
            // Signal might already exist - try to link a dummy pin to verify
            // If link succeeds, signal exists and we can reuse it
            std.log.warn("hal_signal_new failed for '{s}', signal may already exist", .{name});
            // For now, just return error - caller should handle this
            return error.InitFailed;
        }
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
