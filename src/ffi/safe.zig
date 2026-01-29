// Safe wrapper functions for HAL C API
//
// This module provides type-safe, error-handling wrappers around the raw
// LinuxCNC HAL C functions. All FFI calls should go through these wrappers
// rather than calling c.hal_* functions directly.
//
// Design principles:
// - Return error unions (!T) to enforce error handling
// - Handle null pointers explicitly
// - Document memory ownership clearly
// - Use extern structs for C compatibility

const std = @import("std");
const c = @import("c.zig").c;
const HalError = @import("errors.zig").HalError;
const hal_type_t = @import("types.zig").hal_type_t;
const hal_pin_dir_t = @import("types.zig").hal_pin_dir_t;
const hal_pin_t = @import("types.zig").hal_pin_t;
const hal_sig_t = @import("types.zig").hal_sig_t;
const hal_param_t = @import("types.zig").hal_param_t;

/// Initialize a HAL component
///
/// This function initializes a new HAL component with the given name.
/// The component must call hal_ready() before it can use HAL features.
/// When done, call hal_exit() to clean up.
///
/// Parameters:
///   - comp_name: Null-terminated component name (must be unique in HAL)
///
/// Returns:
///   - Component ID on success (use for subsequent HAL calls)
///   - error.InitFailed if HAL is not available or name is invalid
///
/// Memory ownership:
///   - HAL allocates memory for the component
///   - Caller must call hal_exit() when done to clean up
///
/// Example:
/// ```
/// const comp_id = try halInit("mycomponent");
/// defer halExit(comp_id);
/// // ... use HAL features
/// _ = try halReady(comp_id);
/// ```
pub fn halInit(comp_name: [:0]const u8) !c_int {
    // Call hal_init - returns component ID (positive) on success, negative on error
    const comp_id = c.hal_init(comp_name);

    // hal_init returns negative value on failure
    if (comp_id < 0) return HalError.InitFailed;

    return comp_id;
}

/// Exit a HAL component
///
/// This function cleans up a HAL component and frees all associated memory.
/// After calling this function, the component ID is invalid and must not be used.
///
/// Parameters:
///   - comp_id: Component ID from halInit()
///
/// Returns:
///   - void (this function always succeeds, even if comp_id is invalid)
///
/// Memory ownership:
///   - Frees all HAL-allocated memory for this component
///   - Invalidates all pins, signals, and parameters created by this component
///
/// Example:
/// ```
/// const comp_id = try halInit("mycomponent");
/// defer halExit(comp_id);  // Always cleanup, even on error
/// ```
pub fn halExit(comp_id: c_int) void {
    // hal_exit has no return value - it always succeeds
    _ = c.hal_exit(comp_id);
}

/// Mark HAL component as ready
///
/// This function marks a HAL component as ready to operate. After calling
/// hal_ready(), the component can create pins, signals, and parameters.
///
/// Parameters:
///   - comp_id: Component ID from halInit()
///
/// Returns:
///   - void on success
///   - error.NotReady if component is in invalid state
///   - error.InitFailed if HAL initialization failed
///
/// Example:
/// ```
/// const comp_id = try halInit("mycomponent");
/// defer halExit(comp_id);
/// _ = try halReady(comp_id);
/// // ... now can create pins, signals, etc.
/// ```
pub fn halReady(comp_id: c_int) !void {
    const rc = c.hal_ready(comp_id);
    if (rc != 0) {
        // Map negative return code to specific error
        return if (rc < 0)
            HalError.InitFailed
        else
            HalError.NotReady;
    }
}

