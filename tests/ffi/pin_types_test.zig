// Self-contained Pin type test for pib
const std = @import("std");

const c = @cImport({
    @cDefine("ULAPI", "");
    @cInclude("hal.h");
});

// PinType enum
pub const PinType = enum(u2) {
    bit = 0,
    float = 1,
    s32 = 2,
    u32 = 3,
};

// PinDir enum
pub const PinDir = enum(c_int) {
    in = 16,
    out = 32,
    io = 48,
};

// PinDataPtr union
pub const PinDataPtr = union(PinType) {
    bit: *volatile u8,
    float: *volatile f64,
    s32: *volatile i32,
    u32: *volatile u32,
};

// Pin struct
pub const Pin = struct {
    name: []const u8,
    pin_type: PinType,
    dir: PinDir,
    data_ptr: PinDataPtr,
    allocator: std.mem.Allocator,

    pub fn getBit(self: *const Pin) bool {
        return self.data_ptr.bit.* != 0;
    }

    pub fn setBit(self: *Pin, value: bool) !void {
        if (self.pin_type != .bit) return error.TypeMismatch;
        self.data_ptr.bit.* = @intFromBool(value);
    }

    pub fn getFloat(self: *const Pin) f64 {
        return self.data_ptr.float.*;
    }

    pub fn setFloat(self: *Pin, value: f64) !void {
        if (self.pin_type != .float) return error.TypeMismatch;
        self.data_ptr.float.* = value;
    }

    pub fn getS32(self: *const Pin) i32 {
        return self.data_ptr.s32.*;
    }

    pub fn setS32(self: *Pin, value: i32) !void {
        if (self.pin_type != .s32) return error.TypeMismatch;
        self.data_ptr.s32.* = value;
    }

    pub fn getU32(self: *const Pin) u32 {
        return self.data_ptr.u32.*;
    }

    pub fn setU32(self: *Pin, value: u32) !void {
        if (self.pin_type != .u32) return error.TypeMismatch;
        self.data_ptr.u32.* = value;
    }
};

test "Pin: type definitions compile" {
    try std.testing.expectEqual(@as(u2, 0), @intFromEnum(PinType.bit));
    try std.testing.expectEqual(@as(u2, 1), @intFromEnum(PinType.float));
    try std.testing.expectEqual(@as(u2, 2), @intFromEnum(PinType.s32));
    try std.testing.expectEqual(@as(u2, 3), @intFromEnum(PinType.u32));
}

test "Pin: PinDataPtr union compiles" {
    var bit_ptr: PinDataPtr = undefined;
    bit_ptr = .{ .bit = @ptrFromInt(0x1000) };
    try std.testing.expect(@as(PinType, PinType.bit) == bit_ptr);
}
