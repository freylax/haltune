const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const Model = @import("model.zig").Model;
const StateStore = @import("../state/cache.zig").StateStore;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;
const RefreshThread = @import("../state/refresh.zig").RefreshThread;
const HalError = @import("../ffi/errors.zig").HalError;

/// Configuration for haltune from root.zig
pub const Config = @import("../root.zig").Config;

/// Main TUI application entry point
///
/// This function:
/// 1. Initializes the c allocator (like flow does - avoids page_allocator corruption)
/// 2. Creates StateStore for HAL component data caching
/// 3. Creates SubscriptionManager for pubsub notifications
/// 4. Initializes Model with application state
/// 5. Parses configuration files for origin tracking
/// 6. Starts Vxfw application with two-panel layout
///
/// User controls:
/// - Ctrl+Q: Quit application
/// - --test-mode: Bypass terminal size check for automated testing
/// - -f file.hal : Load .hal file for origin tracking
/// - -i file.ini : Load .ini file for origin tracking
pub fn main(config: Config) !void {
    // Use c_allocator throughout (like flow does)
    // Using page_allocator caused memory corruption with vaxis + refresh thread
    const allocator = std.heap.c_allocator;
    const thread_safe_allocator = std.heap.c_allocator;

    // Initialize StateStore for HAL component caching
    // This provides thread-safe access to pins, signals, and parameters
    // Using c_allocator (like flow does) avoids memory corruption with vaxis
    var store = StateStore.init(thread_safe_allocator);
    defer store.deinit();

    // Initialize SubscriptionManager for pubsub notifications
    // This allows the TUI to receive updates when HAL values change
    // MUST use page_allocator since it's accessed by refresh thread
    var pubsub = SubscriptionManager.init(thread_safe_allocator);
    defer pubsub.deinit();

    // Parse configuration files if provided
    // This builds origin tracking data before initializing Model
    if (config.hal_files.items.len > 0 or config.ini_files.items.len > 0) {
        std.log.info("Loading configuration files:", .{});
        for (config.hal_files.items) |file| {
            std.log.info("  .hal: {s}", .{file});
        }
        for (config.ini_files.items) |file| {
            std.log.info("  .ini: {s}", .{file});
        }
        // TODO: Parse config files and populate origin tracker
        // This will be implemented in next phase
    }

    // Create Model with allocator, store, and pubsub
    // The Model holds all application state and implements vxfw.Widget
    const model = try allocator.create(Model);
    errdefer allocator.destroy(model);

    // Initialize Model, catching HAL-specific errors
    model.* = Model.init(allocator, &store, &pubsub, config) catch |err| {
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
        // For other errors (like InitFailed), print helpful message and exit
        if (err == HalError.InitFailed) {
            std.debug.print(
                \\ERROR: Failed to initialize HAL component
                \\
                \\This usually means a component with the name 'haltune' already exists.
                \\
                \\To see existing components, run:
                \\  halcmd list comp
                \\
                \\To remove stuck components, run:
                \\  halcmd del comp haltune
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

    // Initialize Vxfw application FIRST
    // Vxfw manages the event loop, terminal I/O, and rendering
    // Must initialize before starting refresh thread to avoid terminal access conflicts
    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    // Create and start RefreshThread for HAL polling AFTER vaxis is ready
    // Using c_allocator (like flow does) for both main and refresh threads
    const refresh_thread = try thread_safe_allocator.create(RefreshThread);
    refresh_thread.* = RefreshThread.init(thread_safe_allocator, &store);
    // Set redraw flag so refresh thread can trigger UI updates when StateStore is populated
    refresh_thread.setRedrawFlag(&model.redraw_flag);
    _ = try refresh_thread.start();

    // Give refresh thread time to populate StateStore before first draw
    // This ensures the tree is built with actual data, not empty
    std.log.info("Waiting for refresh thread to populate StateStore...", .{});
    std.Thread.sleep(200 * std.time.ns_per_ms); // 200ms delay
    std.log.info("Refresh thread started, continuing to TUI", .{});

    defer {
        std.log.info("Stopping RefreshThread...", .{});
        refresh_thread.stop();
        std.log.info("RefreshThread stopped", .{});
        thread_safe_allocator.destroy(refresh_thread);
    }

    // Validate terminal size before running the TUI
    // vaxis will panic with division by zero if screen dimensions are 0
    // This can happen when running via script/ssh without proper TTY allocation
    // In test mode, skip this check and use default dimensions
    if (!config.test_mode) {
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
                \\For automated testing, use: --test-mode
                \\
            , .{});
            std.process.exit(1);
        }
    } else {
        std.debug.print("TEST MODE: Terminal size check bypassed\n", .{});
    }

    // Run the application with our Model widget
    // This blocks until the user quits (Ctrl+C)
    try app.run(model.widget(), .{});
}
