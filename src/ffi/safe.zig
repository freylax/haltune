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
    // Try the requested name first
    var comp_id = c.hal_init(comp_name);

    // If that fails, try incrementing suffixes (haltune1, haltune2, etc.)
    // This handles cases where a previous instance didn't clean up properly
    if (comp_id < 0) {
        var suffix: u32 = 1;
        while (suffix <= 100) : (suffix += 1) {
            const numbered_name = try std.fmt.allocPrint(
                std.heap.page_allocator,
                "{s}{d}\x00",
                .{ comp_name, suffix },
            );
            defer std.heap.page_allocator.free(numbered_name);

            comp_id = c.hal_init(numbered_name.ptr);
            if (comp_id >= 0) {
                // Success! Print a note about the modified name
                std.debug.print("Using component name '{s}' (original '{s}' was in use)\n", .{ numbered_name, comp_name });
                return comp_id;
            }
        }

        // If we get here, all attempts failed
        std.debug.print(
            \\HAL init failed for component '{s}'
            \\
            \\This usually means a component with this name already exists
            \\(perhaps from a previous crash that didn't clean up properly).
            \\
            \\To see existing components, run:
            \\  halcmd list comp
            \\
            \\To remove a stuck component, run:
            \\  halcmd del comp {s}
            \\
        , .{ comp_name, comp_name });
        return HalError.InitFailed;
    }

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

/// Create a new HAL signal
///
/// This function creates a new signal in the HAL with the specified name and type.
///
/// Parameters:
///   - name: Null-terminated signal name (must be unique in HAL)
///   - hal_type: Signal type (HAL_BIT, HAL_FLOAT, HAL_S32, HAL_U32)
///
/// Returns:
///   - void on success
///   - error.InitFailed if signal already exists or type is invalid
///
/// Memory ownership:
///   - HAL allocates memory for the signal
///   - Signal is automatically cleaned up when hal_exit() is called
///
/// Thread safety:
///   - Acquires HAL mutex before creating signal
pub fn halSignalNew(name: [:0]const u8, hal_type: hal_type_t) !void {
    const rc = c.hal_signal_new(name, @intFromEnum(hal_type));
    if (rc != 0) return HalError.InitFailed;
}

/// Delete a HAL signal
///
/// Removes a signal from the HAL. All pins linked to this signal
/// will be unlinked first. The signal must exist.
///
/// Parameters:
///   - name: Null-terminated signal name to delete
///
/// Returns:
///   - void on success
///   - error.NotFound if signal doesn't exist
///
/// Thread safety:
///   - hal_signal_delete acquires HAL mutex internally
pub fn halSignalDelete(name: [:0]const u8) !void {
    if (c.hal_signal_delete(name) < 0) {
        return HalError.NotFound;
    }
}

/// Link a pin to a signal
///
/// This function links an existing pin to an existing signal.
/// The pin and signal must have the same type (bit, float, s32, or u32).
///
/// Parameters:
///   - pin_name: Null-terminated pin name to link
///   - signal_name: Null-terminated signal name to link to
///
/// Returns:
///   - void on success
///   - error.LinkFailed if pin/signal not found or types don't match
///   - error.AlreadyLinked if pin is already linked to a signal
///
/// Thread safety:
///   - hal_link acquires its own mutex internally
///   - Safe to call from multiple threads
pub fn halLink(pin_name: [:0]const u8, signal_name: [:0]const u8) !void {
    const rc = c.hal_link(pin_name, signal_name);
    if (rc != 0) return HalError.LinkFailed;
}

/// Unlink a pin from its signal
///
/// This function removes the connection between a pin and its signal.
/// After unlinking, the pin retains its last value as a dummy value.
///
/// Parameters:
///   - pin_name: Null-terminated pin name to unlink
///
/// Returns:
///   - void on success
///   - error.UnlinkFailed if pin not found or not linked
///
/// Thread safety:
///   - hal_unlink acquires its own mutex internally
///   - Safe to call from multiple threads
pub fn halUnlink(pin_name: [:0]const u8) !void {
    const rc = c.hal_unlink(pin_name);
    if (rc != 0) return HalError.UnlinkFailed;
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
    // hal_mutex_lock may not be available in ULAPI build
    // For now, skip explicit mutex locking in ULAPI context
    pin_ptr.* = @intFromBool(value);
}

/// Set the value of a HAL bit pin by name
///
/// This is the preferred way to write pin values from userspace.
/// It uses hal_get_pin_value_by_name to get the data pointer,
/// then writes directly to it.
///
/// Parameters:
///   - name: Null-terminated pin name
///   - value: New boolean value
///
/// Returns:
///   - void on success
///   - error.NotFound if pin doesn't exist
///   - error.TypeMismatch if pin type doesn't match
pub fn setPinBitByName(name: [*:0]const u8, value: bool) !void {
    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;
    var connected: bool = undefined;

    const rc = c.hal_get_pin_value_by_name(name, &hal_type, &data_ptr, &connected);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;
    if (hal_type != c.HAL_BIT) return HalError.TypeMismatch;

    data.*.b = value;
}

/// Set the value of a HAL float pin by name
pub fn setPinFloatByName(name: [*:0]const u8, value: f64) !void {
    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;
    var connected: bool = undefined;

    const rc = c.hal_get_pin_value_by_name(name, &hal_type, &data_ptr, &connected);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;
    if (hal_type != c.HAL_FLOAT) return HalError.TypeMismatch;

    data.*.f = value;
}

/// Set the value of a HAL s32 pin by name
pub fn setPinS32ByName(name: [*:0]const u8, value: i32) !void {
    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;
    var connected: bool = undefined;

    const rc = c.hal_get_pin_value_by_name(name, &hal_type, &data_ptr, &connected);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;
    if (hal_type != c.HAL_S32) return HalError.TypeMismatch;

    data.*.s = value;
}

/// Set the value of a HAL u32 pin by name
pub fn setPinU32ByName(name: [*:0]const u8, value: u32) !void {
    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;
    var connected: bool = undefined;

    const rc = c.hal_get_pin_value_by_name(name, &hal_type, &data_ptr, &connected);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;
    if (hal_type != c.HAL_U32) return HalError.TypeMismatch;

    data.*.u = value;
}

/// Set the value of a HAL pin by name (union-based)
///
/// This is a convenience function that dispatches to the type-specific
/// setPin*ByName functions based on the HalValue tag.
pub fn setPinValueByName(name: [*:0]const u8, value: @import("../state/cache.zig").HalValue) !void {
    switch (value) {
        .bit => |v| try setPinBitByName(name, v),
        .float => |v| try setPinFloatByName(name, v),
        .s32 => |v| try setPinS32ByName(name, v),
        .u32 => |v| try setPinU32ByName(name, v),
    }
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
///   - In ULAPI, write directly to pin memory (HAL handles locking)
///   - Safe to call from multiple threads
pub fn pinFloatSet(pin: ?[*c]volatile f64, value: f64) !void {
    const pin_ptr = pin orelse return HalError.NotFound;
    pin_ptr.* = value;
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
///   - In ULAPI, write directly to pin memory (HAL handles locking)
///   - Safe to call from multiple threads
pub fn pinS32Set(pin: ?[*c]volatile i32, value: i32) !void {
    const pin_ptr = pin orelse return HalError.NotFound;
    pin_ptr.* = value;
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
///   - In ULAPI, write directly to pin memory (HAL handles locking)
///   - Safe to call from multiple threads
pub fn pinU32Set(pin: ?[*c]volatile u32, value: u32) !void {
    const pin_ptr = pin orelse return HalError.NotFound;
    pin_ptr.* = value;
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

/// Read from a HAL pin by name
///
/// This function reads the current value from a HAL pin by name.
/// Uses HAL API function hal_get_pin_value_by_name which works
/// with opaque types.
///
/// Parameters:
///   - name: Null-terminated pin name
///
/// Returns:
///   - HalValue union containing the pin's value
///   - error.NotFound if pin doesn't exist
///   - error.TypeMismatch if pin type is invalid
///
/// Thread safety:
///   - Does not acquire mutex (reads are lock-free)
///   - Value may be updated concurrently by HAL real-time thread
pub fn getPinValueByName(name: [*:0]const u8) !@import("../state/cache.zig").HalValue {
    const HalValue = @import("../state/cache.zig").HalValue;

    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;
    var connected: bool = undefined;

    const rc = c.hal_get_pin_value_by_name(name, &hal_type, &data_ptr, &connected);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;

    // Read value based on type using the C hal_data_u union directly
    const b_val = data.*.b;
    return switch (hal_type) {
        c.HAL_BIT => HalValue{ .bit = @as(bool, if (b_val) true else false) },
        c.HAL_FLOAT => HalValue{ .float = data.*.f },
        c.HAL_S32 => HalValue{ .s32 = data.*.s },
        c.HAL_U32 => HalValue{ .u32 = data.*.u },
        else => HalError.TypeMismatch,
    };
}

/// Read from a HAL signal by name
///
/// This function reads the current value from a HAL signal by name.
/// Uses HAL API function hal_get_signal_value_by_name which works
/// with opaque types.
///
/// Parameters:
///   - name: Null-terminated signal name
///
/// Returns:
///   - HalValue union containing the signal's value
///   - error.NotFound if signal doesn't exist
///   - error.TypeMismatch if signal type is invalid
///
/// Thread safety:
///   - Does not acquire mutex (reads are lock-free)
///   - Value may be updated concurrently by HAL real-time thread
pub fn getSignalValueByName(name: [*:0]const u8) !@import("../state/cache.zig").HalValue {
    const HalValue = @import("../state/cache.zig").HalValue;

    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;
    var has_writers: bool = undefined;

    const rc = c.hal_get_signal_value_by_name(name, &hal_type, &data_ptr, &has_writers);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;

    // Read value based on type using the C hal_data_u union directly
    const b_val = data.*.b;
    return switch (hal_type) {
        c.HAL_BIT => HalValue{ .bit = @as(bool, if (b_val) true else false) },
        c.HAL_FLOAT => HalValue{ .float = data.*.f },
        c.HAL_S32 => HalValue{ .s32 = data.*.s },
        c.HAL_U32 => HalValue{ .u32 = data.*.u },
        else => HalError.TypeMismatch,
    };
}

/// Read from a HAL parameter by name
///
/// This function reads the current value from a HAL parameter by name.
/// Uses HAL API function hal_get_param_value_by_name which works
/// with opaque types.
///
/// Parameters:
///   - name: Null-terminated parameter name
///
/// Returns:
///   - HalValue union containing the parameter's value
///   - error.NotFound if parameter doesn't exist
///   - error.TypeMismatch if parameter type is invalid
///
/// Thread safety:
///   - Does not acquire mutex (reads are lock-free)
///   - Value may be updated concurrently by HAL real-time thread
pub fn getParamValueByName(name: [*:0]const u8) !@import("../state/cache.zig").HalValue {
    const HalValue = @import("../state/cache.zig").HalValue;

    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;

    const rc = c.hal_get_param_value_by_name(name, &hal_type, &data_ptr);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;

    // Read value based on type using the C hal_data_u union directly
    const b_val = data.*.b;
    return switch (hal_type) {
        c.HAL_BIT => HalValue{ .bit = @as(bool, if (b_val) true else false) },
        c.HAL_FLOAT => HalValue{ .float = data.*.f },
        c.HAL_S32 => HalValue{ .s32 = data.*.s },
        c.HAL_U32 => HalValue{ .u32 = data.*.u },
        else => HalError.TypeMismatch,
    };
}

/// Set the value of a HAL bit param by name
pub fn setParamBitByName(name: [*:0]const u8, value: bool) !void {
    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;

    const rc = c.hal_get_param_value_by_name(name, &hal_type, &data_ptr);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;
    if (hal_type != c.HAL_BIT) return HalError.TypeMismatch;

    data.*.b = value;
}

/// Set the value of a HAL float param by name
pub fn setParamFloatByName(name: [*:0]const u8, value: f64) !void {
    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;

    const rc = c.hal_get_param_value_by_name(name, &hal_type, &data_ptr);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;
    if (hal_type != c.HAL_FLOAT) return HalError.TypeMismatch;

    data.*.f = value;
}

/// Set the value of a HAL s32 param by name
pub fn setParamS32ByName(name: [*:0]const u8, value: i32) !void {
    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;

    const rc = c.hal_get_param_value_by_name(name, &hal_type, &data_ptr);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;
    if (hal_type != c.HAL_S32) return HalError.TypeMismatch;

    data.*.s = value;
}

/// Set the value of a HAL u32 param by name
pub fn setParamU32ByName(name: [*:0]const u8, value: u32) !void {
    var hal_type: c_int = undefined;
    var data_ptr: [*c]c.hal_data_u = undefined;

    const rc = c.hal_get_param_value_by_name(name, &hal_type, &data_ptr);
    if (rc != 0) return HalError.NotFound;

    const data = data_ptr orelse return HalError.NotFound;
    if (hal_type != c.HAL_U32) return HalError.TypeMismatch;

    data.*.u = value;
}

/// Set the value of a HAL param by name (union-based)
///
/// This is a convenience function that dispatches to the type-specific
/// setParam*ByName functions based on the HalValue tag.
pub fn setParamValueByName(name: [*:0]const u8, value: @import("../state/cache.zig").HalValue) !void {
    switch (value) {
        .bit => |v| try setParamBitByName(name, v),
        .float => |v| try setParamFloatByName(name, v),
        .s32 => |v| try setParamS32ByName(name, v),
        .u32 => |v| try setParamU32ByName(name, v),
    }
}

// SetParam functions are disabled for ULAPI build due to opaque types
// These would need to use different HAL API functions or be implemented differently
// For now, provide stub functions that return an error
pub fn setParamBit(param: ?*hal_param_t, value: bool) !void {
    _ = param;
    _ = value;
    return HalError.InitFailed;
}

pub fn setParamFloat(param: ?*hal_param_t, value: f64) !void {
    _ = param;
    _ = value;
    return HalError.InitFailed;
}

pub fn setParamS32(param: ?*hal_param_t, value: i32) !void {
    _ = param;
    _ = value;
    return HalError.InitFailed;
}

pub fn setParamU32(param: ?*hal_param_t, value: u32) !void {
    _ = param;
    _ = value;
    return HalError.InitFailed;
}

/// Read from a HAL signal (deprecated - use getSignalValueByName)
/// This function is kept for compatibility but may not work with opaque types
pub fn getSignalValue(sig: *const hal_sig_t) !@import("../state/cache.zig").HalValue {
    _ = sig;
    return HalError.InitFailed;
}

/// Read from a HAL parameter (deprecated - use getParamValueByName)
/// This function is kept for compatibility but may not work with opaque types
pub fn getParamValue(param: *const hal_param_t) !@import("../state/cache.zig").HalValue {
    _ = param;
    return HalError.InitFailed;
}

/// Get the name of a HAL pin from an opaque pointer
///
/// This function extracts the name field from a hal_pin_t struct.
/// The name is stored as char name[HAL_NAME_LEN + 1] at offset 64.
///
/// Struct layout from hal_priv.h (64-bit):
///   - next_ptr:       8 bytes  (offset 0)
///   - data_ptr_addr:  8 bytes  (offset 8)
///   - owner_ptr:      8 bytes  (offset 16)
///   - signal:         8 bytes  (offset 24)
///   - dummysig:       8 bytes  (offset 32)
///   - oldname:        8 bytes  (offset 40)
///   - type:           4 bytes  (offset 48)
///   - dir:            4 bytes  (offset 52)
///   - name:          48 bytes  (offset 56 with padding, 64 aligned)
///
/// Parameters:
///   - pin: Opaque pointer to hal_pin_t
///
/// Returns:
///   - Pointer to null-terminated name string
///   - null if pin is null
///
/// Thread safety:
///   - Read-only access, no locking needed
///   - Name string persists as long as pin exists
pub fn getPinName(pin: ?*anyopaque) ?[*:0]const u8 {
    if (pin) |p| {
        // Offset based on hal_priv.h struct layout
        // 6 pointers + 1 union (8 bytes) + 2 ints + padding = 64 bytes
        const ptr: [*]u8 = @ptrCast(p);
        const name_ptr = ptr + 64;
        return @ptrCast(name_ptr);
    }
    return null;
}

/// Get the name of a HAL signal from an opaque pointer
///
/// Struct layout from hal_priv.h (64-bit):
///   - next_ptr:       8 bytes  (offset 0)
///   - data_ptr:       8 bytes  (offset 8)
///   - type:           4 bytes  (offset 16)
///   - readers:        4 bytes  (offset 20)
///   - writers:        4 bytes  (offset 24)
///   - bidirs:         4 bytes  (offset 28)
///   - name:          48 bytes  (offset 32)
///
/// Parameters:
///   - sig: Opaque pointer to hal_sig_t
///
/// Returns:
///   - Pointer to null-terminated name string
///   - null if sig is null
pub fn getSignalName(sig: ?*anyopaque) ?[*:0]const u8 {
    if (sig) |s| {
        // Offset based on hal_priv.h struct layout
        // 2 pointers + 4 ints = 32 bytes
        const ptr: [*]u8 = @ptrCast(s);
        const name_ptr = ptr + 32;
        return @ptrCast(name_ptr);
    }
    return null;
}

/// Get the name of a HAL parameter from an opaque pointer
///
/// Struct layout from hal_priv.h (64-bit):
///   - next_ptr:       8 bytes  (offset 0)
///   - data_ptr:       8 bytes  (offset 8)
///   - owner_ptr:      8 bytes  (offset 16)
///   - oldname:        8 bytes  (offset 24)
///   - type:           4 bytes  (offset 32)
///   - dir:            4 bytes  (offset 36)
///   - name:          48 bytes  (offset 40 with padding, 48 aligned)
///
/// Parameters:
///   - param: Opaque pointer to hal_param_t
///
/// Returns:
///   - Pointer to null-terminated name string
///   - null if param is null
pub fn getParamName(param: ?*anyopaque) ?[*:0]const u8 {
    if (param) |p| {
        // Offset based on hal_priv.h struct layout
        // 4 pointers + 2 ints = 40 bytes (with padding to 48 for alignment)
        const ptr: [*]u8 = @ptrCast(p);
        const name_ptr = ptr + 48;
        return @ptrCast(name_ptr);
    }
    return null;
}

/// Get the component ID from an opaque hal_comp_t pointer
///
/// This function extracts the comp_id field from a hal_comp_t struct.
///
/// Struct layout from hal_priv.h (64-bit):
///   - next_ptr:       8 bytes  (offset 0)
///   - comp_id:        4 bytes  (offset 8)
///   - mem_id:         4 bytes  (offset 12)
///   - type:           4 bytes  (offset 16)
///   - ready:          4 bytes  (offset 20)
///   - pid:            4 bytes  (offset 24)
///   - shmem_base:     8 bytes  (offset 32 with padding)
///   ... (name is later)
///
/// Parameters:
///   - comp: Opaque pointer to hal_comp_t
///
/// Returns:
///   - Component ID on success
///   - error.NotFound if comp is null
pub fn halCompIdFromPtr(comp: ?*anyopaque) !c_int {
    if (comp) |comp_ptr| {
        // comp_id is at offset 8 (after next_ptr)
        const ptr: [*]u8 = @ptrCast(comp_ptr);
        const comp_id_ptr: [*]c_int = @ptrCast(@alignCast(ptr + 8));
        return comp_id_ptr[0];
    }
    return HalError.NotFound;
}

/// Get the name of a HAL component by ID
///
/// This is a wrapper around the public hal_comp_name() function from hal.h.
///
/// Parameters:
///   - comp_id: Component ID
///
/// Returns:
///   - Pointer to null-terminated name string, or null if not found
pub fn getCompNameById(comp_id: c_int) ?[*:0]const u8 {
    return @import("c.zig").c.hal_comp_name(comp_id);
}

/// Iterate through all pins owned by a component
///
/// This function returns the first pin owned by the component when start is null,
/// or the next pin when start is a previously returned pin.
///
/// Parameters:
///   - comp: Opaque pointer to hal_comp_t (component)
///   - start: null for first pin, or previously returned pin for next
///
/// Returns:
///   - Opaque pointer to hal_pin_t, or null if no more pins
///
/// Thread safety:
///   - Requires HAL mutex (halpr functions don't acquire it)
pub fn findPinByOwner(comp: ?*anyopaque, start: ?*anyopaque) ?*anyopaque {
    return @import("c.zig").c.halpr_find_pin_by_owner(comp, start);
}

/// Iterate through all parameters owned by a component
///
/// This function returns the first param owned by the component when start is null,
/// or the next param when start is a previously returned param.
///
/// Parameters:
///   - comp: Opaque pointer to hal_comp_t (component)
///   - start: null for first param, or previously returned param for next
///
/// Returns:
///   - Opaque pointer to hal_param_t, or null if no more params
pub fn findParamByOwner(comp: ?*anyopaque, start: ?*anyopaque) ?*anyopaque {
    return @import("c.zig").c.halpr_find_param_by_owner(comp, start);
}

/// Find component by name
///
/// Parameters:
///   - name: Null-terminated component name
///
/// Returns:
///   - Opaque pointer to hal_comp_t, or null if not found
pub fn findCompByName(name: [*:0]const u8) ?*anyopaque {
    return @import("c.zig").c.halpr_find_comp_by_name(name);
}

/// Find component by ID
///
/// Parameters:
///   - comp_id: Component ID
///
/// Returns:
///   - Opaque pointer to hal_comp_t, or null if not found
pub fn findCompById(comp_id: c_int) ?*anyopaque {
    return @import("c.zig").c.halpr_find_comp_by_id(comp_id);
}

// Note: Discovery functions (firstPin, nextPin, firstSignal, nextSignal, firstParam, nextParam)
// have been moved to safe_discovery.zig to avoid duplication and maintain separation of concerns.

/// Pin direction enum (matches HAL's hal_pin_dir_t)
pub const PinDirection = enum(c_int) {
    in = c.HAL_IN,
    out = c.HAL_OUT,
    io = c.HAL_IO,
    unspecified = c.HAL_DIR_UNSPECIFIED,
};

/// Get pin direction by accessing HAL pin structure directly
///
/// This function accesses the HAL shared memory to read the pin's direction
/// attribute directly from the hal_pin_t structure, just like halcmd does.
///
/// Parameters:
///   - name: Null-terminated pin name
///
/// Returns:
///   - PinDirection enum value
///   - error.NotFound if pin doesn't exist
///
/// Thread safety:
///   - halpr_find_pin_by_name doesn't acquire mutex, but reading the dir field
///     is safe since it's read-only after pin creation
///
/// Source: LinuxCNC halcmd_commands.cc (accesses pin->dir directly)
pub fn getPinDir(name: [*:0]const u8) !PinDirection {
    const pin_ptr = @import("c.zig").halpr_find_pin_by_name(name) orelse return HalError.NotFound;

    // Cast to hal_pin_t to access the dir field
    // This is safe in userspace - we're reading from HAL shared memory
    const pin: *const @import("c.zig").hal_pin_t = @ptrCast(@alignCast(pin_ptr));

    // Convert HAL direction constant to our enum
    return switch (pin.dir) {
        c.HAL_IN => .in,
        c.HAL_OUT => .out,
        c.HAL_IO => .io,
        c.HAL_DIR_UNSPECIFIED => .unspecified,
        else => .unspecified,
    };
}

/// Get param direction by accessing HAL param structure directly
///
/// Similar to getPinDir but for parameters.
///
/// Parameters:
///   - name: Null-terminated param name
///
/// Returns:
///   - ParamDirection enum value
///   - error.NotFound if param doesn't exist
pub const ParamDirection = enum(u8) {
    ro = 0, // Read-only
    rw = 1, // Read-write
};

pub fn getParamDir(_: [*:0]const u8) !ParamDirection {
    // HAL params use HAL_RO and HAL_RW constants
    // For now, we'll return rw as default since most params are writable
    // TODO: Add full hal_param_t structure if needed
    return .rw;
}

// Verify signal functions exist at compile time
comptime {
    _ = halSignalNew;
    _ = halLink;
    _ = halUnlink;
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

    // Verify pin, signal and param value readers (ByName variants for ULAPI)
    _ = getPinValueByName;
    _ = getSignalValueByName;
    _ = getParamValueByName;

    // Note: setParam* functions are not available in ULAPI due to opaque types
}
