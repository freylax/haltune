// Import TUI application
const tui_app = @import("tui/app.zig");
const std = @import("std");
const logging = @import("log.zig");
const toml_config = @import("config/toml_config.zig");

/// std.log configuration - redirects logs to file or disables them
pub const std_options = std.Options{
    .log_level = std.log.Level.info,
    .logFn = logging.logWrite,
};

/// Command-line configuration for haltune
pub const Config = struct {
    /// Test mode flag (bypasses terminal size check)
    test_mode: bool = false,

    /// .hal configuration files to parse for origin tracking
    hal_files: std.ArrayList([]const u8),

    /// .ini configuration files to parse for origin tracking
    ini_files: std.ArrayList([]const u8),

    /// Log file path for debug output (null = stderr)
    log_file_path: ?[]const u8 = null,

    /// Path to configuration file (if loaded from TOML)
    config_file_path: ?[]const u8 = null,

    /// Enabled plugins from config
    enabled_plugins: ?[][]const u8 = null,

    /// Remote HAL configuration
    remote: RemoteConfig,

    /// Allocator used for hal_files and ini_files
    allocator: std.mem.Allocator,

    /// Remote HAL server configuration
    pub const RemoteConfig = struct {
        /// Whether to use remote HAL (false = use local HAL)
        enabled: bool = false,

        /// Remote HAL server host
        host: ?[]const u8 = null,

        /// Remote HAL server port
        port: u16 = 8765,

        /// Owned host string (for cleanup)
        host_owner: ?[]const u8 = null,
    };

    /// Initialize Config with allocator
    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .hal_files = std.ArrayList([]const u8){},
            .ini_files = std.ArrayList([]const u8){},
            .allocator = allocator,
            .remote = .{},
        };
    }

    /// Clean up Config resources
    pub fn deinit(self: *Config) void {
        for (self.hal_files.items) |f| {
            self.allocator.free(f);
        }
        self.hal_files.deinit(self.allocator);

        for (self.ini_files.items) |f| {
            self.allocator.free(f);
        }
        self.ini_files.deinit(self.allocator);

        if (self.log_file_path) |p| {
            self.allocator.free(p);
        }

        if (self.config_file_path) |p| {
            self.allocator.free(p);
        }

        // Free enabled plugins list
        if (self.enabled_plugins) |plugins| {
            for (plugins) |p| {
                self.allocator.free(p);
            }
            self.allocator.free(plugins);
        }

        // Free remote host
        if (self.remote.host_owner) |h| {
            self.allocator.free(h);
        }
    }

    /// Merge TOML configuration into this config
    /// TOML values don't override command-line values
    pub fn mergeToml(self: *Config, toml: toml_config.TomlConfig) !void {
        // Merge hal_files
        if (toml.files.hal_files) |files| {
            for (files) |f| {
                // Check if already in list (from command line)
                const already_exists = for (self.hal_files.items) |existing| {
                    if (std.mem.eql(u8, existing, f)) break true;
                } else false;

                if (!already_exists) {
                    try self.hal_files.append(self.allocator, try self.allocator.dupe(u8, f));
                }
            }
        }

        // Merge ini_files
        if (toml.files.ini_files) |files| {
            for (files) |f| {
                // Check if already in list (from command line)
                const already_exists = for (self.ini_files.items) |existing| {
                    if (std.mem.eql(u8, existing, f)) break true;
                } else false;

                if (!already_exists) {
                    try self.ini_files.append(self.allocator, try self.allocator.dupe(u8, f));
                }
            }
        }

        // Log file path only if not already set by command line
        if (self.log_file_path == null and toml.logging.file != null) {
            if (toml.logging.file) |f| {
                self.log_file_path = try self.allocator.dupe(u8, f);
            }
        }

        // Merge enabled plugins
        if (self.enabled_plugins == null and toml.plugins.enabled != null) {
            if (toml.plugins.enabled) |plugins| {
                const copied = try self.allocator.alloc([]const u8, plugins.len);
                for (plugins, 0..) |p, i| {
                    copied[i] = try self.allocator.dupe(u8, p);
                }
                self.enabled_plugins = copied;
            }
        }

        // Merge remote configuration
        if (toml.remote.enabled) {
            self.remote.enabled = toml.remote.enabled;
        }
        if (toml.remote.host) |h| {
            // Free previous host if owned
            if (self.remote.host_owner) |old| {
                self.allocator.free(old);
            }
            self.remote.host_owner = try self.allocator.dupe(u8, h);
            self.remote.host = self.remote.host_owner;
        }
        // port is already a u16 with default value, just assign it
        self.remote.port = toml.remote.port;
    }
};

