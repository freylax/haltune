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

/// Create a new HAL float pin
///
/// This function creates a new float pin in the HAL with the specified name and direction.
///
/// Parameters:
///   - comp_id: Component ID from halInit()
///   - name: Null-terminated pin name (must be unique within component)
///   - dir: Pin direction (HAL_IN, HAL_OUT, HAL_IO)
///
/// Returns:
///   - Pointer to pin data (use for reading/writing)
///   - error.InitFailed if pin creation fails
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
/// const pin = try pinFloatNew(comp_id, "my-float-pin", c.HAL_OUT);
/// pin.* = 3.14159;  // Write value
/// const value = pin.*;  // Read value
/// ```
pub fn pinFloatNew(comp_id: c_int, name: [:0]const u8, dir: hal_pin_dir_t) ![*c]volatile f64 {
    // Allocate memory from HAL's shared memory region
    // This is required for pin data pointers in hal_pin_*_new functions
    const mem = c.hal_malloc(@sizeOf([*c]volatile f64)) orelse return HalError.InitFailed;
    const pin_ptr_ptr: [*c][*c]volatile f64 = @ptrCast(@alignCast(mem));

    const rc = c.hal_pin_float_new(name, @intFromEnum(dir), pin_ptr_ptr, comp_id);
    if (rc != 0) return HalError.InitFailed;

    return pin_ptr_ptr.*;
}

/// Create a new HAL bit pin
///
/// This function creates a new bit pin in the HAL with the specified name and direction.
///
/// Parameters:
///   - comp_id: Component ID from halInit()
///   - name: Null-terminated pin name (must be unique within component)
///   - dir: Pin direction (HAL_IN, HAL_OUT, HAL_IO)
///
/// Returns:
///   - Pointer to pin data (use for reading/writing)
///   - error.InitFailed if pin creation fails
pub fn pinBitNew(comp_id: c_int, name: [:0]const u8, dir: hal_pin_dir_t) ![*c]volatile u8 {
    const mem = c.hal_malloc(@sizeOf([*c]volatile u8)) orelse return HalError.InitFailed;
    const pin_ptr_ptr: [*c][*c]volatile u8 = @ptrCast(@alignCast(mem));

    const rc = c.hal_pin_bit_new(name, @intFromEnum(dir), pin_ptr_ptr, comp_id);
    if (rc != 0) return HalError.InitFailed;

    return pin_ptr_ptr.*;
}

/// Create a new HAL s32 pin
///
/// This function creates a new signed 32-bit integer pin in the HAL.
pub fn pinS32New(comp_id: c_int, name: [:0]const u8, dir: hal_pin_dir_t) ![*c]volatile i32 {
    const mem = c.hal_malloc(@sizeOf([*c]volatile i32)) orelse return HalError.InitFailed;
    const pin_ptr_ptr: [*c][*c]volatile i32 = @ptrCast(@alignCast(mem));

    const rc = c.hal_pin_s32_new(name, @intFromEnum(dir), pin_ptr_ptr, comp_id);
    if (rc != 0) return HalError.InitFailed;

    return pin_ptr_ptr.*;
}

/// Create a new HAL u32 pin
///
/// This function creates a new unsigned 32-bit integer pin in the HAL.
pub fn pinU32New(comp_id: c_int, name: [:0]const u8, dir: hal_pin_dir_t) ![*c]volatile u32 {
    const mem = c.hal_malloc(@sizeOf([*c]volatile u32)) orelse return HalError.InitFailed;
    const pin_ptr_ptr: [*c][*c]volatile u32 = @ptrCast(@alignCast(mem));

    const rc = c.hal_pin_u32_new(name, @intFromEnum(dir), pin_ptr_ptr, comp_id);
    if (rc != 0) return HalError.InitFailed;

    return pin_ptr_ptr.*;
}

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
    if (ptr) |p| {
        return @as(*hal_pin_t, @ptrCast(p));
    }
    return null;
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
    if (ptr) |p| {
        return @as(*hal_sig_t, @ptrCast(p));
    }
    return null;
}

