// HAL extern struct definitions with compile-time verification
//
// This module defines extern structs for HAL types that cross the FFI boundary.
// All structs use 'extern' to guarantee C ABI compatibility on ARM64.
// Compile-time assertions verify struct sizes and field offsets match C types.
//
// IMPORTANT: These are ONLY for types that cross the FFI boundary.
// Pure Zig types should be defined elsewhere.

const std = @import("std");
const c = @import("c.zig").c;

/// HAL pin type enumeration
///
/// Pins in HAL can be of different data types. This enum matches the
/// hal_type_t enum from hal.h.
pub const hal_type_t = enum(c_int) {
    /// Bit (boolean) pin type
    HAL_BIT = 0,
    /// Floating point pin type
    HAL_FLOAT = 1,
    /// Signed 32-bit integer pin type
    HAL_S32 = 2,
    /// Unsigned 32-bit integer pin type
    HAL_U32 = 3,
};

/// HAL pin direction enumeration
///
/// Pins can be read-only (IN), write-only (OUT), or bidirectional (IO).
/// This enum matches the hal_pin_dir_t enum from hal.h.
pub const hal_pin_dir_t = enum(c_int) {
    /// Read-only pin (input to HAL component)
    HAL_IN = 0,
    /// Write-only pin (output from HAL component)
    HAL_OUT = 1,
    /// Bidirectional pin (can read and write)
    HAL_IO = 2,
};

/// HAL data union for pin values
///
/// Pins in HAL store their data as pointers to the actual value.
/// This union provides type-safe access to the different pin data types.
///
/// Memory: The pointers in this union point to memory owned by HAL.
/// Do not free these pointers - HAL manages the memory.
pub extern union hal_data_u {
    /// Bit (boolean) value pointer
    bit: *c_int,
    /// Floating point value pointer
    float: *f64,
    /// Signed 32-bit integer value pointer
    s32: *i32,
    /// Unsigned 32-bit integer value pointer
    u32: *u32,
};

/// HAL pin structure
///
/// This structure represents a pin in the HAL. It is defined here as an
/// extern struct to guarantee C ABI compatibility on ARM64.
///
/// Memory: hal_pin_t structures are owned by HAL and allocated via hal_malloc().
/// Never free these pointers - HAL will clean them up on hal_exit().
///
/// Expected struct sizes (for documentation):
/// - LinuxCNC 2.9.7: ~64 bytes (varies with architecture)
/// - LinuxCNC 2.10: ~64 bytes (varies with architecture)
///
/// The actual size is verified at compile time via assertions below.
pub extern struct hal_pin_t {
    /// Pin name (null-terminated string, owned by HAL)
    name: [*:0]const u8,

    /// Pin type (bit, float, s32, u32)
    type: hal_type_t,

    /// Pin direction (in, out, io)
    dir: hal_pin_dir_t,

    /// Pin data value (union of pointers to actual data)
    data: hal_data_u,

    /// Next pin in linked list (null if last)
    next: ?*hal_pin_t,

    /// Component ID that owns this pin
    comp_id: c_int,

    /// Handle for other users (e.g., Python bindings)
    handle: *anyopaque,
};

/// HAL component structure
///
/// This structure represents a component in the HAL. It is defined here as an
/// extern struct to guarantee C ABI compatibility on ARM64.
///
/// Memory: hal_comp_t structures are owned by HAL and allocated via hal_malloc().
/// Never free these pointers - HAL will clean them up on hal_exit().
///
/// Expected struct sizes (for documentation):
/// - LinuxCNC 2.9.7: ~64 bytes (varies with architecture)
/// - LinuxCNC 2.10: ~64 bytes (varies with architecture)
///
/// The actual size is verified at compile time via assertions below.
pub extern struct hal_comp_t {
    /// Component name (null-terminated string, owned by HAL)
    name: [*:0]const u8,

    /// Component ID (integer handle)
    comp_id: c_int,

    /// Pointer to component state
    state_ptr: *c_int,

    /// Next component in linked list (null if last)
    next: ?*hal_comp_t,

    /// Type of component (RT or non-RT)
    type: c_int,

    /// Last update time (for RT components)
    last_update: i64,

    /// User data pointer (for component-specific data)
    user_data1: *anyopaque,
    user_data2: *anyopaque,
};

// Compile-time verification that Zig extern structs match C ABI
//
// These assertions prevent silent ABI mismatches that would cause bugs
// on ARM64 (Raspberry Pi 5). If these fail, the struct definition is wrong.
comptime {
    // Verify hal_pin_t size and layout
    std.debug.assert(@sizeOf(hal_pin_t) == @sizeOf(c.hal_pin_t));
    std.debug.assert(@offsetOf(hal_pin_t, "name") == @offsetOf(c.hal_pin_t, "name"));
    std.debug.assert(@offsetOf(hal_pin_t, "type") == @offsetOf(c.hal_pin_t, "type"));
    std.debug.assert(@offsetOf(hal_pin_t, "dir") == @offsetOf(c.hal_pin_t, "dir"));

    // Verify hal_comp_t size and layout
    std.debug.assert(@sizeOf(hal_comp_t) == @sizeOf(c.hal_comp_t));
    std.debug.assert(@offsetOf(hal_comp_t, "name") == @offsetOf(c.hal_comp_t, "name"));
    std.debug.assert(@offsetOf(hal_comp_t, "comp_id") == @offsetOf(c.hal_comp_t, "comp_id"));
    std.debug.assert(@offsetOf(hal_comp_t, "state_ptr") == @offsetOf(c.hal_comp_t, "state_ptr"));
}
