// HAL Backend Interface
//
// This module defines a common interface for HAL operations.
// Multiple implementations can be provided:
// - NativeBackend: Direct HAL FFI calls (on LinuxCNC systems)
// - RemoteBackend: TCP client to hal_bridge_server
//
// The interface uses Zig's trait pattern with function pointers.

const std = @import("std");

/// HAL value union supporting all four HAL data types
pub const HalValue = union(enum) {
    /// Boolean value (HAL_BIT pins/signals)
    bit: bool,

    /// Floating-point value (HAL_FLOAT pins/signals)
    float: f64,

    /// Signed 32-bit integer (HAL_S32 pins/signals/params)
    s32: i32,

    /// Unsigned 32-bit integer (HAL_U32 pins/signals/params)
    u32: u32,
};

/// Pin information returned by discovery
pub const PinInfo = struct {
    name: []const u8,
    type: PinType,
    dir: PinDir,
    value: HalValue,
};

/// Signal information returned by discovery
pub const SignalInfo = struct {
    name: []const u8,
    type: PinType,
    value: HalValue,
    // Writers: pins that write to this signal
    writers: []const []const u8,
    // Readers: pins that read from this signal
    readers: []const []const u8,
};

/// Parameter information returned by discovery
pub const ParamInfo = struct {
    name: []const u8,
    type: PinType,
    dir: ParamDir,
    value: HalValue,
};

/// HAL data type
pub const PinType = enum(u8) {
    bit = 1,
    float = 2,
    s32 = 3,
    u32 = 4,

    pub fn fromHal(hal_type: c_int) !PinType {
        return switch (hal_type) {
            1 => .bit,
            2 => .float,
            3 => .s32,
            4 => .u32,
            else => error.InvalidHalType,
        };
    }

    pub fn toHal(comptime self: PinType) c_int {
        return @intFromEnum(self);
    }
};

/// Pin direction
pub const PinDir = enum(u8) {
    in = 1,
    out = 2,
    io = 3,

    pub fn fromHal(hal_dir: c_int) !PinDir {
        return switch (hal_dir) {
            1 => .in,
            2 => .out,
            3 => .io,
            else => error.InvalidHalDir,
        };
    }

    pub fn toHal(comptime self: PinDir) c_int {
        return @intFromEnum(self);
    }
};

/// Parameter direction
pub const ParamDir = enum(u8) {
    in = 16,  // HAL_RD
    out = 32, // HAL_WR
    rw = 48,  // HAL_RD | HAL_WR

    pub fn fromHal(hal_dir: c_int) !ParamDir {
        return switch (hal_dir) {
            16 => .in,
            32 => .out,
            48 => .rw,
            else => error.InvalidHalDir,
        };
    }
};

/// HAL Backend Interface
///
/// This uses Zig's trait pattern with function pointers.
/// All implementations must provide these functions.

/// Common error set for HAL backend operations
pub const HalError = error{
    InitFailed,
    NotReady,
    PinNotFound,
    SignalNotFound,
    ParamNotFound,
    NotLinked,
    InvalidHalType,
    InvalidHalDir,
    RemoteError,
    UnexpectedResponse,
    InvalidMessageType,
    InvalidHalValue,
    OutOfMemory,
};