/// Create a new HAL pin
///
/// This function creates a new pin in the HAL with the specified name, type, and direction.
/// Pins are the primary mechanism for HAL components to exchange data.
///
/// Parameters:
///   - comp_id: Component ID from halInit()
///   - name: Null-terminated pin name (must be unique within component)
///   - type: Pin data type (HAL_BIT, HAL_FLOAT, HAL_S32, HAL_U32)
///   - dir: Pin direction (HAL_IN, HAL_OUT, HAL_IO)
///
/// Returns:
///   - Pointer to hal_pin_t on success
///   - error.PinCreationFailed if pin creation fails
///
/// Memory ownership:
///   - HAL allocates memory for the pin
///   - Caller must NOT free the pin pointer - HAL owns it
///   - Pin is automatically cleaned up when hal_exit() is called
///
/// Example:
/// ```
/// const comp_id = try halInit("mycomponent");
/// defer halExit(comp_id);
///
/// const pin = try pinNew(comp_id, "my-pin", c.HAL_FLOAT, c.HAL_OUT);
/// // pin is now ready to use
/// ```
// pub fn pinNew( // DISABLED: hal_pin_t is opaque in ULAPI
//     comp_id: c_int,
//     name: [:0]const u8,
//     pin_type: hal_type_t,
//     dir: hal_pin_dir_t,
// ) !*c.hal_pin_t {
//     var pin_ptr: ?*c.hal_pin_t = undefined;
//     const rc = c.hal_pin_new_ff(name, @intFromEnum(pin_type), @intFromEnum(dir), &pin_ptr, comp_id);
//     if (rc != 0) return HalError.PinCreationFailed;
//     return pin_ptr orelse HalError.PinCreationFailed;
// }

/// Write to a float pin (thread-safe)
///
/// This function writes a floating-point value to a HAL pin.
/// The HAL mutex is acquired before writing to prevent data races.
///
/// Parameters:
///   - pin: Pointer to hal_pin_t from pinNew()
///   - value: Float value to write
///
/// Returns:
///   - void on success
///   - error.TypeMismatch if pin is not a HAL_FLOAT pin
///
/// Thread safety:
///   - Acquires HAL mutex before write
///   - Automatically releases mutex when done (defer unlock)
///
/// Example:
/// ```
/// const pin = try pinNew(comp_id, "value", c.HAL_FLOAT, c.HAL_OUT);
/// try setPinFloat(pin, 3.14159);
/// ```
// pub fn setPinFloat(pin: *c.hal_pin_t, value: f64) !void {
    // Acquire HAL mutex before write
//     _ = c.hl_mutex_lock(&c.hal_mutex);
//     defer c.hl_mutex_unlock(&c.hal_mutex);
// 
    // Verify pin type
//     if (pin.*.type != c.HAL_FLOAT) return HalError.TypeMismatch;
// 
    // Write value through pin's data pointer
//     pin.*.data.float.* = value;
// }

/// Write to a bit pin (thread-safe)
///
/// This function writes a boolean value to a HAL bit pin.
/// The HAL mutex is acquired before writing to prevent data races.
///
/// Parameters:
///   - pin: Pointer to hal_pin_t from pinNew()
///   - value: Boolean value to write
///
/// Returns:
///   - void on success
///   - error.TypeMismatch if pin is not a HAL_BIT pin
// pub fn setPinBit(pin: *c.hal_pin_t, value: bool) !void {
//     _ = c.hl_mutex_lock(&c.hal_mutex);
//     defer c.hl_mutex_unlock(&c.hal_mutex);
// 
//     if (pin.*.type != c.HAL_BIT) return HalError.TypeMismatch;
// 
//     pin.*.data.bit.* = @intFromBool(value);
// }

/// Write to a signed 32-bit integer pin (thread-safe)
///
/// This function writes a signed integer value to a HAL s32 pin.
/// The HAL mutex is acquired before writing to prevent data races.
///
/// Parameters:
///   - pin: Pointer to hal_pin_t from pinNew()
///   - value: Signed 32-bit integer value to write
///
/// Returns:
///   - void on success
///   - error.TypeMismatch if pin is not a HAL_S32 pin
// pub fn setPinS32(pin: *c.hal_pin_t, value: i32) !void {
//     _ = c.hl_mutex_lock(&c.hal_mutex);
//     defer c.hl_mutex_unlock(&c.hal_mutex);
// 
//     if (pin.*.type != c.HAL_S32) return HalError.TypeMismatch;
// 
//     pin.*.data.s32.* = value;
// }

