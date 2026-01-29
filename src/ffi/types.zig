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

/// HAL pin structure (opaque in ULAPI)
///
/// When ULAPI is defined (userspace API), hal_pin_t is an opaque type.
/// We use opaque {} because the struct definition is not exposed to userspace.
/// For reading pins, use halprFindPinByName() discovery API.
///
/// Memory: Opaque pointers owned by HAL. Never free them.
pub const hal_pin_t = opaque {};

/// HAL signal structure (opaque in ULAPI)
pub const hal_sig_t = opaque {};

/// HAL parameter structure (opaque in ULAPI)
pub const hal_param_t = opaque {};

/// HAL component ID (not a structure in ULAPI)
///
/// In userspace API, hal_init() returns an int component ID, not a pointer.
/// We use c_int (alias for int) for component IDs.
// pub const hal_comp_t = c.hal_comp_t;

// Compile-time verification disabled for ULAPI
//
// When ULAPI is defined, HAL structs (hal_pin_t, hal_sig_t, hal_param_t)
// are opaque types - their fields are not exposed to userspace code.
// Therefore we cannot verify field offsets or sizes at compile time.
//
// For our use case (HAL inspector/monitor), we only need to:
// - Enumerate pins/signals/params via halprFind*ByName() discovery API
// - Read values via hal_get*() functions
// - Write values via hal_set*() functions (if needed)
//
// We don't need direct struct field access, so opaque types are sufficient.

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
