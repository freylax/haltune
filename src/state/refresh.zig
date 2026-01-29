// Refresh thread for HAL state polling
//
// This module provides RefreshThread, a dedicated thread that polls HAL at
// configurable intervals (default 100ms), enumerates ALL pins/signals/params
// from HAL (including newly created ones), removes stale entries for unloaded
// components, and updates the state cache.
//
// Design principles:
// - Use atomic.Value(bool) for thread-safe running flag with .acquire/.release
// - Never call HAL functions while holding cache lock (prevents deadlock)
// - Support dynamic component load/unload via full HAL enumeration each cycle
// - Configurable refresh interval at runtime

const std = @import("std");
const StateStore = @import("cache.zig").StateStore;
const ffi = @import("../ffi/safe.zig");

/// Refresh thread manages HAL polling and cache updates
///
/// This struct maintains a background thread that periodically polls HAL
/// for pin/signal/parameter values, updates the state cache, and handles
/// dynamic changes (components loaded/unloaded via halcmd).
///
/// Thread lifecycle:
/// 1. Create RefreshThread with init()
/// 2. Start polling with start()
/// 3. Change interval with setInterval() (optional)
/// 4. Stop thread with stop()
/// 5. Clean up with deinit()
///
/// Thread safety:
/// - running flag uses .acquire/.release memory ordering for visibility
/// - Cache updates follow RESEARCH.md Pitfall 1: read HAL first, then acquire lock
pub const RefreshThread = struct {
    /// StateStore to update with HAL values
    store: *StateStore,

    /// Atomic flag for thread lifecycle (true = running, false = shutdown)
    /// Uses .release on store, .acquire on load for cross-thread visibility
    running: std.atomic.Value(bool),

    /// Thread handle for join on shutdown
    thread: std.Thread,

    /// Refresh interval in nanoseconds (default 100ms)
    interval_ns: u64,

    /// Memory allocator for temporary allocations during refresh
    allocator: std.mem.Allocator,

    /// Initialize a new RefreshThread
    ///
    /// Creates a refresh thread instance with default 100ms interval.
    /// The thread is not started until start() is called.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for refresh operations
    ///   - store: StateStore to update with HAL values
    ///
    /// Returns:
    ///   - Initialized RefreshThread (not yet started)
    ///
    /// Example:
    /// ```
    /// var store = StateStore.init(allocator);
    /// defer store.deinit();
    ///
    /// var refresh = RefreshThread.init(allocator, &store);
    /// defer refresh.deinit();
    ///
    /// try refresh.start();
    /// // ... thread is now polling HAL
    /// refresh.stop();
    /// ```
    pub fn init(allocator: std.mem.Allocator, store: *StateStore) RefreshThread {
        return .{
            .store = store,
            .running = std.atomic.Value(bool).init(true),
            .thread = undefined,
            .interval_ns = 100 * std.time.ns_per_ms, // Default 100ms
            .allocator = allocator,
        };
    }

    /// Clean up RefreshThread resources
    ///
    /// Releases resources. The thread must be stopped before calling deinit().
    ///
    /// IMPORTANT: Call stop() before deinit() to ensure clean shutdown.
    ///
    /// Example:
    /// ```
    /// var refresh = RefreshThread.init(allocator, &store);
    /// try refresh.start();
    /// // ... use refresh thread
    /// refresh.stop();  // Wait for thread exit
    /// refresh.deinit(); // Clean up resources
    /// ```
    pub fn deinit(self: *RefreshThread) void {
        // Note: running flag is cleaned up by atomic.Value deinit
        _ = self;
    }

    /// Start the refresh thread
    ///
    /// Spawns a background thread that polls HAL at the configured interval.
    /// The thread runs until stop() is called.
    ///
    /// Returns:
    ///   - void on success
    ///   - error.ThreadCreationFailed if thread spawn fails
    ///
    /// Thread safety:
    ///   - Must not be called if thread is already running
    ///
    /// Example:
    /// ```
    /// var refresh = RefreshThread.init(allocator, &store);
    /// try refresh.start();
    /// // ... thread is now polling HAL
    /// refresh.stop();
    /// ```
    pub fn start(self: *RefreshThread) !void {
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    /// Main refresh loop (runs in background thread)
    ///
    /// This function runs in a dedicated thread, polling HAL at the
    /// configured interval and updating the state cache.
    ///
    /// Thread safety:
    ///   - Uses .acquire memory ordering to see latest running flag value
    ///   - Never holds cache lock while calling HAL functions (Pitfall 1)
    ///
    /// Example:
    /// ```
    /// // Called automatically by start() - do not call directly
    /// ```
    fn run(self: *RefreshThread) void {
        while (self.running.load(.acquire)) {
            // Refresh HAL state (may fail without crashing)
            self.refreshHal() catch |err| {
                std.log.err("Refresh error: {}", .{err});
            };

            // Sleep until next interval
            std.Thread.sleep(self.interval_ns);
        }
    }

    /// Stop the refresh thread
    ///
    /// Signals the background thread to exit and waits for it to finish.
    /// Uses .release memory ordering to ensure the running flag is visible
    /// to the background thread.
    ///
    /// IMPORTANT: This blocks until the thread exits. May take up to one
    /// refresh interval (default 100ms) for the thread to see the signal.
    ///
    /// Thread safety:
    ///   - Uses .release memory ordering for visibility
    ///   - Joins thread to ensure clean shutdown
    ///
    /// Example:
    /// ```
    /// var refresh = RefreshThread.init(allocator, &store);
    /// try refresh.start();
    /// // ... use refresh thread
    /// refresh.stop();  // Waits for thread exit
    /// ```
    pub fn stop(self: *RefreshThread) void {
        // Signal thread to stop (using .release for visibility)
        self.running.store(false, .release);

        // Wait for thread to exit
        self.thread.join();
    }
};

// Compile-time tests to verify API surface
comptime {
    // Verify RefreshThread can be initialized
    _ = RefreshThread.init;

    // Verify deinit is callable
    _ = RefreshThread.deinit;
}
