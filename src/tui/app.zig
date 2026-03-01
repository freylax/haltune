const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const Model = @import("model.zig").Model;
const StateStore = @import("../state/cache.zig").StateStore;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;
const RefreshThread = @import("../state/refresh.zig").RefreshThread;
const HalError = @import("../ffi/errors.zig").HalError;
const plugin_registry_mod = @import("../plugin/registry.zig");
const plugin_manager_mod = @import("../plugin/manager.zig");
const plugins_mod = @import("../plugins/plugins.zig");

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

    // Initialize plugin registry
    try plugin_registry_mod.initGlobalRegistry(allocator);
    defer plugin_registry_mod.deinitGlobalRegistry();

    // Register all available plugins
    try plugins_mod.registerAllPlugins(allocator);
    const registry = plugin_registry_mod.getGlobalRegistry();
    std.log.info("Registered {d} plugins", .{if (registry) |r| r.count() else 0});

    // Initialize plugin manager (backend will be set after Model creates it)
    var plugin_manager = if (registry) |r| plugin_manager_mod.PluginManager.init(allocator, r, null) else return error.PluginRegistryNotAvailable;
    plugin_manager_mod.setGlobalPluginManager(&plugin_manager);
    defer plugin_manager.deinit();

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

    // Create and start RefreshThread for HAL polling BEFORE initializing vaxis
    // This allows StateStore to be populated before the UI starts
    // Using c_allocator (like flow does) for both main and refresh threads
    const refresh_thread = try thread_safe_allocator.create(RefreshThread);
    refresh_thread.* = RefreshThread.init(thread_safe_allocator, &store);
    // Set redraw flag so refresh thread can trigger UI updates when StateStore is populated
    refresh_thread.setRedrawFlag(&model.redraw_flag);

    // Set remote backend if available
    if (model.remote_backend) |backend| {
        refresh_thread.setRemoteBackend(backend);
        plugin_manager.setBackend(backend);
        std.log.info("Using remote HAL for refresh thread and plugins", .{});
    }

    // Start the refresh thread
    _ = try refresh_thread.start();

    // Give refresh thread time to populate StateStore before initializing UI
    // This ensures the tree is built with actual data, not empty
    std.log.info("Waiting for refresh thread to populate StateStore...", .{});

    // Wait up to 2 seconds for StateStore to be populated
    var wait_count: u32 = 0;
    while (wait_count < 20) : (wait_count += 1) {
        std.Thread.sleep(100 * std.time.ns_per_ms);
        if (refresh_thread.populated.load(.acquire)) {
            std.log.info("StateStore populated after {d}ms", .{wait_count * 100});
            break;
        }
    }
    if (!refresh_thread.populated.load(.acquire)) {
        std.log.warn("StateStore not populated after 2s, continuing anyway", .{});
    }

    // Rebuild tree now that StateStore has been populated
    try model.tree_view.buildTree();
    std.log.info("Tree rebuilt with {d} components", .{model.tree_view.root.items.len});

    // NOW initialize Vxfw application (requires /dev/tty)
    // Vxfw manages the event loop, terminal I/O, and rendering
    var app = vxfw.App.init(allocator) catch |err| {
        // Clean up refresh thread if app init fails
        std.log.info("Stopping RefreshThread...", .{});
        refresh_thread.stop();
        std.log.info("RefreshThread stopped", .{});
        thread_safe_allocator.destroy(refresh_thread);
        return err;
    };
    defer {
        // Clean up refresh thread and app when function exits (normal case)
        std.log.info("Stopping RefreshThread...", .{});
        refresh_thread.stop();
        std.log.info("RefreshThread stopped", .{});
        thread_safe_allocator.destroy(refresh_thread);
        app.deinit();
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
        std.debug.print("TEST MODE: Setting default terminal size 80x24\n", .{});
        // In test mode, set a default terminal size to prevent vaxis division by zero
        const os = std.os.linux;
        const winsize = extern struct { ws_row: u16, ws_col: u16, ws_xpixel: u16, ws_ypixel: u16 };
        var ws: winsize = .{ .ws_row = 24, .ws_col = 80, .ws_xpixel = 0, .ws_ypixel = 0 };
        const fd = std.posix.STDOUT_FILENO;
        const TIOCSWINSZ = 0x5414; // Set window size
        _ = os.ioctl(fd, TIOCSWINSZ, @intFromPtr(&ws));
    }

    // Run the application with our Model widget
    // This blocks until the user quits (Ctrl+C)
    try app.run(model.widget(), .{});
}
