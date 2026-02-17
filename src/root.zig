// Import TUI application
const tui_app = @import("tui/app.zig");
const std = @import("std");
const logging = @import("log.zig");

/// std.log configuration - redirects logs to file or disables them
pub const std_options = struct {
    pub const log_level = std.log.Level.info;

    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        logging.logWrite(level, scope, format, args);
    }
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

    /// Allocator used for hal_files and ini_files
    allocator: std.mem.Allocator,

    /// Initialize Config with allocator
    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .hal_files = std.ArrayList([]const u8){},
            .ini_files = std.ArrayList([]const u8){},
            .allocator = allocator,
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
    }
};

/// Parse command-line arguments
///
/// Supported arguments:
///   -f <file.hal>  : Add .hal file for origin tracking
///   -i <file.ini>  : Add .ini file for origin tracking
///   --log-file <path> : Write debug logs to file instead of stderr
///   --test-mode, -t : Enable test mode (bypass terminal check)
///   -h, --help     : Show help message
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Config {
    var config = Config.init(allocator);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--test-mode") or std.mem.eql(u8, arg, "-t")) {
            config.test_mode = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            std.process.exit(0);
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
        \\  -f <file.hal>   Load .hal file for origin tracking
        \\                   Can be specified multiple times
        \\  -i <file.ini>   Load .ini file for origin tracking
        \\                   Can be specified multiple times
        \\  --log-file <path>  Write debug logs to file instead of stderr
        \\  --test-mode, -t  Enable test mode (bypass terminal size check)
        \\  -h, --help       Show this help message
        \\
        \\Examples:
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
