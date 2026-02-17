//! Logging configuration for haltune
//!
//! Redirects std.log output to a file when --log-file is specified.
//! When no log file is specified, logging is disabled entirely
//! to avoid interfering with the TUI.

const std = @import("std");

/// Global log file handle
var log_file: ?std.fs.File = null;
var log_mutex: std.Thread.Mutex = .{};

/// Initialize logging with the specified file path
/// Pass null to disable logging entirely
pub fn init(file_path: ?[]const u8) !void {
    if (file_path) |path| {
        log_file = try std.fs.cwd().createFile(path, .{ .read = true });
        try logWriteAll("=== haltune log started ===\n");
    } else {
        log_file = null;
    }
}

/// Cleanup logging (closes log file)
pub fn deinit() void {
    if (log_file) |file| {
        logWriteAll("=== haltune log ended ===\n") catch {};
        file.close();
        log_file = null;
    }
}

/// Write to log file (thread-safe)
fn logWriteAll(text: []const u8) !void {
    const file = log_file orelse return;
    log_mutex.lock();
    defer log_mutex.unlock();
    try file.writeAll(text);
}

/// Get the current log file (null if not configured)
pub fn getLogFile() ?std.fs.File {
    return log_file;
}

/// Check if logging is enabled
pub fn isEnabled() bool {
    return log_file != null;
}

// Configure std.log to use our handler
pub const std_options = struct {
    /// Log function that writes to file or discards output
    pub fn log(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const file = log_file orelse return;
        log_mutex.lock();
        defer log_mutex.unlock();

        // Format: [timestamp] [LEVEL] scope: message
        const timestamp = std.time.timestamp();
        const level_txt = comptime level.asText();
        file.writer().print(
            "[{d}] [{s}] {s}: " ++ format ++ "\n",
            .{ timestamp, level_txt, @tagName(scope) } ++ args,
        ) catch {};
    }

    /// Return true to enable stderr fallback (we don't want this)
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        // Override log function to prevent stderr output
        log(level, scope, format, args);
    }
};