/// Set the value of a HAL bit pin
///
/// Parameters:
///   - pin: Pointer to pin data (from pinBitNew or halprFindPinByName)
///   - value: New bit value (true = 1, false = 0)
///
/// Returns:
///   - void on success
///   - error.NotFound if pin pointer is null
///
/// Thread safety:
///   - Acquires HAL mutex before writing
///   - Safe to call from multiple threads
pub fn pinBitSet(pin: ?[*c]volatile u8, value: bool) !void {
    const pin_ptr = pin orelse return HalError.NotFound;
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    pin_ptr.* = @intFromBool(value);
    c.hal_mutex_unlock(c.hal_mutex.ptr);
}

/// Set the value of a HAL float pin
///
/// Parameters:
///   - pin: Pointer to pin data (from pinFloatNew or halprFindPinByName)
///   - value: New float value
///
/// Returns:
///   - void on success
///   - error.NotFound if pin pointer is null
///
/// Thread safety:
///   - Acquires HAL mutex before writing
///   - Safe to call from multiple threads
pub fn pinFloatSet(pin: ?[*c]volatile f64, value: f64) !void {
    const pin_ptr = pin orelse return HalError.NotFound;
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    pin_ptr.* = value;
    c.hal_mutex_unlock(c.hal_mutex.ptr);
}

/// Set the value of a HAL s32 pin
///
/// Parameters:
///   - pin: Pointer to pin data (from pinS32New or halprFindPinByName)
///   - value: New signed 32-bit integer value
///
/// Returns:
///   - void on success
///   - error.NotFound if pin pointer is null
///
/// Thread safety:
///   - Acquires HAL mutex before writing
///   - Safe to call from multiple threads
pub fn pinS32Set(pin: ?[*c]volatile i32, value: i32) !void {
    const pin_ptr = pin orelse return HalError.NotFound;
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    pin_ptr.* = value;
    c.hal_mutex_unlock(c.hal_mutex.ptr);
}

/// Set the value of a HAL u32 pin
///
/// Parameters:
///   - pin: Pointer to pin data (from pinU32New or halprFindPinByName)
///   - value: New unsigned 32-bit integer value
///
/// Returns:
///   - void on success
///   - error.NotFound if pin pointer is null
///
/// Thread safety:
///   - Acquires HAL mutex before writing
///   - Safe to call from multiple threads
pub fn pinU32Set(pin: ?[*c]volatile u32, value: u32) !void {
    const pin_ptr = pin orelse return HalError.NotFound;
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    pin_ptr.* = value;
    c.hal_mutex_unlock(c.hal_mutex.ptr);
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
    if (ptr) |p| {
        return @as(*hal_param_t, @ptrCast(p));
    }
    return null;
}

