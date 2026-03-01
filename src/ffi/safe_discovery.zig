// HAL discovery helpers using halcmd command
//
// This module provides functions to iterate through HAL pins, signals, and
// parameters by calling halcmd and parsing the output.
//
// This is necessary because the HAL API doesn't provide functions to iterate
// through all items - halpr_find_pin_by_owner with NULL as owner doesn't work.
//
// Design principles:
// - Use halcmd list/ls commands to discover HAL items
// - Parse the output to get pin/param/signal names

const std = @import("std");
const c_import = @import("c.zig");
const c = c_import.c;

/// Result of running halcmd command
const HalcmdResult = struct {
    output: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: HalcmdResult) void {
        self.allocator.free(self.output);
    }
};

/// Run halcmd and return the output
fn runHalcmd(allocator: std.mem.Allocator, args: []const []const u8) !HalcmdResult {
    // Build argv array at runtime
    var argv_list = try std.ArrayList([]const u8).initCapacity(allocator, args.len + 1);
    defer argv_list.deinit(allocator);
    try argv_list.append(allocator, "halcmd");
    for (args) |arg| {
        try argv_list.append(allocator, arg);
    }

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv_list.items,
    }) catch |err| {
        std.log.err("HALCMD ERROR: Failed to run halcmd: {} ({s})", .{ err, @errorName(err) });
        return err;
    };
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }

    std.log.info("HALCMD: exit code={}, stdout_len={d}, stderr_len={d}", .{ result.term, result.stdout.len, result.stderr.len });
    if (result.stderr.len > 0) {
        std.log.info("HALCMD stderr: {s}", .{result.stderr[0..@min(200, result.stderr.len)]});
    }
    if (result.stdout.len > 0) {
        std.log.info("HALCMD stdout (first 300 chars): {s}", .{result.stdout[0..@min(300, result.stdout.len)]});
    }

    // Check if the process exited successfully (exit code 0)
    if (result.term == .Exited and result.term.Exited == 0) {
        return HalcmdResult{
            .output = try allocator.dupe(u8, result.stdout),
            .allocator = allocator,
        };
    } else {
        std.log.err("HALCMD: Process failed with term: {}", .{result.term});
        return error.HalcmdFailed;
    }
}

/// Check if a string looks like a valid HAL pin/param/signal name
///
/// Valid HAL names contain only alphanumeric characters plus dash, dot, underscore.
/// This filters out halcmd header text like "Component", "Pins:", "Type", etc.
fn isValidHalName(name: []const u8) bool {
    if (name.len == 0) return false;

    for (name) |ch| {
        // Allow: a-z, A-Z, 0-9, '-', '.', '_'
        const is_valid = (ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9') or
            ch == '-' or ch == '.' or ch == '_';
        if (!is_valid) return false;
    }
    return true;
}

/// List all pin names from HAL
pub fn listPinNames(allocator: std.mem.Allocator) anyerror!std.ArrayList([]const u8) {
    std.log.info("listPinNames: Starting pin discovery", .{});
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    const cmd_result = try runHalcmd(allocator, &[_][]const u8{ "list", "pin" });
    defer cmd_result.deinit();

    // Trim trailing whitespace to avoid empty tokens
    const trimmed = std.mem.trimRight(u8, cmd_result.output, " \t\n\r");
    std.log.info("listPinNames: trimmed output length: {d}", .{trimmed.len});
    var iter = std.mem.tokenizeScalar(u8, trimmed, ' ');
    var token_count: usize = 0;
    var valid_count: usize = 0;
    while (iter.next()) |pin_name| {
        token_count += 1;
        if (pin_name.len > 0 and isValidHalName(pin_name)) {
            valid_count += 1;
            // NOTE: tokenizer returns slice of cmd_result.output, which gets freed
            // We MUST dupe the string to own the memory
            try result.append(allocator, try allocator.dupe(u8, pin_name));
        }
    }

    std.log.info("listPinNames: Found {d} tokens, {d} valid names, returning {d} pins", .{ token_count, valid_count, result.items.len });
    return result;
}

/// List all param names from HAL
pub fn listParamNames(allocator: std.mem.Allocator) anyerror!std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 4);
    const cmd_result = try runHalcmd(allocator, &[_][]const u8{ "list", "param" });
    defer cmd_result.deinit();

    // Trim trailing whitespace to avoid empty tokens
    const trimmed = std.mem.trimRight(u8, cmd_result.output, " \t\n\r");
    var iter = std.mem.tokenizeScalar(u8, trimmed, ' ');
    while (iter.next()) |param_name| {
        if (param_name.len > 0 and isValidHalName(param_name)) {
            try result.append(allocator, try allocator.dupe(u8, param_name));
        }
    }

    return result;
}

