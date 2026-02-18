//! Logging configuration for haltune
//!
//! Redirects std.log output to a file when --log-file is specified.
//! When no log file is specified, logging is disabled entirely
//! to avoid interfering with the TUI.

const std = @import("std");

/// Global log file handle
pub var log_file: ?std.fs.File = null;
var log_mutex: std.Thread.Mutex = .{};

/// Buffered writer for log file (4KB buffer)
var buffered_writer: ?std.io.BufferedWriter(4096, std.fs.File, .{}) = null;

/// Write to log file (thread-safe, internal)
/// This function has the signature expected by std.options.log_fn
pub fn logWrite(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const writer = buffered_writer orelse return;
    log_mutex.lock();
    defer log_mutex.unlock();

    // Format: [timestamp] [LEVEL] scope: message
    const timestamp = std.time.timestamp();
    const level_txt = comptime message_level.asText();

    writer.print("[{d}] [{s}] {s}: " ++ format ++ "\n", .{
        timestamp, level_txt, @tagName(scope),
    } ++ args) catch {};

    // Flush after each log to ensure messages are written
    writer.flush() catch {};
}

/// Initialize logging with the specified file path
/// Pass null to disable logging entirely
pub fn init(file_path: ?[]const u8) !void {
    if (file_path) |path| {
        log_file = try std.fs.cwd().createFile(path, .{ .read = true });
        buffered_writer = std.io.bufferedWriter(log_file.?);
        try logWriteAll("=== haltune log started ===\n");
    } else {
        log_file = null;
        buffered_writer = null;
    }
}

/// Cleanup logging (closes log file)
pub fn deinit() void {
    if (buffered_writer) |*bw| {
        bw.flush() catch {};
        buffered_writer = null;
    }
    if (log_file) |file| {
        logWriteAll("=== haltune log ended ===\n") catch {};
        file.close();
        log_file = null;
    }
}

/// Write to log file (thread-safe)
fn logWriteAll(text: []const u8) !void {
    const writer = buffered_writer orelse return error.FileNotOpen;
    log_mutex.lock();
    defer log_mutex.unlock();
    try writer.writeAll(text);
    try writer.flush();
}