/// Parse command-line arguments
///
/// Supported arguments:
///   -c <file.toml> : Load configuration from TOML file
///   -f <file.hal>  : Add .hal file for origin tracking
///   -i <file.ini>  : Add .ini file for origin tracking
///   --log-file <path> : Write debug logs to file instead of stderr
///   --test-mode, -t : Enable test mode (bypass terminal check)
///   -h, --help     : Show help message
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Config {
    var config = Config.init(allocator);

    // Track if we should look for default config file
    var try_default_config = true;
    var explicit_config: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--test-mode") or std.mem.eql(u8, arg, "-t")) {
            config.test_mode = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--config")) {
            // Next arg is the config file path
            i += 1;
            if (i >= args.len) {
                std.debug.print("ERROR: -c/--config requires a file path argument\n\n", .{});
                printHelp();
                std.process.exit(1);
            }
            explicit_config = args[i];
            try_default_config = false;
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            // Handle --config=path format
            explicit_config = arg[9..];
            try_default_config = false;
        } else if (std.mem.eql(u8, arg, "--log-file")) {
            // Next arg is the log file path
            i += 1;
            if (i >= args.len) {
                std.debug.print("ERROR: --log-file requires a file path argument\n\n", .{});
                printHelp();
                std.process.exit(1);
            }
            const file_path = args[i];
            config.log_file_path = try allocator.dupe(u8, file_path);
        } else if (std.mem.startsWith(u8, arg, "--log-file=")) {
            // Handle --log-file=path format
            const file_path = arg[11..];
            config.log_file_path = try allocator.dupe(u8, file_path);
        } else if (std.mem.eql(u8, arg, "-f")) {
            // Next arg is the file path
            i += 1;
            if (i >= args.len) {
                std.debug.print("ERROR: -f requires a file path argument\n\n", .{});
                printHelp();
                std.process.exit(1);
            }
            const file_path = args[i];
            try config.hal_files.append(allocator, try allocator.dupe(u8, file_path));
        } else if (std.mem.startsWith(u8, arg, "-f=")) {
            // Handle -f=path format
            const file_path = arg[3..];
            try config.hal_files.append(allocator, try allocator.dupe(u8, file_path));
        } else if (std.mem.eql(u8, arg, "-i")) {
            // Next arg is the .ini file path
            i += 1;
            if (i >= args.len) {
                std.debug.print("ERROR: -i requires a file path argument\n\n", .{});
                printHelp();
                std.process.exit(1);
            }
            const file_path = args[i];
            try config.ini_files.append(allocator, try allocator.dupe(u8, file_path));
        } else if (std.mem.startsWith(u8, arg, "-i=")) {
            // Handle -i=path format
            const file_path = arg[3..];
            try config.ini_files.append(allocator, try allocator.dupe(u8, file_path));
        } else {
            std.debug.print("ERROR: Unknown argument '{s}'\n\n", .{arg});
            printHelp();
            std.process.exit(1);
        }
    }

    // Load TOML config if specified
    if (explicit_config) |path| {
        std.log.info("Loading configuration from: {s}", .{path});
        var toml_cfg = try toml_config.loadConfig(allocator, path);
        defer toml_config.deinit(&toml_cfg, allocator);
        config.config_file_path = try allocator.dupe(u8, path);
        try config.mergeToml(toml_cfg);
    } else if (try_default_config) {
        // Try to load default config file
        if (toml_config.loadConfig(allocator, null)) |toml_cfg| {
            var cfg = toml_cfg;
            defer toml_config.deinit(&cfg, allocator);
            std.log.info("Loaded configuration from haltune.toml", .{});
            config.config_file_path = try allocator.dupe(u8, "haltune.toml");
            try config.mergeToml(cfg);
        } else |err| {
            if (err != error.FileNotFound) {
                std.log.warn("Failed to load config file: {}", .{err});
            }
            // FileNotFound is expected - no config file
        }
    }

    return config;
}

/// Print help message
fn printHelp() void {
    std.debug.print(
        \\haltune - LinuxCNC HAL configuration browser and editor
        \\
        \\Usage:
        \\  haltune [options]
        \\
        \\Options:
        \\  -c, --config <file.toml>  Load configuration from TOML file
        \\                           (default: looks for haltune.toml)
        \\  -f <file.hal>             Load .hal file for origin tracking
        \\                           Can be specified multiple times
        \\  -i <file.ini>             Load .ini file for origin tracking
        \\                           Can be specified multiple times
        \\  --log-file <path>         Write debug logs to file instead of stderr
        \\  --test-mode, -t           Enable test mode (bypass terminal check)
        \\  -h, --help                Show this help message
        \\
        \\Configuration file (haltune.toml):
        \\  [files]
        \\    hal_files = ["custom.hal", "core_stepper.hal"]
        \\    ini_files = ["myconfig.ini"]
        \\  [logging]
        \\    file = "debug.log"
        \\
        \\Key bindings (in TUI):
        \\  Ctrl+Q         Quit application
        \\  Ctrl+T         Toggle tree/table view
        \\  Enter           Expand/collapse or edit value
        \\  Space           Toggle visibility
        \\  Esc             Clear search/filter
        \\  /               Search
        \\  n               Create new signal (tree view)
        \\  s               Save configuration (tree view)
        \\  t               Cycle type filter (table view)
        \\  c               Component filter (table view)
        \\  +/-             Expand/collapse all
        \\  Up/Down/Page     Navigate
        \\
        \\Examples:
        \\  haltune
        \\  haltune -c myconfig.toml
        \\  haltune -f custom.hal
        \\  haltune -f core_stepper.hal -f custom.hal -i myconfig.ini
        \\  haltune --log-file debug.log -f test.hal
        \\  haltune --test-mode -f test.hal
        \\
    , .{});
}

pub fn main() !void {
    // Parse command-line arguments
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse arguments into config
    var config = try parseArgs(allocator, args[1..]);
    defer config.deinit();

    // Initialize logging
    if (config.log_file_path) |path| {
        logging.init(path) catch |err| {
            std.debug.print("ERROR: Failed to open log file '{s}': {}\n", .{ path, err });
            std.process.exit(1);
        };
    } else {
        // Disable logging to avoid interfering with TUI
        logging.init(null) catch {};
    }
    defer logging.deinit();

    // Run the TUI application with config
    // This initializes HAL, starts the refresh thread, and runs the Vaxis TUI
    try tui_app.main(config);
}
