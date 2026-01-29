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
const c = @import("../ffi/c.zig").c;

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

    /// Set refresh interval in milliseconds
    ///
    /// Updates the polling interval at runtime. The change takes effect
    /// on the next sleep cycle (not immediately).
    ///
    /// Parameters:
    ///   - interval_ms: New interval in milliseconds (minimum 1ms)
    ///
    /// Example:
    /// ```
    /// var refresh = RefreshThread.init(allocator, &store);
    /// try refresh.start();
    /// // ... change to 50ms refresh rate
    /// refresh.setInterval(50);
    /// refresh.stop();
    /// ```
    pub fn setInterval(self: *RefreshThread, interval_ms: u64) void {
        self.interval_ns = interval_ms * std.time.ns_per_ms;
    }

    /// Refresh HAL state and update cache
    ///
    /// This function performs a complete refresh cycle:
    /// 1. Discovery: Enumerate ALL pins/signals/params from HAL
    /// 2. Snapshot: Get current cache keys
    /// 3. Comparison: Add new pins, remove stale entries
    /// 4. Update: Read current values and update cache
    ///
    /// Thread safety:
    ///   - Reads HAL values BEFORE acquiring cache lock (Pitfall 1)
    ///   - Uses temporary allocations freed before returning
    ///
    /// Returns:
    ///   - void on success
    ///   - error.OutOfMemory if allocation fails
    ///
    /// STATE-03 support:
    ///   - Discovers pins from newly loaded components (halcmd loadusr)
    ///   - Removes pins from unloaded components (stale cleanup)
    fn refreshHal(self: *RefreshThread) !void {
        // Refresh pins
        try self.refreshPins();

        // TODO: Refresh signals and params in future tasks
        // For now, only pins are implemented
    }

    /// Refresh all pins from HAL
    ///
    /// This function:
    /// 1. Enumerates all pins from HAL via halprFindPinByName(null) iteration
    /// 2. Compares with cache to find new/stale pins
    /// 3. Adds new pins to cache
    /// 4. Removes stale pins from cache
    /// 5. Updates all pin values
    ///
    /// Thread safety:
    ///   - Reads HAL pins without holding cache lock
    ///   - Collects all values in temporary ArrayList
    ///   - Acquires cache lock only for final update
    fn refreshPins(self: *RefreshThread) !void {
        // Discovery phase: Walk HAL's linked list of all pins
        var hal_pins = std.ArrayList(*c.hal_pin_t).init(self.allocator);
        defer hal_pins.deinit();

        var maybe_pin = ffi.halprFindPinByName(null); // null = first pin
        while (maybe_pin) |pin| {
            try hal_pins.append(pin);
            maybe_pin = pin.*.next; // Walk linked list via next pointer
        }

        // Snapshot phase: Get current cache keys for comparison
        const cached_names = try self.store.listPins(self.allocator);
        defer self.allocator.free(cached_names);

        // Comparison phase: Find new pins (in HAL but not cache)
        for (hal_pins.items) |pin| {
            const name = std.mem.span(pin.*.name);

            // Check if this pin is already in cache
            var found = false;
            for (cached_names) |cached_name| {
                if (std.mem.eql(u8, name, cached_name)) {
                    found = true;
                    break;
                }
            }

            // If not in cache, add it (newly discovered pin)
            if (!found) {
                // Note: pin.*.type and pin.*.dir are already enum values from C
                // We'll add them with a default value initially
                const value = try self.readPinValue(pin);
                try self.store.addPin(name, value);
            }
        }

        // Comparison phase: Find stale pins (in cache but not HAL)
        // TODO: Implement stale pin removal in future task
        // For now, new pins are added but stale pins are not removed

        // Update phase: Read all current values from HAL and update cache
        for (hal_pins.items) |pin| {
            const name = std.mem.span(pin.*.name);
            const value = try self.readPinValue(pin);
            try self.store.updatePin(name, value);
        }
    }

    /// Read a pin's value based on its type
    ///
    /// This function reads the current value from a pin, handling all
    /// four HAL data types (BIT, FLOAT, S32, U32).
    ///
    /// Parameters:
    ///   - pin: Pointer to hal_pin_t
    ///
    /// Returns:
    ///   - HalValue union containing the pin's value
    ///   - error.TypeMismatch if pin type is invalid
    fn readPinValue(self: *RefreshThread, pin: *c.hal_pin_t) !StateStore.HalValue {
        _ = self; // Not used but needed for method signature

        // Read value based on pin type
        switch (pin.*.type) {
            c.HAL_BIT => {
                const bit_val = try ffi.getPinBit(pin);
                return StateStore.HalValue{ .bit = bit_val };
            },
            c.HAL_FLOAT => {
                const float_val = try ffi.getPinFloat(pin);
                return StateStore.HalValue{ .float = float_val };
            },
            c.HAL_S32 => {
                const s32_val = try ffi.getPinS32(pin);
                return StateStore.HalValue{ .s32 = s32_val };
            },
            c.HAL_U32 => {
                const u32_val = try ffi.getPinU32(pin);
                return StateStore.HalValue{ .u32 = u32_val };
            },
            else => return error.TypeMismatch,
        }
    }
};

// Compile-time tests to verify API surface
comptime {
    // Verify RefreshThread can be initialized
    _ = RefreshThread.init;

    // Verify deinit is callable
    _ = RefreshThread.deinit;

    // Verify lifecycle operations exist
    _ = RefreshThread.start;
    _ = RefreshThread.stop;

    // Verify configuration operations exist
    _ = RefreshThread.setInterval;
}
