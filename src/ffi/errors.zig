// HAL error type definitions
//
// This module defines Zig error types that map to LinuxCNC HAL error codes.
// HAL functions typically return negative integers on error, with specific
// values indicating different failure modes.

const std = @import("std");

/// HAL-specific error set mapping to LinuxCNC HAL error codes
///
/// These errors correspond to the negative return codes from HAL C functions.
/// The error set provides type-safe error handling enforced by the compiler.
pub const HalError = error{
    /// hal_init() failed - returned null or negative
    /// This typically indicates HAL is not running or component name is invalid
    InitFailed,

    /// HAL is not available - LinuxCNC is not running
    /// HAL shared memory files in /dev/shm don't exist
    HalNotAvailable,

    /// Component not found in HAL
    /// The specified component ID or name does not exist
    ComponentNotFound,

    /// Pin not found in HAL
    /// The specified pin name does not exist
    PinNotFound,

    /// Invalid name for HAL object
    /// Name contains invalid characters, is too long, or conflicts with existing object
    InvalidName,

    /// Object already linked to a signal
    /// Attempted to link a pin that's already linked, or link signal to already-linked pin
    AlreadyLinked,

    /// hal_link() failed - pin or signal not found, or type mismatch
    /// The pin or signal does not exist, or their types are incompatible
    LinkFailed,

    /// hal_unlink() failed - pin not linked or not found
    /// The pin does not exist or is not linked to a signal
    UnlinkFailed,

    /// Type mismatch in HAL operation
    /// Attempted operation between incompatible types (e.g., linking float pin to bit signal)
    TypeMismatch,

    /// HAL mutex is locked
    /// Could not acquire HAL mutex for write operation
    MutexLocked,

    /// HAL component not ready
    /// Component must call hal_ready() before performing certain operations
    NotReady,

    /// Signal not found in HAL
    /// The specified signal name does not exist
    SignalNotFound,

    /// Parameter not found in HAL
    /// The specified parameter name does not exist
    ParamNotFound,

    /// Generic not found error
    /// Used for FFI functions that return null pointers
    NotFound,
};

/// Map HAL C return code to Zig error
///
/// HAL C functions return negative integers on error. This function converts
/// those error codes to Zig error types for type-safe error handling.
///
/// LinuxCNC HAL error codes (from hal.h):
/// - -EINVAL (-22): Invalid argument/name
/// - -ENOMEM (-12): Out of memory
/// - -EBUSY (-16): Resource busy (already linked, etc.)
/// - -ENOENT (-2): No such entity (component/pin/signal not found)
/// - -EPERM (-1): Operation not permitted
///
/// Since HAL error codes are not always consistent, we use best-effort mapping
/// and default to InitFailed for unknown codes.
///
/// Parameters:
///   rc: Return code from HAL C function (negative on error)
///
/// Returns: Corresponding HalError
pub fn mapHalError(rc: std.c.Int) HalError {
    // Map specific negative error codes to Zig errors
    // These are standard Linux errno values used by HAL
    switch (@as(i32, @intCast(rc))) {
        // Invalid argument - bad name, type, etc.
        -22 => return HalError.InvalidName,

        // No such entity - component, pin, signal, or param not found
        -2 => return HalError.ComponentNotFound,

        // Resource busy - already linked or in use
        -16 => return HalError.AlreadyLinked,

        // Operation not permitted - component not ready, wrong state
        -1 => return HalError.NotReady,

        // For other error codes, default to InitFailed
        // This is a conservative choice since we can't be more specific
        else => return HalError.InitFailed,
    }
}

/// Check if HAL is available by verifying shared memory files exist
///
/// HAL creates shared memory files in /dev/shm when LinuxCNC is running.
/// This function checks for the presence of these files to determine if
/// HAL is available before attempting to call hal_init().
///
/// Returns:
///   - void on success (HAL is available)
///   - error.HalNotAvailable if HAL cannot be initialized
///
/// Example:
/// ```
/// // Check HAL is available before initializing
/// try checkHalAvailable();
/// const comp_id = try halInit("mycomponent");
/// ```
pub fn checkHalAvailable() !void {
    // The most reliable way to check if HAL is available is to try
    // initializing a test component. This works with both:
    // - Full LinuxCNC (creates /dev/shm/hal_shm)
    // - halrun (interactive HAL, may use different mechanisms)
    const c = @import("c.zig").c;

    // Try to initialize a temporary test component
    const test_comp_name = "haltune_check\x00";
    const test_comp_id = c.hal_init(test_comp_name);

    // If hal_init returns negative, HAL is not available
    if (test_comp_id < 0) {
        return HalError.HalNotAvailable;
    }

    // Success! Clean up the test component immediately
    _ = c.hal_exit(test_comp_id);
}
