// HAL Pin and Param types with cached data pointers
//
// This module provides Pin and Param types that cache HAL data pointers
// for direct memory access without name-based lookups.
//
// Design principles:
// - Pin objects cache data pointers from hal_pin_*_new()
// - get() and set() access memory directly without name lookups
// - Pin objects store their original signal for restore on deactivation

const std = @import("std");

// Import C functions directly - this file needs the include path
pub const c = @cImport({
    @cDefine("ULAPI", "");
    @cInclude("hal.h");
});

// Import errors from errors module (relative import)
pub const HalError = @import("errors.zig").HalError;

/// HAL pin type enumeration
pub const PinType = enum(u2) {
    /// Bit (boolean) pin type
    bit = 0,
    /// Floating point pin type
    float = 1,
    /// Signed 32-bit integer pin type
    s32 = 2,
    /// Unsigned 32-bit integer pin type
    u32 = 3,
};

/// HAL pin direction enumeration
pub const PinDir = enum(c_int) {
    /// Read-only pin (input to HAL component)
    in = c.HAL_IN,
    /// Write-only pin (output from HAL component)
    out = c.HAL_OUT,
    /// Bidirectional pin (can read and write)
    io = c.HAL_IO,
};

/// Cached pin data pointer for direct memory access
///
/// This union stores the actual pointer to the pin's data in HAL shared memory.
/// Access is volatile because HAL's realtime thread may modify the value.
pub const PinDataPtr = union(PinType) {
    /// Bit pin data pointer
    bit: *volatile u8,
    /// Float pin data pointer
    float: *volatile f64,
    /// Signed 32-bit integer pin data pointer
    s32: *volatile i32,
    /// Unsigned 32-bit integer pin data pointer
    u32: *volatile u32,
};

/// Null-terminated name result with ownership flag
const NullTermName = struct { ptr: [*:0]const u8, owned: bool };

