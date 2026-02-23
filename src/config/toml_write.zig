// TOML configuration file writer for haltune
//
// This module serializes TomlConfig back to TOML format.
// This allows saving configuration changes made through the TUI.

const std = @import("std");
const toml = @import("toml");

// Import TomlConfig type from toml_config module
pub const TomlConfig = @import("toml_config").TomlConfig;

/// Write a TomlConfig to TOML format
///
/// Parameters:
///   - allocator: Memory allocator for building the output string
///   - config: The TomlConfig to serialize
///
/// Returns:
///   - Allocated string containing TOML format (caller must free)
///   - error.OutOfMemory if allocation fails
pub fn writeTomlConfigAlloc(allocator: std.mem.Allocator, config: *const TomlConfig) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 512);
    errdefer buffer.deinit(allocator);

    // Write [files] section
    try buffer.appendSlice(allocator, "[files]\n");

    if (config.files.hal_files) |files| {
        try buffer.appendSlice(allocator, "hal_files = [");
        for (files, 0..) |file, i| {
            if (i > 0) try buffer.appendSlice(allocator, ", ");
            try buffer.print(allocator, "\"{s}\"", .{file});
        }
        try buffer.appendSlice(allocator, "]\n");
    }

    if (config.files.ini_files) |files| {
        try buffer.appendSlice(allocator, "ini_files = [");
        for (files, 0..) |file, i| {
            if (i > 0) try buffer.appendSlice(allocator, ", ");
            try buffer.print(allocator, "\"{s}\"", .{file});
        }
        try buffer.appendSlice(allocator, "]\n");
    }

    try buffer.appendSlice(allocator, "\n");

    // Write [logging] section
    try buffer.appendSlice(allocator, "[logging]\n");
    if (config.logging.file) |file| {
        try buffer.print(allocator, "file = \"{s}\"\n", .{file});
    }
    try buffer.appendSlice(allocator, "\n");

    // Write [plugins] section
    try buffer.appendSlice(allocator, "[plugins]\n");
    if (config.plugins.enabled) |plugins| {
        try buffer.appendSlice(allocator, "enabled = [");
        for (plugins, 0..) |plugin, i| {
            if (i > 0) try buffer.appendSlice(allocator, ", ");
            try buffer.print(allocator, "\"{s}\"", .{plugin});
        }
        try buffer.appendSlice(allocator, "]\n");
    }

    return buffer.toOwnedSlice(allocator);
}

/// Write a TomlConfig to a file
///
/// Parameters:
///   - allocator: Memory allocator
///   - file_path: Path to output file
///   - config: The TomlConfig to serialize
///
/// Returns:
///   - error.FileNotFound if directory doesn't exist
///   - error.OutOfMemory if allocation fails
pub fn writeTomlConfigFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    config: *const TomlConfig,
) !void {
    const content = try writeTomlConfigAlloc(allocator, config);
    defer allocator.free(content);

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(content);
}
