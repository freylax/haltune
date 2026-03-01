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

// Manual extern declarations for discovery functions (module level in c.zig)
const halpr_find_pin_by_owner = c_import.halpr_find_pin_by_owner;
const halpr_find_param_by_owner = c_import.halpr_find_param_by_owner;

// Constants from c.zig
const HAL_NAME_LEN = c_import.HAL_NAME_LEN;
const HAL_DATA_SIG_LIST_OFFSET = c_import.HAL_DATA_SIG_LIST_OFFSET;
extern var hal_shmem_base: [*c]u8;

// Import backend types for return values
const backend = @import("hal/backend");
const PinInfo = backend.PinInfo;
const SignalInfo = backend.SignalInfo;
const ParamInfo = backend.ParamInfo;
const PinType = backend.PinType;
const PinDir = backend.PinDir;
const ParamDir = backend.ParamDir;
const HalValue = backend.HalValue;

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

// Iterate through all pins and return full PinInfo array
pub fn iterPins(allocator: std.mem.Allocator) ![]PinInfo {
    std.log.scoped(.hal_iterate).info("iterPins: starting iteration", .{});

    // First count pins by iterating once
    var count: usize = 0;
    {
        var current_pin: ?*anyopaque = null;
        while (true) {
            const pin_ptr = halpr_find_pin_by_owner(null, current_pin);
            if (pin_ptr == null) break;
            count += 1;
            current_pin = pin_ptr;
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

    // Iterate again to fill in data
    var i: usize = 0;
    var current_pin: ?*anyopaque = null;
    while (true) {
        const pin_ptr = halpr_find_pin_by_owner(null, current_pin);
        if (pin_ptr == null) break;

        const pin: *const hal_pin_t = @ptrCast(@alignCast(pin_ptr));

        // Get pin name (null-terminated)
        const name_len = std.mem.sliceTo(&pin.name, 0).len;
        const name = try allocator.alloc(u8, name_len);
        @memcpy(name, pin.name[0..name_len]);

        // Get pin type and direction
        const pin_type = pinTypeFromHal(pin.type);
        const pin_dir = pinDirFromHal(pin.dir);

        // Get pin value
        // data_ptr_addr is a pointer to the data pointer
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
        current_pin = pin_ptr;
    }

    return pins;
}

// Iterate through all signals and return full SignalInfo array
pub fn iterSignals(allocator: std.mem.Allocator) ![]SignalInfo {
    // Access signal list head from hal_data via shared memory base
    const hal_data_sig_list = @as(
        [*c][*c]hal_sig_t,
        @ptrFromInt(@intFromPtr(hal_shmem_base) + HAL_DATA_SIG_LIST_OFFSET),
    );

    // First count signals
    var count: usize = 0;
    {
        var current_sig: ?*const hal_sig_t = hal_data_sig_list.*;
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
    var current_sig: ?*const hal_sig_t = hal_data_sig_list.*;
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
    // First count params
    var count: usize = 0;
    {
        var current_param: ?*anyopaque = null;
        while (true) {
            const param_ptr = halpr_find_param_by_owner(null, current_param);
            if (param_ptr == null) break;
            count += 1;
            current_param = param_ptr;
        }
    }

    if (count == 0) return &[_]ParamInfo{};

    // Allocate result array
    const params = try allocator.alloc(ParamInfo, count);
    errdefer allocator.free(params);

    // Iterate again to fill in data
    var i: usize = 0;
    var current_param: ?*anyopaque = null;
    while (true) {
        const param_ptr = halpr_find_param_by_owner(null, current_param);
        if (param_ptr == null) break;

        const param: *const hal_param_t = @ptrCast(@alignCast(param_ptr));

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
        current_param = param_ptr;
    }

    return params;
}

// Backwards compatible - return name lists only
pub fn iterPinNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 64);
    var current_pin: ?*anyopaque = null;

    while (true) {
        const pin_ptr = halpr_find_pin_by_owner(null, current_pin);
        if (pin_ptr == null) break;

        const pin: *const hal_pin_t = @ptrCast(@alignCast(pin_ptr));
        const name = try allocator.dupe(u8, std.mem.sliceTo(&pin.name, 0));
        try result.append(allocator, name);

        current_pin = pin_ptr;
    }

    return result;
}

pub fn iterParamNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 64);
    var current_param: ?*anyopaque = null;

    while (true) {
        const param_ptr = halpr_find_param_by_owner(null, current_param);
        if (param_ptr == null) break;

        const param: *const hal_param_t = @ptrCast(@alignCast(param_ptr));
        const name = try allocator.dupe(u8, std.mem.sliceTo(&param.name, 0));
        try result.append(allocator, name);

        current_param = param_ptr;
    }

    return result;
}

pub fn iterSignalNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 64);

    const hal_data_ptr = @as([*c]hal_sig_t, @ptrFromInt(@intFromPtr(c.hal_shmem_base) + HAL_DATA_SIG_LIST_OFFSET));
    var current_sig: ?*const c.hal_sig_t = hal_data_ptr.*;

    while (current_sig) |sig| {
        const name = try allocator.dupe(u8, std.mem.sliceTo(&sig.name, 0));
        try result.append(allocator, name);
        current_sig = sig.next_ptr;
    }

    return result;
}