/// HAL Pin with cached data pointer
///
/// Pin objects cache the data pointer returned by hal_pin_*_new().
/// This allows direct memory access without name lookups on each read/write.
pub const Pin = struct {
    /// Pin name (owned by Pin, freed with allocator)
    name: []const u8,
    /// Pin type
    pin_type: PinType,
    /// Pin direction
    dir: PinDir,
    /// Cached data pointer for direct access
    data_ptr: PinDataPtr,
    /// Allocator used for name
    allocator: std.mem.Allocator,

    /// Get the current value of the pin
    ///
    /// Reads directly from the cached data pointer.
    /// No name lookup required - this is a direct memory access.
    ///
    /// Returns:
    ///   - HalValue union containing the pin's value
    pub fn get(self: *const Pin) HalValue {
        return switch (self.pin_type) {
            .bit => HalValue{ .bit = self.data_ptr.bit.* != 0 },
            .float => HalValue{ .float = self.data_ptr.float.* },
            .s32 => HalValue{ .s32 = self.data_ptr.s32.* },
            .u32 => HalValue{ .u32 = self.data_ptr.u32.* },
        };
    }

    /// Convenience method to get bit pin value
    pub fn getBit(self: *const Pin) bool {
        return self.data_ptr.bit.* != 0;
    }

    /// Convenience method to get float pin value
    pub fn getFloat(self: *const Pin) f64 {
        return self.data_ptr.float.*;
    }

    /// Convenience method to get s32 pin value
    pub fn getS32(self: *const Pin) i32 {
        return self.data_ptr.s32.*;
    }

    /// Convenience method to get u32 pin value
    pub fn getU32(self: *const Pin) u32 {
        return self.data_ptr.u32.*;
    }

    /// Set the value of the pin
    ///
    /// Writes directly to the cached data pointer.
    /// No name lookup required - this is a direct memory access.
    ///
    /// Parameters:
    ///   - value: New value (HalValue union)
    ///
    /// Returns:
    ///   - void on success
    ///   - error.TypeMismatch if value type doesn't match pin type
    pub fn set(self: *Pin, value: HalValue) !void {
        switch (self.pin_type) {
            .bit => {
                if (value != .bit) return error.TypeMismatch;
                self.data_ptr.bit.* = @intFromBool(value.bit);
            },
            .float => {
                if (value != .float) return error.TypeMismatch;
                self.data_ptr.float.* = value.float;
            },
            .s32 => {
                if (value != .s32) return error.TypeMismatch;
                self.data_ptr.s32.* = value.s32;
            },
            .u32 => {
                if (value != .u32) return error.TypeMismatch;
                self.data_ptr.u32.* = value.u32;
            },
        }
    }

    /// Convenience method to set bit pin
    pub fn setBit(self: *Pin, value: bool) !void {
        if (self.pin_type != .bit) return error.TypeMismatch;
        self.data_ptr.bit.* = @intFromBool(value);
    }

    /// Convenience method to set float pin
    pub fn setFloat(self: *Pin, value: f64) !void {
        if (self.pin_type != .float) return error.TypeMismatch;
        self.data_ptr.float.* = value;
    }

    /// Convenience method to set s32 pin
    pub fn setS32(self: *Pin, value: i32) !void {
        if (self.pin_type != .s32) return error.TypeMismatch;
        self.data_ptr.s32.* = value;
    }

    /// Convenience method to set u32 pin
    pub fn setU32(self: *Pin, value: u32) !void {
        if (self.pin_type != .u32) return error.TypeMismatch;
        self.data_ptr.u32.* = value;
    }

    /// Link this pin to a signal
    ///
    /// Creates a connection between this pin and a HAL signal.
    /// The pin and signal must have the same type.
    ///
    /// Parameters:
    ///   - signal_name: Name of the signal to link to
    ///
    /// Returns:
    ///   - void on success
    ///   - error.LinkFailed if link fails
    pub fn link(self: *Pin, signal_name: []const u8) !void {
        // Need null-terminated string for C API
        const signal_z = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{signal_name});
        defer self.allocator.free(signal_z);

        const pin_name = try self.nullTerminatedName();
        defer self.freeNullTerminatedName(pin_name);

        const rc = c.hal_link(pin_name.ptr, signal_z.ptr);
        if (rc != 0) return HalError.LinkFailed;
    }

    /// Unlink this pin from its signal
    ///
    /// Removes the connection between this pin and its signal.
    /// The pin retains its last value as a dummy value.
    ///
    /// Returns:
    ///   - void on success
    ///   - error.UnlinkFailed if unlink fails
    pub fn unlink(self: *Pin) !void {
        const pin_name = try self.nullTerminatedName();
        defer self.freeNullTerminatedName(pin_name);

        const rc = c.hal_unlink(pin_name.ptr);
        if (rc != 0) return HalError.UnlinkFailed;
    }

    /// Get null-terminated pin name for C API calls
    /// NOTE: Caller is responsible for freeing the returned string if it was newly allocated.
    /// This function returns either a view into self.name or a newly allocated string.
    fn nullTerminatedName(self: *Pin) !NullTermName {
        // If name already has null terminator, return it
        if (std.mem.indexOfScalar(u8, self.name, 0)) |idx| {
            if (idx == self.name.len - 1) {
                return .{ .ptr = @ptrCast(self.name.ptr), .owned = false };
            }
        }
        // Otherwise allocate a new null-terminated string
        const result = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{self.name});
        return .{ .ptr = @ptrCast(result.ptr), .owned = true };
    }

    /// Helper to call cleanup after nullTerminatedName
    fn freeNullTerminatedName(self: *Pin, result: NullTermName) void {
        if (result.owned) {
            // Calculate the length and free the allocated memory
            const len = std.mem.len(result.ptr);
            self.allocator.free(result.ptr[0..len]);
        }
    }

    /// Clean up the pin
    pub fn deinit(self: *Pin) void {
        self.allocator.free(self.name);
        self.* = undefined;
    }
};

/// HAL value union matching the four HAL data types
pub const HalValue = union(enum) {
    /// Boolean value (HAL_BIT pins/signals)
    bit: bool,
    /// Floating-point value (HAL_FLOAT pins/signals)
    float: f64,
    /// Signed 32-bit integer (HAL_S32 pins/signals)
    s32: i32,
    /// Unsigned 32-bit integer (HAL_U32 pins/signals)
    u32: u32,
};

// Compile-time tests
comptime {
    _ = Pin.get;
    _ = Pin.set;
    _ = Pin.link;
    _ = Pin.unlink;
}
