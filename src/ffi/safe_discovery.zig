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
        std.debug.print("HALCMD ERROR: Failed to run halcmd: {} ({s})\n", .{ err, @errorName(err) });
        return err;
    };
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }

    // Check if the process exited successfully (exit code 0)
    if (result.term == .Exited and result.term.Exited == 0) {
        return HalcmdResult{
            .output = try allocator.dupe(u8, result.stdout),
            .allocator = allocator,
        };
    } else {
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
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    const cmd_result = try runHalcmd(allocator, &[_][]const u8{ "list", "pin" });
    defer cmd_result.deinit();

    // Trim trailing whitespace to avoid empty tokens
    const trimmed = std.mem.trimRight(u8, cmd_result.output, " \t\n\r");
    var iter = std.mem.tokenizeScalar(u8, trimmed, ' ');
    while (iter.next()) |pin_name| {
        if (pin_name.len > 0 and isValidHalName(pin_name)) {
            // NOTE: tokenizer returns slice of cmd_result.output, which gets freed
            // We MUST dupe the string to own the memory
            try result.append(allocator, try allocator.dupe(u8, pin_name));
        }
    }

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

