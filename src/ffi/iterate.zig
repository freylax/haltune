// Direct HAL enumeration through shared memory
//
// This module provides functions to iterate through HAL pins, signals, and
// parameters by directly accessing HAL shared memory and using HAL C API functions.
// This replaces the halcmd-based approach for better performance and reliability.
//
// Design principles:
// - Use halpr_find_*_by_owner() to iterate through all items
// - Access hal_data directly via hal_shmem_base for signal iteration
// - No subprocess overhead

const std = @import("std");

// C imports are provided via module import by build.zig
const c_import = @import("c.zig");
const c = c_import.c;

// Constants from c.zig
const HAL_NAME_LEN = c_import.HAL_NAME_LEN;

// Use hal_shmem_base from c.zig - don't redeclare it
const hal_shmem_base = c_import.hal_shmem_base;

// Import backend types for return values
const backend = @import("hal/backend");
const PinInfo = backend.PinInfo;
const SignalInfo = backend.SignalInfo;
const ParamInfo = backend.ParamInfo;
const PinType = backend.PinType;
const PinDir = backend.PinDir;
const ParamDir = backend.ParamDir;
const HalValue = backend.HalValue;

// HAL component structure for iteration (from hal_priv.h)
pub const hal_comp_t = extern struct {
    next_ptr: [*c]hal_comp_t,
    comp_id: c_int,
    name: [HAL_NAME_LEN + 1]u8,
};

// HAL pin structure for iteration (from hal_priv.h)
pub const hal_pin_t = extern struct {
    next_ptr: [*c]hal_pin_t,
    data_ptr_addr: ?*anyopaque,
    owner_ptr: ?*anyopaque,
    signal: ?*anyopaque,
    dummysig: c.hal_data_u,
    oldname: ?*anyopaque,
    type: c_int,
    dir: c_int,
    name: [HAL_NAME_LEN + 1]u8,
};

// HAL param structure for iteration (from hal_priv.h)
pub const hal_param_t = extern struct {
    next_ptr: [*c]hal_param_t,
    data_ptr: ?*anyopaque,
    owner_ptr: ?*anyopaque,
    oldname: ?*anyopaque,
    type: c_int,
    dir: c_int,
    name: [HAL_NAME_LEN + 1]u8,
};

// HAL signal structure for iteration (from hal_priv.h)
pub const hal_sig_t = extern struct {
    next_ptr: [*c]hal_sig_t,
    data_ptr: ?*anyopaque,
    writers: ?*anyopaque,
    readers: ?*anyopaque,
    oldname: ?*anyopaque,
    type: c_int,
    name: [HAL_NAME_LEN + 1]u8,
};

/// Get pin type from HAL type constant
fn pinTypeFromHal(hal_type: c_int) PinType {
    return switch (hal_type) {
        c.HAL_BIT => .bit,
        c.HAL_FLOAT => .float,
        c.HAL_S32 => .s32,
        c.HAL_U32 => .u32,
        else => .float,
    };
}

/// Get pin direction from HAL direction constant
fn pinDirFromHal(hal_dir: c_int) PinDir {
    return switch (hal_dir) {
        c_import.HAL_IN, c_import.HAL_IO => .in,
        c_import.HAL_OUT => .out,
        else => .in,
    };
}

/// Get param direction from HAL direction constant
fn paramDirFromHal(hal_dir: c_int) ParamDir {
    return switch (hal_dir) {
        c_import.HAL_RO => .in,
        c_import.HAL_RW => .rw,
        else => .rw,
    };
}

/// Read HAL value from a data pointer and type
fn readHalValue(data_ptr: ?*anyopaque, hal_type: c_int) HalValue {
    if (data_ptr == null) return HalValue{ .float = 0.0 };

    switch (hal_type) {
        c.HAL_BIT => {
            const ptr: *const u8 = @ptrCast(@alignCast(data_ptr));
            return HalValue{ .bit = ptr.* != 0 };
        },
        c.HAL_FLOAT => {
            const ptr: *const f64 = @ptrCast(@alignCast(data_ptr));
            return HalValue{ .float = ptr.* };
        },
        c.HAL_S32 => {
            const ptr: *const i32 = @ptrCast(@alignCast(data_ptr));
            return HalValue{ .s32 = ptr.* };
        },
        c.HAL_U32 => {
            const ptr: *const u32 = @ptrCast(@alignCast(data_ptr));
            return HalValue{ .u32 = ptr.* };
        },
        else => return HalValue{ .float = 0.0 },
    }
}