/// Read from a HAL pin
///
/// This function reads the current value from a HAL pin.
/// For pins linked to signals, this returns the signal's value.
///
/// Parameters:
///   - pin: Pointer to hal_pin_t (from halprFindPinByName)
///
/// Returns:
///   - HalValue union containing the pin's value
///   - error.NotFound if pin pointer is null
///   - error.TypeMismatch if pin type is invalid
///
/// Thread safety:
///   - Does not acquire mutex (reads are lock-free)
///   - Value may be updated concurrently by HAL real-time thread
pub fn getPinValue(pin: ?*const hal_pin_t) !@import("../state/cache.zig").HalValue {
    const pin_ptr = pin orelse return HalError.NotFound;
    const HalValue = @import("../state/cache.zig").HalValue;

    // Pin values are stored in signal_data union
    // If pin is linked to signal, signal_data points to signal value
    // If pin is unlinked, signal_data contains pin's direct value
    switch (pin_ptr.*.signal) {
        null => {
            // Unlinked pin - read from pin's dummy value
            switch (pin_ptr.*.type) {
                c.HAL_BIT => return HalValue{ .bit = pin_ptr.*.dummysig.bit != 0 },
                c.HAL_FLOAT => return HalValue{ .float = pin_ptr.*.dummysig.float },
                c.HAL_S32 => return HalValue{ .s32 = pin_ptr.*.dummysig.s32 },
                c.HAL_U32 => return HalValue{ .u32 = pin_ptr.*.dummysig.u32 },
                else => return HalError.TypeMismatch,
            }
        },
        else => {
            // Linked pin - read from signal
            return getSignalValue(pin_ptr.*.signal.?);
        }
    }
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
pub fn getSignalValue(sig: *const hal_sig_t) !@import("../state/cache.zig").HalValue {
    const HalValue = @import("../state/cache.zig").HalValue;

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

/// Set the value of a HAL bit parameter
///
/// Parameters:
///   - param: Pointer to hal_param_t (from halprFindParamByName)
///   - value: New bit value (true = 1, false = 0)
///
/// Returns:
///   - void on success
///   - error.NotFound if param pointer is null
///   - error.TypeMismatch if param is not bit type
///
/// Thread safety:
///   - Acquires HAL mutex before writing
///   - Safe to call from multiple threads
pub fn setParamBit(param: ?*hal_param_t, value: bool) !void {
    const param_ptr = param orelse return HalError.NotFound;
    if (param_ptr.*.type != c.HAL_BIT) return HalError.TypeMismatch;
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    param_ptr.*.data.bit = @intFromBool(value);
    c.hal_mutex_unlock(c.hal_mutex.ptr);
}

/// Set the value of a HAL float parameter
///
/// Parameters:
///   - param: Pointer to hal_param_t (from halprFindParamByName)
///   - value: New float value
///
/// Returns:
///   - void on success
///   - error.NotFound if param pointer is null
///   - error.TypeMismatch if param is not float type
///
/// Thread safety:
///   - Acquires HAL mutex before writing
///   - Safe to call from multiple threads
pub fn setParamFloat(param: ?*hal_param_t, value: f64) !void {
    const param_ptr = param orelse return HalError.NotFound;
    if (param_ptr.*.type != c.HAL_FLOAT) return HalError.TypeMismatch;
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    param_ptr.*.data.float = value;
    c.hal_mutex_unlock(c.hal_mutex.ptr);
}

/// Set the value of a HAL s32 parameter
///
/// Parameters:
///   - param: Pointer to hal_param_t (from halprFindParamByName)
///   - value: New signed 32-bit integer value
///
/// Returns:
///   - void on success
///   - error.NotFound if param pointer is null
///   - error.TypeMismatch if param is not s32 type
///
/// Thread safety:
///   - Acquires HAL mutex before writing
///   - Safe to call from multiple threads
pub fn setParamS32(param: ?*hal_param_t, value: i32) !void {
    const param_ptr = param orelse return HalError.NotFound;
    if (param_ptr.*.type != c.HAL_S32) return HalError.TypeMismatch;
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    param_ptr.*.data.s32 = value;
    c.hal_mutex_unlock(c.hal_mutex.ptr);
}

/// Set the value of a HAL u32 parameter
///
/// Parameters:
///   - param: Pointer to hal_param_t (from halprFindParamByName)
///   - value: New unsigned 32-bit integer value
///
/// Returns:
///   - void on success
///   - error.NotFound if param pointer is null
///   - error.TypeMismatch if param is not u32 type
///
/// Thread safety:
///   - Acquires HAL mutex before writing
///   - Safe to call from multiple threads
pub fn setParamU32(param: ?*hal_param_t, value: u32) !void {
    const param_ptr = param orelse return HalError.NotFound;
    if (param_ptr.*.type != c.HAL_U32) return HalError.TypeMismatch;
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    param_ptr.*.data.u32 = value;
    c.hal_mutex_unlock(c.hal_mutex.ptr);
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
pub fn getParamValue(param: *const hal_param_t) !@import("../state/cache.zig").HalValue {
    const HalValue = @import("../state/cache.zig").HalValue;

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

    // Verify pin creation functions return error unions
    _ = pinFloatNew;
    _ = pinBitNew;
    _ = pinS32New;
    _ = pinU32New;

    // Verify pin write functions return error unions
    _ = pinBitSet;
    _ = pinFloatSet;
    _ = pinS32Set;
    _ = pinU32Set;

    // Verify discovery functions
    _ = halprFindPinByName;
    _ = halprFindSigByName;
    _ = halprFindParamByName;

    // Verify pin, signal and param value readers
    _ = getPinValue;
    _ = getSignalValue;
    _ = getParamValue;

    // Verify param write functions return error unions
    _ = setParamBit;
    _ = setParamFloat;
    _ = setParamS32;
    _ = setParamU32;
}
