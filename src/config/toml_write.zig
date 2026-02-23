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
///   - writer: Any writer that implements std.io.Writer interface
///   - config: The TomlConfig to serialize
///
/// Returns:
///   - error.WriteError if writing fails
///   - error.OutOfMemory if allocation fails
pub fn writeTomlConfig(writer: anytype, config: *const TomlConfig) !void {
    // Write [files] section
    try writer.writeAll("[files]\n");

    if (config.files.hal_files) |files| {
        try writer.writeAll("hal_files = [");
        for (files, 0..) |file, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{file});
        }
        try writer.writeAll("]\n");
    }

    if (config.files.ini_files) |files| {
        try writer.writeAll("ini_files = [");
        for (files, 0..) |file, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{file});
        }
        try writer.writeAll("]\n");
    }

    try writer.writeAll("\n");

    // Write [logging] section
    try writer.writeAll("[logging]\n");
    if (config.logging.file) |file| {
        try writer.print("file = \"{s}\"\n", .{file});
    }
    try writer.writeAll("\n");

    // Write [plugins] section
    try writer.writeAll("[plugins]\n");
    if (config.plugins.enabled) |plugins| {
        try writer.writeAll("enabled = [");
        for (plugins, 0..) |plugin, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{plugin});
        }
        try writer.writeAll("]\n");
    }
}

/// Write a TomlConfig to a file
///
/// Parameters:
///   - file_path: Path to output file
///   - config: The TomlConfig to serialize
///
/// Returns:
///   - error.FileNotFound if directory doesn't exist
///   - error.OutOfMemory if allocation fails
pub fn writeTomlConfigFile(
    file_path: []const u8,
    config: *const TomlConfig,
) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    const buffered = std.io.bufferedWriter(file.writer());
    try writeTomlConfig(buffered.writer(), config);
    try buffered.flush();
}
