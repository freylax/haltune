const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const Model = @import("model.zig").Model;
const StateStore = @import("../state/cache.zig").StateStore;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;

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
    var store = try StateStore.init(allocator);
    defer store.deinit();

    // Initialize SubscriptionManager for pubsub notifications
    // This allows the TUI to receive updates when HAL values change
    var pubsub = try SubscriptionManager.init(allocator);
    defer pubsub.deinit();

    // Create Model with allocator, store, and pubsub
    // The Model holds all application state and implements vxfw.Widget
    const model = try allocator.create(Model);
    defer allocator.destroy(model);

    model.* = try Model.init(allocator, &store, &pubsub);

    // Stop RefreshThread before deinit (clean shutdown)
    // Ensure thread exits before we free resources
    if (model.refresh_thread) |*refresh| {
        defer refresh.stop();
    }

    // Initialize Vxfw application
    // Vxfw manages the event loop, terminal I/O, and rendering
    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    // Run the application with our Model widget
    // This blocks until the user quits (Ctrl+C)
    try app.run(model.widget(), .{});
}
