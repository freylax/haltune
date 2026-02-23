// HAL Wiring Save/Restore
//
// This module provides functionality to save and restore pin connections to signals.
// This is used when activating/deactivating plugins to preserve existing wiring.
//
// Design principles:
// - saveConnection() records the current signal a pin is connected to
// - restoreConnection() unwires from plugin signal and restores original connection
// - Memory ownership is clearly tracked (old_signal is allocated and owned)

const std = @import("std");

// Direct C imports for HAL functions
pub const c = @cImport({
    @cDefine("ULAPI", "");
    @cInclude("hal.h");
});

// Use HalError from errors module
pub const HalError = @import("errors").HalError;

/// HAL pin structure for accessing signal field
///
/// This matches the layout in hal_priv.h for accessing pin signal info.
pub const hal_pin_t = extern struct {
    next_ptr: [*c]hal_pin_t,
    data_ptr_addr: ?*anyopaque,
    owner_ptr: ?*anyopaque,
    signal: ?*anyopaque, // Pointer to hal_sig_t if connected, null if unlinked
    dummysig: c.hal_data_u,
    oldname: ?*anyopaque,
    type: c_int,
    dir: c_int,
    name: [48 + 1]u8, // HAL_NAME_LEN + 1
};

/// HAL signal structure for accessing signal name
pub const hal_sig_t = extern struct {
    next_ptr: [*c]hal_sig_t,
    data_ptr_addr: ?*anyopaque,
    writers: c_int,
    readers: c_int,
    oldname: ?*anyopaque,
    type: c_int,
    name: [48 + 1]u8, // HAL_NAME_LEN + 1
};

/// Wiring state records a pin's original connection
///
/// When activating a plugin, we save each pin's current connection so we can
/// restore it when deactivating the plugin.
pub const WiringState = struct {
    /// Pin name (owned, must be freed)
    pin_name: []const u8,
    /// Original signal name (owned if non-null, must be freed)
    /// null means the pin was not connected to any signal
    old_signal: ?[]const u8,

    /// Clean up the wiring state
    pub fn deinit(self: *WiringState, allocator: std.mem.Allocator) void {
        allocator.free(self.pin_name);
        if (self.old_signal) |sig| {
            allocator.free(sig);
        }
        self.* = undefined;
    }
};

/// Save the current connection state of a pin
///
/// This function queries HAL to find the pin and record what signal it's
/// currently connected to (if any).
///
/// Parameters:
///   - pin_name: Name of the pin to check
///   - allocator: Memory allocator for owned strings
///
/// Returns:
///   - WiringState on success (caller owns the memory)
///   - null if pin not found
pub fn saveConnection(pin_name: []const u8, allocator: std.mem.Allocator) !?WiringState {
    // Create null-terminated pin name for C API
    const pin_name_z = try std.fmt.allocPrintZ(allocator, "{s}\x00", .{pin_name});
    defer allocator.free(pin_name_z);

    // Find the pin in HAL
    const pin_ptr = c.halpr_find_pin_by_name(pin_name_z.ptr);
    if (pin_ptr == null) {
        // Pin doesn't exist in HAL
        return null;
    }

    const pin: *const hal_pin_t = @ptrCast(@alignCast(pin_ptr));

    // Get the signal name if connected
    var signal_name: ?[]const u8 = null;
    if (pin.signal != null) {
        const sig_ptr: *const hal_sig_t = @ptrCast(@alignCast(pin.signal));
        // Convert C string to Zig slice
        const sig_name_c: [*:0]const u8 = @ptrCast(&sig_ptr.name);
        signal_name = try allocator.dupe(u8, std.mem.span(sig_name_c));
    }

    // Duplicate pin name for ownership
    const owned_pin_name = try allocator.dupe(u8, pin_name);

    return WiringState{
        .pin_name = owned_pin_name,
        .old_signal = signal_name,
    };
}

/// Restore a pin's connection to its original signal
///
/// This function unwires a pin from its current signal and restores it to
/// the signal it was originally connected to (or disconnects if it had none).
///
/// Parameters:
///   - state: The wiring state to restore
pub fn restoreConnection(state: WiringState) !void {
    // First, unlink the pin from whatever it's currently connected to
    const pin_name_z = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}\x00", .{state.pin_name});
    defer std.heap.page_allocator.free(pin_name_z);

    _ = c.hal_unlink(pin_name_z.ptr);

    // If there was an original signal, reconnect to it
    if (state.old_signal) |old_sig| {
        const old_sig_z = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}\x00", .{old_sig});
        defer std.heap.page_allocator.free(old_sig_z);

        _ = c.hal_link(pin_name_z.ptr, old_sig_z.ptr);
    }
}

/// Connect a pin to a signal
///
/// Parameters:
///   - pin_name: Name of the pin
///   - signal_name: Name of the signal to connect to
///
/// Returns:
///   - void on success
///   - error.LinkFailed if link fails
pub fn connectPin(pin_name: []const u8, signal_name: []const u8) !void {
    const pin_z = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}\x00", .{pin_name});
    defer std.heap.page_allocator.free(pin_z);

    const sig_z = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}\x00", .{signal_name});
    defer std.heap.page_allocator.free(sig_z);

    const rc = c.hal_link(pin_z.ptr, sig_z.ptr);
    if (rc != 0) return HalError.LinkFailed;
}

/// Disconnect a pin from its signal
///
/// Parameters:
///   - pin_name: Name of the pin to disconnect
///
/// Returns:
///   - void on success
///   - error.UnlinkFailed if unlink fails
pub fn disconnectPin(pin_name: []const u8) !void {
    const pin_z = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}\x00", .{pin_name});
    defer std.heap.page_allocator.free(pin_z);

    const rc = c.hal_unlink(pin_z.ptr);
    if (rc != 0) return HalError.UnlinkFailed;
}

/// Free a WiringState and all its owned memory
///
/// This is a convenience wrapper for deinit()
pub fn freeWiringState(state: ?WiringState, allocator: std.mem.Allocator) void {
    if (state) |s| {
        s.deinit(allocator);
    }
}
