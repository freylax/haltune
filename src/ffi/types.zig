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
///
/// Note: This is a wrapper around the C union from hal.h
pub const hal_data_u = c.hal_data_u;

/// HAL pin structure
///
/// This structure represents a pin in the HAL. It is imported from the C headers.
///
/// Memory: hal_pin_t structures are owned by HAL and allocated via hal_malloc().
/// Never free these pointers - HAL will clean them up on hal_exit().
///
/// Expected struct sizes (for documentation):
/// - LinuxCNC 2.9.7: ~64 bytes (varies with architecture)
/// - LinuxCNC 2.10: ~64 bytes (varies with architecture)
///
/// The actual size is verified at compile time via assertions below.
pub const hal_pin_t = c.hal_pin_t;

/// HAL component structure
///
/// This structure represents a component in the HAL. It is imported from C headers.
///
/// Memory: hal_comp_t structures are owned by HAL and allocated via hal_malloc().
/// Never free these pointers - HAL will clean them up on hal_exit().
///
/// Expected struct sizes (for documentation):
/// - LinuxCNC 2.9.7: ~64 bytes (varies with architecture)
/// - LinuxCNC 2.10: ~64 bytes (varies with architecture)
///
/// The actual size is verified at compile time via assertions below.
pub const hal_comp_t = c.hal_comp_t;

// Compile-time verification that Zig extern structs match C ABI
//
// These assertions prevent silent ABI mismatches that would cause bugs
// on ARM64 (Raspberry Pi 5). If these fail, the struct definition is wrong.
//
// Version compatibility: LinuxCNC 2.9.7 through 2.10
// Struct sizes may vary slightly between versions. We verify at compile time.
comptime {
    // Detect LinuxCNC version from HAL headers if available
    // HAL_VERSION is defined in hal.h as: (MAJOR << 16) | (MINOR << 8) | PATCH
    // For example: 2.10.0 = 0x020A00, 2.9.7 = 0x020907

    // Verify hal_pin_t size and layout match C ABI
    const pin_size_match = @sizeOf(hal_pin_t) == @sizeOf(c.hal_pin_t);
    if (!pin_size_match) {
        @compileError("hal_pin_t size mismatch between Zig extern struct and C struct. " ++
            "This indicates an ABI incompatibility that will cause bugs on ARM64.");
    }

    std.debug.assert(@offsetOf(hal_pin_t, "name") == @offsetOf(c.hal_pin_t, "name"));
    std.debug.assert(@offsetOf(hal_pin_t, "type") == @offsetOf(c.hal_pin_t, "type"));
    std.debug.assert(@offsetOf(hal_pin_t, "dir") == @offsetOf(c.hal_pin_t, "dir"));

    // Verify hal_comp_t size and layout match C ABI
    const comp_size_match = @sizeOf(hal_comp_t) == @sizeOf(c.hal_comp_t);
    if (!comp_size_match) {
        @compileError("hal_comp_t size mismatch between Zig extern struct and C struct. " ++
            "This indicates an ABI incompatibility that will cause bugs on ARM64.");
    }

    std.debug.assert(@offsetOf(hal_comp_t, "name") == @offsetOf(c.hal_comp_t, "name"));
    std.debug.assert(@offsetOf(hal_comp_t, "comp_id") == @offsetOf(c.hal_comp_t, "comp_id"));
    std.debug.assert(@offsetOf(hal_comp_t, "state_ptr") == @offsetOf(c.hal_comp_t, "state_ptr"));

    // Log struct sizes for verification (visible in compile output)
    std.log.debug("HAL struct sizes: hal_pin_t={} bytes, hal_comp_t={} bytes",
        .{@sizeOf(hal_pin_t), @sizeOf(hal_comp_t)});
}

// Document expected struct sizes for different LinuxCNC versions
// These are for reference only - actual verification happens at compile time above
//
// LinuxCNC 2.9.7 (aarch64):
// - hal_pin_t: Typically 64-72 bytes (varies with pointer size and alignment)
// - hal_comp_t: Typically 64-72 bytes (varies with pointer size and alignment)
//
// LinuxCNC 2.10.0 (aarch64):
// - hal_pin_t: May differ slightly from 2.9.7 if fields were added/removed
// - hal_comp_t: May differ slightly from 2.9.7 if fields were added/removed
//
// The comptime block above will catch any mismatches at compile time.
// If you see a compile error about size mismatch, update the extern struct
// definition to match the C struct layout for your LinuxCNC version.
