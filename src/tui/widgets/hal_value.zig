// Shared HAL value formatting and editing logic for TreeView and DataTable
//
// This module provides common functions for:
// - Formatting HAL values for display (●/○ for bits, numbers for others)
// - Checking if a HAL item is writable (considering direction and signal connections)

const std = @import("std");
const HalValue = @import("../../state/cache.zig").HalValue;
const StateStore = @import("../../state/cache.zig").StateStore;
const safe = @import("../../ffi/safe.zig");

/// Item type (pin, signal, or parameter)
pub const ItemType = enum {
    /// Pin (IN/OUT/IO)
    pin,
    /// Signal (wire connecting pins)
    signal,
    /// Parameter (configurable value)
    param,
};

/// Format a HAL value for display in the value column
/// Uses compact formatting: ●/○ for BIT, no trailing zeros for FLOAT
///
/// This is shared between TreeView and DataTable for consistent display.
pub fn formatHalValue(value: HalValue, allocator: std.mem.Allocator) ![]const u8 {
    return switch (value) {
        .bit => |v| if (v) "\xe2\x97\x8f" else "\xe2\x97\x8b", // UTF-8 for ●/○
        .float => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR", // No trailing zeros
        .s32 => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR",
        .u32 => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR",
    };
}

/// Check if a HAL item is writable
///
/// Rules:
/// - Pins connected to signals are NOT writable (they get value from signal)
/// - IN and IO pins are writable (OUT pins are read-only outputs)
/// - Only RW params are writable
/// - Signals are always writable
///
/// This is shared between TreeView and DataTable for consistent behavior.
///
/// Parameters:
///   - allocator: Memory allocator for temporary allocations
///   - store: StateStore for checking signal connections
///   - item_type: Type of HAL item
///   - name: Full name of the HAL item
///
/// Returns:
///   - true if the item is writable, false otherwise
pub fn isItemWritable(
    allocator: std.mem.Allocator,
    store: *StateStore,
    item_type: ItemType,
    name: []const u8,
) bool {
    return if (item_type == .pin) blk: {
        // Check if pin is connected to a signal
        const NameKey = @import("../../state/cache.zig").NameKey;
        if (store.pin_links.get(NameKey.fromStr(name))) |_| {
            break :blk false; // Connected pins get value from signal
        }

        // Check pin direction - IN and IO pins are writable (OUT pins are read-only outputs)
        const name_z = allocator.dupeZ(u8, name) catch return true; // Assume writable if allocation fails
        defer allocator.free(name_z);

        if (safe.getPinDir(name_z)) |dir| {
            break :blk dir == .in or dir == .io; // IN and IO pins are writable
        } else |_| {
            break :blk true; // Can't determine direction, assume writable
        }
    } else if (item_type == .param) blk: {
        // Check param direction - only RW params are writable
        const name_z = allocator.dupeZ(u8, name) catch return true;
        defer allocator.free(name_z);

        if (safe.getParamDir(name_z)) |dir| {
            break :blk dir == .rw; // Only RW params are writable
        } else |_| {
            break :blk true; // Can't determine direction, assume writable
        }
    } else blk: {
        // Signals are always writable
        break :blk true;
    };
}

// Compile-time tests to verify API surface
comptime {
    _ = formatHalValue;
    _ = isItemWritable;
}
