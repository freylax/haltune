const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const Model = @import("model.zig").Model;
const StateStore = @import("../state/cache.zig").StateStore;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;
const HalError = @import("../ffi/errors.zig").HalError;

/// Main TUI application entry point
///
/// This function:
/// 1. Initializes the GPA allocator for memory management
/// 2. Creates StateStore for HAL component data caching
/// 3. Creates SubscriptionManager for pubsub notifications
/// 4. Initializes Model with application state
/// 5. Starts Vxfw application with two-panel layout
///
/// Note: RefreshThread is NOT started here - will be added in plan 03-03
/// when connecting real HAL data to the TUI
///
/// User controls:
/// - Ctrl+C: Quit application
pub fn main() !void {
    // Initialize GPA allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        // Check for memory leaks on shutdown
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Initialize StateStore for HAL component caching
    // This provides thread-safe access to pins, signals, and parameters
    var store = StateStore.init(allocator);
    defer store.deinit();

    // Initialize SubscriptionManager for pubsub notifications
    // This allows the TUI to receive updates when HAL values change
    var pubsub = SubscriptionManager.init(allocator);
    defer pubsub.deinit();

    // Create Model with allocator, store, and pubsub
    // The Model holds all application state and implements vxfw.Widget
    const model = try allocator.create(Model);

    // Initialize Model, catching HAL-specific errors
    model.* = Model.init(allocator, &store, &pubsub) catch |err| {
        // Handle HAL not available error with helpful message
        if (err == HalError.HalNotAvailable) {
            std.debug.print(
                \\ERROR: HAL is not available
                \\
                \\haltune requires LinuxCNC to be running to access the HAL.
                \\
                \\Please start LinuxCNC first:
                \\  linuxcnc /path/to/your/config.ini
                \\
                \\Then run haltune again.
                \\
            , .{});
            std.process.exit(1);
        }
        // For other errors, propagate normally
        return err;
    };
    defer {
        // Clean up Model resources (tree_view, data_table, signal_dialog, HAL)
        model.deinit();
        // Free the Model allocation itself
        allocator.destroy(model);
    }

    // Initialize Vxfw application
    // Vxfw manages the event loop, terminal I/O, and rendering
    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    // Validate terminal size before running the TUI
    // vaxis will panic with division by zero if screen dimensions are 0
    // This can happen when running via script/ssh without proper TTY allocation
    {
        const os = std.os.linux;
        const winsize = extern struct { ws_row: u16, ws_col: u16, ws_xpixel: u16, ws_ypixel: u16 };
        var ws: winsize = undefined;
        const fd = std.posix.STDOUT_FILENO;
        const TIOCGWINSZ = 0x5413;
        const rc = os.ioctl(fd, TIOCGWINSZ, @intFromPtr(&ws));
        if (rc != 0 or ws.ws_col == 0 or ws.ws_row == 0) {
            std.debug.print(
                \\ERROR: Terminal size unavailable or too small
                \\
                \\haltune requires a proper terminal with at least 1x1 characters.
                \\
                \\If running via SSH, make sure you're using an interactive session
                \\with a TTY allocated (not piping input or using 'script' command).
                \\
                \\Direct console access: ssh pib, then run ./zig-out/bin/haltune
                \\
            , .{});
            std.process.exit(1);
        }
    }

    // Run the application with our Model widget
    // This blocks until the user quits (Ctrl+C)
    try app.run(model.widget(), .{});
}