/// Helper to find valid list pointer by trying common offsets
fn findListPtr(comptime T: type, offsets: []const usize) ?*T {
    for (offsets) |offset| {
        const base_addr = @intFromPtr(hal_shmem_base) + offset;
        const list_bytes = @as([*]u8, @ptrFromInt(base_addr))[0..@sizeOf([*c]T)];
        const list_ptr = std.mem.bytesAsValue([*c]T, list_bytes).*;

        if (list_ptr != null) {
            const ptr_addr = @intFromPtr(list_ptr);
            const base_addr_int = @intFromPtr(hal_shmem_base);

            // Check if pointer is in a reasonable range (within 1MB of base)
            if (ptr_addr > base_addr_int and ptr_addr < base_addr_int + 1024 * 1024) {
                return list_ptr;
            }
        }
    }
    return null;
}

/// Pin list offsets to try for different architectures
const PIN_LIST_OFFSETS = [_]usize{ 76, 80, 84, 88, 96 };

/// Signal list offsets (4 bytes after pin list)
const SIG_LIST_OFFSETS = [_]usize{ 80, 84, 88, 92, 100 };

/// Param list offsets (8 bytes after pin list)
const PARAM_LIST_OFFSETS = [_]usize{ 84, 88, 92, 96, 104 };

// Iterate through all pins and return full PinInfo array
pub fn iterPins(allocator: std.mem.Allocator) ![]PinInfo {
    std.log.scoped(.hal_iterate).info("iterPins: starting iteration", .{});

    const hal_data_pin_list = findListPtr(hal_pin_t, &PIN_LIST_OFFSETS);
    if (hal_data_pin_list == null) {
        std.log.scoped(.hal_iterate).warn("iterPins: could not find pin list pointer!", .{});
        return &[_]PinInfo{};
    }

    // First count pins
    var count: usize = 0;
    {
        var current_pin: ?*const hal_pin_t = hal_data_pin_list;
        while (current_pin) |pin| {
            count += 1;
            current_pin = pin.next_ptr;
        }
        std.log.scoped(.hal_iterate).info("iterPins: found {d} pins", .{count});
    }

    if (count == 0) {
        std.log.scoped(.hal_iterate).warn("iterPins: no pins found!", .{});
        return &[_]PinInfo{};
    }

    // Allocate result array
    const pins = try allocator.alloc(PinInfo, count);
    errdefer allocator.free(pins);

    // Iterate to fill in data
    var i: usize = 0;
    var current_pin: ?*const hal_pin_t = hal_data_pin_list;
    while (current_pin) |pin| {
        // Get pin name
        const name_len = std.mem.sliceTo(&pin.name, 0).len;
        const name = try allocator.alloc(u8, name_len);
        @memcpy(name, pin.name[0..name_len]);

        const pin_type = pinTypeFromHal(pin.type);
        const pin_dir = pinDirFromHal(pin.dir);

        // Get pin value - data_ptr_addr points to the data pointer
        const data_ptr_ptr: *const ?*anyopaque = @ptrCast(@alignCast(&pin.data_ptr_addr));
        const data_ptr = data_ptr_ptr.*;
        const pin_value = readHalValue(data_ptr, pin.type);

        pins[i] = PinInfo{
            .name = name,
            .type = pin_type,
            .dir = pin_dir,
            .value = pin_value,
        };

        i += 1;
        current_pin = pin.next_ptr;
    }

    return pins;
}