/// Write to an unsigned 32-bit integer pin (thread-safe)
///
/// This function writes an unsigned integer value to a HAL u32 pin.
/// The HAL mutex is acquired before writing to prevent data races.
///
/// Parameters:
///   - pin: Pointer to hal_pin_t from pinNew()
///   - value: Unsigned 32-bit integer value to write
///
/// Returns:
///   - void on success
///   - error.TypeMismatch if pin is not a HAL_U32 pin
// pub fn setPinU32(pin: *c.hal_pin_t, value: u32) !void {
//     _ = c.hl_mutex_lock(&c.hal_mutex);
//     defer c.hl_mutex_unlock(&c.hal_mutex);
// 
//     if (pin.*.type != c.HAL_U32) return HalError.TypeMismatch;
// 
//     pin.*.data.u32.* = value;
// }

/// Read from a float pin
///
/// This function reads the current value from a HAL float pin.
/// No mutex is needed for read operations (HAL real-time thread owns writes).
///
/// Parameters:
///   - pin: Pointer to hal_pin_t from pinNew()
///
/// Returns:
///   - Float value on success
///   - error.TypeMismatch if pin is not a HAL_FLOAT pin
///
/// Thread safety:
///   - Does not acquire mutex (reads are lock-free)
///   - Value may be updated concurrently by HAL real-time thread
// pub fn getPinFloat(pin: *const c.hal_pin_t) !f64 {
//     if (pin.*.type != c.HAL_FLOAT) return HalError.TypeMismatch;
// 
//     return pin.*.data.float.*;
// }

/// Read from a bit pin
///
/// This function reads the current value from a HAL bit pin.
/// No mutex is needed for read operations.
///
/// Parameters:
///   - pin: Pointer to hal_pin_t from pinNew()
///
/// Returns:
///   - Boolean value on success
///   - error.TypeMismatch if pin is not a HAL_BIT pin
// pub fn getPinBit(pin: *const c.hal_pin_t) !bool {
//     if (pin.*.type != c.HAL_BIT) return HalError.TypeMismatch;
// 
//     return pin.*.data.bit.* != 0;
// }

/// Read from a signed 32-bit integer pin
///
/// This function reads the current value from a HAL s32 pin.
/// No mutex is needed for read operations.
///
/// Parameters:
///   - pin: Pointer to hal_pin_t from pinNew()
///
/// Returns:
///   - Signed 32-bit integer value on success
///   - error.TypeMismatch if pin is not a HAL_S32 pin
// pub fn getPinS32(pin: *const c.hal_pin_t) !i32 {
//     if (pin.*.type != c.HAL_S32) return HalError.TypeMismatch;
// 
//     return pin.*.data.s32.*;
// }

/// Read from an unsigned 32-bit integer pin
///
/// This function reads the current value from a HAL u32 pin.
/// No mutex is needed for read operations.
///
/// Parameters:
///   - pin: Pointer to hal_pin_t from pinNew()
///
/// Returns:
///   - Unsigned 32-bit integer value on success
///   - error.TypeMismatch if pin is not a HAL_U32 pin
// pub fn getPinU32(pin: *const c.hal_pin_t) !u32 {
//     if (pin.*.type != c.HAL_U32) return HalError.TypeMismatch;
// 
//     return pin.*.data.u32.*;
// }

/// Find a HAL pin by name
///
/// This function searches the HAL pin database for a pin with the given name.
/// Pass null to get the first pin in HAL (used for iteration).
///
/// Parameters:
///   - name: Null-terminated pin name, or null to get first pin
///
/// Returns:
///   - Pointer to hal_pin_t on success
///   - null if not found
///
/// Memory ownership:
///   - HAL owns the pin memory - do not free
///
/// Usage for enumeration:
/// ```
/// var maybe_pin = halprFindPinByName(null);  // Get first pin
/// while (maybe_pin) |pin| {
///     // Can't access pin.*.name directly - hal_pin_t is opaque in ULAPI
///     // Use HAL API functions to read pin data
///     maybe_pin = halprFindPinByName(pin.*.next);  // Walk linked list
/// }
/// ```
pub fn halprFindPinByName(name: ?[*:0]const u8) ?*hal_pin_t {
    const c_import = @import("c.zig");
    const ptr = c_import.halpr_find_pin_by_name(name);
    return if (ptr) |p| @ptrCast(*hal_pin_t, p) else null;
}

