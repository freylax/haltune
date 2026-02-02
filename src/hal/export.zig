// HAL configuration export module
//
// This module provides functionality to export current HAL configuration
// to halcmd-compatible text format for backup and restoration.

const std = @import("std");
const StateStore = @import("../state/cache.zig").StateStore;
const HalValue = @import("../state/cache.zig").HalValue;

/// Export current HAL configuration to halcmd-compatible format
///
/// This function generates a text representation of the current HAL state
/// that can be loaded back with halcmd -f filename.hal
///
/// Parameters:
///   - allocator: Memory allocator for temporary allocations
///   - store: StateStore containing current HAL state
///   - writer: Any writer with write() method (file, buffer, etc.)
///
/// Returns:
///   - void on success
///   - error.OutOfMemory if allocation fails
///   - error.WriteError if I/O fails
///
/// Format:
///   - Header comment with timestamp
///   - net commands for signals with pin connections
///   - setp commands for parameter values
pub fn exportHalConfiguration(
    allocator: std.mem.Allocator,
    store: *StateStore,
    writer: anytype,
) !void {
    // Write header
    const timestamp = std.time.timestamp();
    try writer.print("# HAL configuration exported by haltune\n", .{});
    try writer.print("# Generated: {}\n\n", .{timestamp});

    // Export signals
    try exportSignals(allocator, store, writer);

    // Export parameters
    try exportParams(allocator, store, writer);
}

/// Export all signals with pin connections
fn exportSignals(
    allocator: std.mem.Allocator,
    store: *StateStore,
    writer: anytype,
) !void {
    try writer.writeAll("# Signals\n");

    const signal_names = try store.listSignals(allocator);
    defer allocator.free(signal_names);

    for (signal_names) |sig_name| {
        // Get signal value
        const sig_value = try store.getSignal(sig_name);

        // Get pins linked to this signal
        const pins = try store.getSignalLinks(allocator, sig_name);
        defer allocator.free(pins);
        defer {
            for (pins) |pin| allocator.free(pin);
        }

        // Format: net signame pin1 pin2 pin3...
        try writer.print("net {s}", .{sig_name});

        // Write linked pins
        if (pins.len > 0) {
            for (pins) |pin| {
                try writer.print(" {s}", .{pin});
            }
        }

        // Write initial value if non-zero/default
        try writer.print("\t# value: ", .{});
        switch (sig_value) {
            .bit => |v| try writer.print("{}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
            .s32 => |v| try writer.print("{}", .{v}),
            .u32 => |v| try writer.print("{}", .{v}),
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("\n");
}

/// Export all parameters with current values
fn exportParams(
    allocator: std.mem.Allocator,
    store: *StateStore,
    writer: anytype,
) !void {
    try writer.writeAll("# Parameters\n");

    const param_names = try store.listParams(allocator);
    defer allocator.free(param_names);

    for (param_names) |param_name| {
        const param_value = try store.getParam(param_name);

        // Format: setp param.name value
        try writer.print("setp {s} ", .{param_name});
        switch (param_value) {
            .bit => |v| try writer.print("{}\n", .{v}),
            .float => |v| try writer.print("{d}\n", .{v}),
            .s32 => |v| try writer.print("{}\n", .{v}),
            .u32 => |v| try writer.print("{}\n", .{v}),
        }
    }
}
