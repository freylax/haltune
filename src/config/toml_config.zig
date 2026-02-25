// TOML configuration file parser for haltune
//
// This module parses haltune.toml configuration files that specify:
// - HAL files to load for origin tracking
// - INI files to load for origin tracking
// - Log file path
// - Plugin configurations (for future use)
// - Remote HAL server configuration
//
// Example haltune.toml:
//   [files]
//   hal_files = ["custom.hal", "core_stepper.hal"]
//   ini_files = ["myconfig.ini"]
//
//   [logging]
//   file = "debug.log"
//
//   [plugins]
//   enabled = ["plugin1", "plugin2"]
//
//   [remote]
//   enabled = true
//   host = "192.168.2.118"
//   port = 8765

const std = @import("std");
const toml = @import("toml");

/// Configuration structure parsed from haltune.toml
pub const TomlConfig = struct {
    /// File configuration section
    files: Files,

    /// Logging configuration section
    logging: Logging,

    /// Plugin configuration section (reserved for future use)
    plugins: Plugins,

    /// Remote HAL server configuration
    remote: Remote,

    /// File configuration
    pub const Files = struct {
        /// List of .hal files to load
        hal_files: ?[][]const u8 = null,

        /// List of .ini files to load
        ini_files: ?[][]const u8 = null,
    };

    /// Logging configuration
    pub const Logging = struct {
        /// Log file path (null = stderr)
        file: ?[]const u8 = null,
    };

    /// Plugin configuration
    pub const Plugins = struct {
        /// List of enabled plugins
        enabled: ?[][]const u8 = null,

        /// Plugin-specific settings (as key-value strings)
        settings: ?[]PluginSetting = null,

        /// Individual plugin setting
        pub const PluginSetting = struct {
            /// Plugin name
            name: []const u8,

            /// Setting value
            value: []const u8,
        };
    };

    /// Remote HAL server configuration
    pub const Remote = struct {
        /// Whether to use remote HAL (false = use local HAL)
        enabled: bool = false,

        /// Remote HAL server host
        host: ?[]const u8 = null,

        /// Remote HAL server port
        port: u16 = 8765,
    };
};

/// Parse a TOML configuration file
///
/// Parameters:
///   - allocator: Memory allocator for all returned data
///   - file_path: Path to .toml file to parse
///
/// Returns:
///   - TomlConfig with all configuration
///   - error.FileNotFound if file doesn't exist
///   - error.OutOfMemory if allocation fails
///   - error.InvalidToml if TOML parsing fails
///
/// Note: The returned strings are allocated by the provided allocator
/// and should be freed by calling deinit().
pub fn parseTomlConfig(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !TomlConfig {
    // Define the TOML structure for parsing
    const TomlRoot = struct {
        files: struct {
            hal_files: ?[]const []const u8 = null,
            ini_files: ?[]const []const u8 = null,
        } = .{},

        logging: struct {
            file: ?[]const u8 = null,
        } = .{},

        plugins: struct {
            enabled: ?[]const []const u8 = null,
        } = .{},

        remote: struct {
            enabled: ?bool = null,
            host: ?[]const u8 = null,
            port: ?u16 = null,
        } = .{},
    };

    var parser = toml.Parser(TomlRoot).init(allocator);
    defer parser.deinit();

    const result = try parser.parseFile(file_path);
    defer result.deinit();

    const parsed = result.value;

    // Convert parsed TOML to our TomlConfig structure
    // We need to copy strings since the TOML parser's arena will be freed
    const config = TomlConfig{
        .files = .{
            .hal_files = if (parsed.files.hal_files) |f| try copyStringSlice(allocator, f) else null,
            .ini_files = if (parsed.files.ini_files) |f| try copyStringSlice(allocator, f) else null,
        },
        .logging = .{
            .file = if (parsed.logging.file) |f| try allocator.dupe(u8, f) else null,
        },
        .plugins = .{
            .enabled = if (parsed.plugins.enabled) |p| try copyStringSlice(allocator, p) else null,
            .settings = null,
        },
        .remote = .{
            .enabled = parsed.remote.enabled orelse false,
            .host = if (parsed.remote.host) |h| try allocator.dupe(u8, h) else null,
            .port = parsed.remote.port orelse 8765,
        },
    };

    return config;
}

/// Copy a slice of strings to a new allocator
fn copyStringSlice(allocator: std.mem.Allocator, source: []const []const u8) ![][]const u8 {
    const copied = try allocator.alloc([]const u8, source.len);
    for (source, 0..) |s, i| {
        copied[i] = try allocator.dupe(u8, s);
    }
    return copied;
}

/// Find and load configuration file
///
/// Search order:
/// 1. If config_path is provided, use it
/// 2. Look for haltune.toml in current directory
/// 3. Look for .haltune.toml in current directory
///
/// Returns:
///   - TomlConfig if file found
///   - error.FileNotFound if no config file exists
pub fn loadConfig(
    allocator: std.mem.Allocator,
    config_path: ?[]const u8,
) !TomlConfig {
    const path = config_path orelse "haltune.toml";

    // Try the specified path
    if (std.fs.cwd().openFile(path, .{})) |file| {
        file.close();
        return parseTomlConfig(allocator, path);
    } else |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    }

    // Try .haltune.toml if no explicit path
    if (config_path == null) {
        if (std.fs.cwd().openFile(".haltune.toml", .{})) |file| {
            file.close();
            return parseTomlConfig(allocator, ".haltune.toml");
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        }
    }

    return error.FileNotFound;
}

/// Deinitialize and free all resources
pub fn deinit(self: *TomlConfig, allocator: std.mem.Allocator) void {
    // Free hal_files
    if (self.files.hal_files) |files| {
        for (files) |f| {
            allocator.free(f);
        }
        allocator.free(files);
    }

    // Free ini_files
    if (self.files.ini_files) |files| {
        for (files) |f| {
            allocator.free(f);
        }
        allocator.free(files);
    }

    // Free log file path
    if (self.logging.file) |f| {
        allocator.free(f);
    }

    // Free plugin names
    if (self.plugins.enabled) |plugins| {
        for (plugins) |p| {
            allocator.free(p);
        }
        allocator.free(plugins);
    }

    // Free plugin settings
    if (self.plugins.settings) |settings| {
        for (settings) |s| {
            allocator.free(s.name);
            allocator.free(s.value);
        }
        allocator.free(settings);
    }

    // Free remote host
    if (self.remote.host) |h| {
        allocator.free(h);
    }

    self.* = undefined;
}

/// Generate a default configuration file
///
/// This can be used to create a template config file
pub fn generateDefaultConfig(allocator: std.mem.Allocator, writer: anytype) !void {
    _ = allocator;
    try writer.writeAll(
        \\# haltune configuration file
        \\
        \\[files]
        \\# HAL files to load for origin tracking
        \\# hal_files = ["custom.hal", "core_stepper.hal"]
        \\
        \\# INI files to load for origin tracking
        \\# ini_files = ["myconfig.ini"]
        \\
        \\[logging]
        \\# Log file path (comment out to log to stderr)
        \\# file = "debug.log"
        \\
        \\[plugins]
        \\# Enabled plugins
        \\# enabled = ["plugin1", "plugin2"]
        \\
        \\[remote]
        \\# Remote HAL server configuration
        \\# Set enabled = true to connect to HAL bridge server instead of local HAL
        \\# enabled = false
        \\# host = "192.168.2.118"
        \\# port = 8765
        \\
    );
}