// Iterate through all signals and return full SignalInfo array
pub fn iterSignals(allocator: std.mem.Allocator) ![]SignalInfo {
    const hal_data_sig_list = findListPtr(hal_sig_t, &SIG_LIST_OFFSETS);
    if (hal_data_sig_list == null) return &[_]SignalInfo{};

    // First count signals
    var count: usize = 0;
    {
        var current_sig: ?*const hal_sig_t = hal_data_sig_list;
        while (current_sig) |sig| {
            count += 1;
            current_sig = sig.next_ptr;
        }
    }

    if (count == 0) return &[_]SignalInfo{};

    // Allocate result array
    const signals = try allocator.alloc(SignalInfo, count);
    errdefer allocator.free(signals);

    // Iterate to fill in data
    var i: usize = 0;
    var current_sig: ?*const hal_sig_t = hal_data_sig_list;
    while (current_sig) |sig| {
        // Get signal name
        const name_len = std.mem.sliceTo(&sig.name, 0).len;
        const name = try allocator.alloc(u8, name_len);
        @memcpy(name, sig.name[0..name_len]);

        const sig_type = pinTypeFromHal(sig.type);
        const sig_value = readHalValue(sig.data_ptr, sig.type);

        // For now, empty writers/readers - would need more complex iteration
        signals[i] = SignalInfo{
            .name = name,
            .type = sig_type,
            .value = sig_value,
            .writers = &[_][]const u8{},
            .readers = &[_][]const u8{},
        };

        i += 1;
        current_sig = sig.next_ptr;
    }

    return signals;
}

// Iterate through all params and return full ParamInfo array
pub fn iterParams(allocator: std.mem.Allocator) ![]ParamInfo {
    const hal_data_param_list = findListPtr(hal_param_t, &PARAM_LIST_OFFSETS);
    if (hal_data_param_list == null) return &[_]ParamInfo{};

    // First count params
    var count: usize = 0;
    {
        var current_param: ?*const hal_param_t = hal_data_param_list;
        while (current_param) |param| {
            count += 1;
            current_param = param.next_ptr;
        }
    }

    if (count == 0) return &[_]ParamInfo{};

    // Allocate result array
    const params = try allocator.alloc(ParamInfo, count);
    errdefer allocator.free(params);

    // Iterate to fill in data
    var i: usize = 0;
    var current_param: ?*const hal_param_t = hal_data_param_list;
    while (current_param) |param| {
        // Get param name
        const name_len = std.mem.sliceTo(&param.name, 0).len;
        const name = try allocator.alloc(u8, name_len);
        @memcpy(name, param.name[0..name_len]);

        const param_type = pinTypeFromHal(param.type);
        const param_dir = paramDirFromHal(param.dir);
        const param_value = readHalValue(param.data_ptr, param.type);

        params[i] = ParamInfo{
            .name = name,
            .type = param_type,
            .dir = param_dir,
            .value = param_value,
        };

        i += 1;
        current_param = param.next_ptr;
    }

    return params;
}

// Backwards compatible - return name lists only
pub fn iterPinNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 64);

    const hal_data_pin_list = findListPtr(hal_pin_t, &PIN_LIST_OFFSETS);
    if (hal_data_pin_list == null) return result;

    var current_pin: ?*const hal_pin_t = hal_data_pin_list;
    while (current_pin) |pin| {
        const name = try allocator.dupe(u8, std.mem.sliceTo(&pin.name, 0));
        try result.append(name);
        current_pin = pin.next_ptr;
    }

    return result;
}

pub fn iterParamNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 64);

    const hal_data_param_list = findListPtr(hal_param_t, &PARAM_LIST_OFFSETS);
    if (hal_data_param_list == null) return result;

    var current_param: ?*const hal_param_t = hal_data_param_list;
    while (current_param) |param| {
        const name = try allocator.dupe(u8, std.mem.sliceTo(&param.name, 0));
        try result.append(name);
        current_param = param.next_ptr;
    }

    return result;
}

pub fn iterSignalNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 64);

    const hal_data_sig_list = findListPtr(hal_sig_t, &SIG_LIST_OFFSETS);
    if (hal_data_sig_list == null) return result;

    var current_sig: ?*const hal_sig_t = hal_data_sig_list;
    while (current_sig) |sig| {
        const name = try allocator.dupe(u8, std.mem.sliceTo(&sig.name, 0));
        try result.append(name);
        current_sig = sig.next_ptr;
    }

    return result;
}