/// List all signal names from HAL
pub fn listSignalNames(allocator: std.mem.Allocator) anyerror!std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 4);
    const cmd_result = try runHalcmd(allocator, &[_][]const u8{ "list", "sig" });
    defer cmd_result.deinit();

    // Trim trailing whitespace to avoid empty tokens
    const trimmed = std.mem.trimRight(u8, cmd_result.output, " \t\n\r");
    var iter = std.mem.tokenizeScalar(u8, trimmed, ' ');
    while (iter.next()) |sig_name| {
        if (sig_name.len > 0 and isValidHalName(sig_name)) {
            try result.append(allocator, try allocator.dupe(u8, sig_name));
        }
    }

    return result;
}

/// Detailed pin information from halcmd
pub const PinDetail = struct {
    name: []const u8,
    type: PinType,
    dir: PinDir,
    value: f64,  // For bit pins, this will be 0.0 or 1.0
};

pub const PinType = enum { bit, float, s32, u32 };
pub const PinDir = enum { in, out, io, unspecified };

/// List all pins with detailed information using halcmd show pin
/// This returns all pins with their type, direction, and value in a single call.
pub fn listPinsDetail(allocator: std.mem.Allocator) anyerror!std.ArrayList(PinDetail) {
    std.log.info("listPinsDetail: Starting detailed pin discovery", .{});
    const cmd_result = try runHalcmd(allocator, &[_][]const u8{ "show", "pin" });
    defer cmd_result.deinit();

    var result = try std.ArrayList(PinDetail).initCapacity(allocator, 8);

    // Parse output like:
    // "Component Pins:\nOwner   Type  Dir         Value  Name\n    11  float IN              0  pid.Dgain\n"
    var lines = std.mem.splitScalar(u8, cmd_result.output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimRight(u8, line, " \t\r");
        // Skip header lines
        if (trimmed.len == 0 or
            std.mem.indexOf(u8, trimmed, "Component Pins:") != null or
            std.mem.indexOf(u8, trimmed, "Owner") != null) continue;

        // Parse line: "    11  float IN              0  pid.Dgain"
        var iter = std.mem.tokenizeScalar(u8, trimmed, ' ');
        var fields: [6]?[]const u8 = .{ null, null, null, null, null, null };
        var field_idx: usize = 0;
        while (iter.next()) |field| {
            if (field_idx < fields.len) {
                fields[field_idx] = field;
                field_idx += 1;
            }
        }

        // Find the pin name (last field)
        const pin_name = fields[5] orelse fields[4] orelse fields[3] orelse continue;
        if (!isValidHalName(pin_name)) continue;

        // Parse type (field 1)
        var pin_type: PinType = .float;
        if (fields[1]) |type_str| {
            if (std.mem.eql(u8, type_str, "bit")) pin_type = .bit;
            if (std.mem.eql(u8, type_str, "s32")) pin_type = .s32;
            if (std.mem.eql(u8, type_str, "u32")) pin_type = .u32;
        }

        // Parse direction (field 2)
        var pin_dir: PinDir = .unspecified;
        if (fields[2]) |dir_str| {
            if (std.mem.indexOf(u8, dir_str, "IN") != null) pin_dir = .in;
            if (std.mem.indexOf(u8, dir_str, "OUT") != null) pin_dir = .out;
            if (std.mem.indexOf(u8, dir_str, "I/O") != null) pin_dir = .io;
        }

        // Parse value (field 3)
        var pin_value: f64 = 0.0;
        if (fields[3]) |val_str| {
            // Handle FALSE/TRUE for bit pins
            if (std.mem.eql(u8, val_str, "FALSE")) {
                pin_value = 0.0;
            } else if (std.mem.eql(u8, val_str, "TRUE")) {
                pin_value = 1.0;
            } else {
                pin_value = std.fmt.parseFloat(f64, val_str) catch 0.0;
            }
        }

        try result.append(allocator, PinDetail{
            .name = try allocator.dupe(u8, pin_name),
            .type = pin_type,
            .dir = pin_dir,
            .value = pin_value,
        });
    }

    std.log.info("listPinsDetail: Found {d} pins with details", .{result.items.len});
    return result;
}