pub const HalBackend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Clean up backend resources
        deinit: *const fn (ptr: *anyopaque) void,

        /// Initialize a HAL component
        initComponent: *const fn (ptr: *anyopaque, name: []const u8) HalError!c_int,

        /// Mark component as ready
        readyComponent: *const fn (ptr: *anyopaque, comp_id: c_int) HalError!void,

        /// Exit a HAL component
        exitComponent: *const fn (ptr: *anyopaque, comp_id: c_int) void,

        /// List all pins
        listPins: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) HalError![]PinInfo,

        /// List all signals
        listSignals: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) HalError![]SignalInfo,

        /// List all parameters
        listParams: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) HalError![]ParamInfo,

        /// List all components
        listComponents: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) HalError![][]const u8,

        /// Get pin value
        getPinValue: *const fn (ptr: *anyopaque, name: []const u8) HalError!HalValue,

        /// Set pin value
        setPinValue: *const fn (ptr: *anyopaque, name: []const u8, value: HalValue) HalError!void,

        /// Get parameter value
        getParamValue: *const fn (ptr: *anyopaque, name: []const u8) HalError!HalValue,

        /// Set parameter value
        setParamValue: *const fn (ptr: *anyopaque, name: []const u8, value: HalValue) HalError!void,

        /// Create a new signal
        createSignal: *const fn (ptr: *anyopaque, name: []const u8, pin_type: PinType) HalError!void,

        /// Delete a signal
        deleteSignal: *const fn (ptr: *anyopaque, name: []const u8) HalError!void,

        /// Link a pin to a signal
        linkPin: *const fn (ptr: *anyopaque, pin_name: []const u8, sig_name: []const u8) HalError!void,

        /// Unlink a pin from its signal
        unlinkPin: *const fn (ptr: *anyopaque, pin_name: []const u8) HalError!void,
    };

    /// Helper: Clean up backend resources
    pub fn deinit(self: HalBackend) void {
        self.vtable.deinit(self.ptr);
    }

    /// Helper: Initialize a HAL component
    pub fn initComponent(self: HalBackend, name: []const u8) !c_int {
        return self.vtable.initComponent(self.ptr, name);
    }

    /// Helper: Mark component as ready
    pub fn readyComponent(self: HalBackend, comp_id: c_int) !void {
        return self.vtable.readyComponent(self.ptr, comp_id);
    }

    /// Helper: Exit a HAL component
    pub fn exitComponent(self: HalBackend, comp_id: c_int) void {
        self.vtable.exitComponent(self.ptr, comp_id);
    }

    /// Helper: List all pins
    pub fn listPins(self: HalBackend, allocator: std.mem.Allocator) ![]PinInfo {
        return self.vtable.listPins(self.ptr, allocator);
    }

    /// Helper: List all signals
    pub fn listSignals(self: HalBackend, allocator: std.mem.Allocator) ![]SignalInfo {
        return self.vtable.listSignals(self.ptr, allocator);
    }

    /// Helper: List all parameters
    pub fn listParams(self: HalBackend, allocator: std.mem.Allocator) ![]ParamInfo {
        return self.vtable.listParams(self.ptr, allocator);
    }

    /// Helper: List all components
    pub fn listComponents(self: HalBackend, allocator: std.mem.Allocator) ![][]const u8 {
        return self.vtable.listComponents(self.ptr, allocator);
    }

    /// Helper: Get pin value
    pub fn getPinValue(self: HalBackend, name: []const u8) !HalValue {
        return self.vtable.getPinValue(self.ptr, name);
    }

    /// Helper: Set pin value
    pub fn setPinValue(self: HalBackend, name: []const u8, value: HalValue) !void {
        return self.vtable.setPinValue(self.ptr, name, value);
    }

    /// Helper: Get parameter value
    pub fn getParamValue(self: HalBackend, name: []const u8) !HalValue {
        return self.vtable.getParamValue(self.ptr, name);
    }

    /// Helper: Set parameter value
    pub fn setParamValue(self: HalBackend, name: []const u8, value: HalValue) !void {
        return self.vtable.setParamValue(self.ptr, name, value);
    }

    /// Helper: Create a new signal
    pub fn createSignal(self: HalBackend, name: []const u8, pin_type: PinType) !void {
        return self.vtable.createSignal(self.ptr, name, pin_type);
    }

    /// Helper: Delete a signal
    pub fn deleteSignal(self: HalBackend, name: []const u8) !void {
        return self.vtable.deleteSignal(self.ptr, name);
    }

    /// Helper: Link a pin to a signal
    pub fn linkPin(self: HalBackend, pin_name: []const u8, sig_name: []const u8) !void {
        return self.vtable.linkPin(self.ptr, pin_name, sig_name);
    }

    /// Helper: Unlink a pin from its signal
    pub fn unlinkPin(self: HalBackend, pin_name: []const u8) !void {
        return self.vtable.unlinkPin(self.ptr, pin_name);
    }
};