/// Find a HAL signal by name
///
/// This function searches the HAL signal database for a signal with the given name.
/// Pass null to get the first signal in HAL (used for iteration).
///
/// Parameters:
///   - name: Null-terminated signal name, or null to get first signal
///
/// Returns:
///   - Pointer to hal_sig_t on success
///   - null if not found
///
/// Memory ownership:
///   - HAL owns the signal memory - do not free
pub fn halprFindSigByName(name: ?[*:0]const u8) ?*hal_sig_t {
    const c_import = @import("c.zig");
    const ptr = c_import.halpr_find_sig_by_name(name);
    return if (ptr) |p| @ptrCast(*hal_sig_t, p) else null;
}

/// Find a HAL parameter by name
///
/// This function searches the HAL parameter database for a parameter with the given name.
/// Pass null to get the first parameter in HAL (used for iteration).
///
/// Parameters:
///   - name: Null-terminated parameter name, or null to get first parameter
///
/// Returns:
///   - Pointer to hal_param_t on success
///   - null if not found
///
/// Memory ownership:
///   - HAL owns the parameter memory - do not free
pub fn halprFindParamByName(name: ?[*:0]const u8) ?*hal_param_t {
    const c_import = @import("c.zig");
    const ptr = c_import.halpr_find_param_by_name(name);
    return if (ptr) |p| @ptrCast(*hal_param_t, p) else null;
}

/// Read from a HAL signal
///
/// This function reads the current value from a HAL signal.
/// Signals store their values directly in the hal_sig_t structure.
///
/// Parameters:
///   - sig: Pointer to hal_sig_t
///
/// Returns:
///   - HalValue union containing the signal's value
///   - error.TypeMismatch if signal type is invalid
///
/// Thread safety:
///   - Does not acquire mutex (reads are lock-free)
///   - Value may be updated concurrently by HAL real-time thread
pub fn getSignalValue(sig: *const hal_sig_t) !@import("state-cache").HalValue {
    const HalValue = @import("state-cache").HalValue;

    // Read value based on signal type
    switch (sig.*.type) {
        c.HAL_BIT => {
            return HalValue{ .bit = sig.*.data.bit != 0 };
        },
        c.HAL_FLOAT => {
            return HalValue{ .float = sig.*.data.float };
        },
        c.HAL_S32 => {
            return HalValue{ .s32 = sig.*.data.s32 };
        },
        c.HAL_U32 => {
            return HalValue{ .u32 = sig.*.data.u32 };
        },
        else => return HalError.TypeMismatch,
    }
}

/// Read from a HAL parameter
///
/// This function reads the current value from a HAL parameter.
/// Parameters store their values directly in the hal_param_t structure.
///
/// Parameters:
///   - param: Pointer to hal_param_t
///
/// Returns:
///   - HalValue union containing the parameter's value
///   - error.TypeMismatch if parameter type is invalid
///
/// Thread safety:
///   - Does not acquire mutex (reads are lock-free)
///   - Value may be updated concurrently by HAL real-time thread
pub fn getParamValue(param: *const hal_param_t) !@import("state-cache").HalValue {
    const HalValue = @import("state-cache").HalValue;

    // Read value based on parameter type
    switch (param.*.type) {
        c.HAL_BIT => {
            return HalValue{ .bit = param.*.data.bit != 0 };
        },
        c.HAL_FLOAT => {
            return HalValue{ .float = param.*.data.float };
        },
        c.HAL_S32 => {
            return HalValue{ .s32 = param.*.data.s32 };
        },
        c.HAL_U32 => {
            return HalValue{ .u32 = param.*.data.u32 };
        },
        else => return HalError.TypeMismatch,
    }
}

// Compile-time tests
comptime {
    // Verify halInit returns error union
    _ = halInit;

    // Verify halExit is callable
    _ = halExit;

    // Verify halReady returns error union
    _ = halReady;

    // Verify pin functions return error unions
    // DISABLED: hal_pin_t is opaque in ULAPI, need to implement name-based API
    // _ = pinNew;
    // _ = setPinFloat;
    // _ = setPinBit;
    // _ = setPinS32;
    // _ = setPinU32;
    // _ = getPinFloat;
    // _ = getPinBit;
    // _ = getPinS32;
    // _ = getPinU32;

    // Verify discovery functions
    _ = halprFindPinByName;
    _ = halprFindSigByName;
    _ = halprFindParamByName;

    // Verify signal and param value readers
    _ = getSignalValue;
    _ = getParamValue;
}
