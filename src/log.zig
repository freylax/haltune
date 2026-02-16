// Logging module for haltune
//
// Provides logging functions that can write to stderr or a file.
// Use this instead of std.log to avoid cluttering the TUI.

const std = @import("std");

/// Global log file handle (set by root.zig)
pub var log_file: ?std.fs.File = null;

/// Log level
pub const Level = enum {
    debug,
    info,
    warn,
    err,
};

/// Format timestamp for log entry
fn formatTimestamp(buffer: *[32]u8) []const u8 {
    const timestamp = std.time.timestamp();
    return std.fmt.bufPrint(buffer, "{d}", .{timestamp}) catch buffer[0..0];
}

/// Write a log message to the log file (and optionally stderr)
fn logWrite(level: Level, comptime fmt: []const u8, args: anytype) void {
    const level_str = switch (level) {
        .debug => "DEBUG",
        .info => "INFO",
        .warn => "WARN",
        .err => "ERROR",
    };

    var buffer: [1024]u8 = undefined;
    var timestamp_buf: [32]u8 = undefined;
    const ts = formatTimestamp(&timestamp_buf);

    // Build format string with prefix
    const full_fmt = "[{s}] [{s}] " ++ fmt ++ "\n";

    // Create combined args tuple
    const msg = std.fmt.bufPrint(&buffer, full_fmt, .{ ts, level_str } ++ args) catch return;

    if (log_file) |f| {
        f.writeAll(msg) catch {};
    } else {
        std.debug.print("{s}", .{msg});
    }
}

/// Public logging functions
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    logWrite(.debug, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    logWrite(.info, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    logWrite(.warn, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    logWrite(.err, fmt, args);
}
