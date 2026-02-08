// Refresh thread for HAL state polling
//
// This module provides RefreshThread, a dedicated thread that polls HAL at
// configurable intervals (default 100ms), enumerates ALL pins/signals/params
// from HAL (including newly created ones), removes stale entries for unloaded
// components, and updates the state cache.
//
// Implementation:
// - refreshPins(): Enumerates and updates HAL pins
// - refreshSignals(): Enumerates and updates HAL signals
// - refreshParams(): Enumerates and updates HAL parameters
//
// Design principles:
// - Use atomic.Value(bool) for thread-safe running flag with .acquire/.release
// - Never call HAL functions while holding cache lock (prevents deadlock)
// - Support dynamic component load/unload via full HAL enumeration each cycle
// - Configurable refresh interval at runtime

const std = @import("std");
const StateStore = @import("cache.zig").StateStore;
const HalValue = @import("cache.zig").HalValue;
const ffi = @import("../ffi/safe.zig");
const discovery = @import("../ffi/safe_discovery.zig");
const c = @import("../ffi/c.zig").c;
const hal_pin_t = @import("../ffi/types.zig").hal_pin_t;
const hal_sig_t = @import("../ffi/types.zig").hal_sig_t;
const hal_param_t = @import("../ffi/types.zig").hal_param_t;

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
    /// Uses page_allocator which is thread-safe (mmap-based)
    allocator: std.mem.Allocator,

    /// Initialize a new RefreshThread
    ///
    /// Creates a refresh thread instance with default 100ms interval.
    /// The thread is not started until start() is called.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for refresh operations (used to create arena)
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
        _ = allocator;
        // Use page_allocator directly - it's thread-safe (mmap-based)
        // Don't use ArenaAllocator as it may have issues in multithreaded context
        return .{
            .store = store,
            .running = std.atomic.Value(bool).init(true),
            .thread = undefined,
            .interval_ns = 100 * std.time.ns_per_ms, // Default 100ms
            .allocator = std.heap.page_allocator,
        };
    }

    /// Clean up RefreshThread resources
    ///
    /// Releases resources. The thread must be stopped before calling deinit().
    ///
    /// IMPORTANT: Call stop() before deinit() to ensure clean shutdown.
    pub fn deinit(self: *RefreshThread) void {
        // page_allocator doesn't need deinit
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
    /// Graceful shutdown:
    ///   - Catches all errors to prevent crashes during HAL shutdown
    ///   - Exits immediately on first error (likely HAL shutdown)
    ///   - Also exits when running flag is set to false
    ///
    /// Example:
    /// ```
    /// // Called automatically by start() - do not call directly
    /// ```
    fn run(self: *RefreshThread) void {
        // Track consecutive errors to detect HAL shutdown
        var consecutive_errors: u32 = 0;

        while (self.running.load(.acquire)) {
            // Refresh HAL state (may fail without crashing)
            // If we get errors, assume HAL is shutting down and exit
            if (self.refreshHal()) {
                // Success - reset error counter
                consecutive_errors = 0;
            } else |err| {
                // Error occurred - log it
                std.log.err("Refresh error: {}", .{err});
                std.debug.print("Refresh error: {}\n", .{err});
                consecutive_errors += 1;

                // If we get multiple consecutive errors, HAL is likely shut down
                // Exit the thread to prevent assertion failures
                if (consecutive_errors >= 3) {
                    std.log.warn("Multiple refresh errors - assuming HAL shutdown, exiting thread", .{});
                    std.debug.print("Multiple refresh errors - exiting RefreshThread\n", .{});
                    return;
                }
            }

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
    ///   - Discovers pins/signals/params from newly loaded components (halcmd loadusr)
    ///   - Removes pins/signals/params from unloaded components (stale cleanup)
    fn refreshHal(self: *RefreshThread) !void {
        // Refresh all HAL data types
        try self.refreshPins();
        try self.refreshSignals();
        try self.refreshParams();
    }

    /// Refresh all pins from HAL
    ///
    /// This function:
    /// 1. Discovers all pins from HAL using halcmd
    /// 2. Updates all pin values from HAL
    ///
    /// Thread safety:
    ///   - Reads HAL pins without holding cache lock
    fn refreshPins(self: *RefreshThread) !void {
        // Track all discovered pin names in this refresh cycle
        // Note: HashMap owns copies of pin names to avoid dangling pointers
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer {
            // Free owned pin name copies
            var iter = discovered_names.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered_names.deinit();
        }

        // Discover all pins by calling halcmd list pin
        std.debug.print("refreshPins: discovering all pins from HAL\n", .{});

        const pin_names = discovery.listPinNames(self.allocator) catch |err| {
            std.log.err("refreshPins: halcmd failed: {}", .{err});
            return err;
        };
        defer {
            for (pin_names.items) |name| {
                self.allocator.free(name);
            }
            pin_names.deinit();
        }

        var pin_count: usize = 0;
        for (pin_names.items) |pin_name| {
            std.debug.print("  pin: {s}\n", .{pin_name});

            // Copy the pin name so HashMap owns it (pin_names memory gets freed)
            const pin_name_copy = try self.allocator.dupe(u8, pin_name);
            try discovered_names.put(pin_name_copy, {});

            // Create null-terminated version for FFI call
            const pin_name_z = try self.allocator.dupeZ(u8, pin_name);
            defer self.allocator.free(pin_name_z);

            if (ffi.getPinValueByName(pin_name_z)) |v| {
                self.store.addPin(pin_name, v) catch {
                    self.store.updatePin(pin_name, v) catch {};
                };
                pin_count += 1;
            } else |err| {
                std.debug.print("refreshPins: skipping {s}: {}\n", .{ pin_name, err });
            }
        }

        std.debug.print("refreshPins: discovered {d} pins from HAL\n", .{pin_count});

        // Remove pins from cache that are no longer in HAL
        const cached_names = try self.store.listPins(self.allocator);
        defer {
            for (cached_names) |n| self.allocator.free(n);
            self.allocator.free(cached_names);
        }

        for (cached_names) |name| {
            if (discovered_names.get(name) == null) {
                self.store.removePin(name) catch {};
                std.debug.print("refreshPins: removed stale pin {s}\n", .{name});
            }
        }
    }

    /// Refresh all signals from HAL
    ///
    /// This function:
    /// 1. Discovers all signals from HAL using halcmd
    /// 2. Updates all cached signal values from HAL
    ///
    /// Thread safety:
    ///   - Reads HAL signals without holding cache lock
    fn refreshSignals(self: *RefreshThread) !void {
        // Track all discovered signal names in this refresh cycle
        // Note: HashMap owns copies of signal names to avoid dangling pointers
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer {
            // Free owned signal name copies
            var iter = discovered_names.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered_names.deinit();
        }

        // Discover all signals by calling halcmd list sig
        std.debug.print("refreshSignals: discovering all signals from HAL\n", .{});

        const sig_names = discovery.listSignalNames(self.allocator) catch |err| {
            std.log.err("refreshSignals: halcmd failed: {}", .{err});
            return err;
        };
        defer {
            for (sig_names.items) |name| {
                self.allocator.free(name);
            }
            sig_names.deinit();
        }

        var sig_count: usize = 0;
        for (sig_names.items) |sig_name| {
            std.debug.print("  signal: {s}\n", .{sig_name});

            // Copy the signal name so HashMap owns it (sig_names memory gets freed)
            const sig_name_copy = try self.allocator.dupe(u8, sig_name);
            try discovered_names.put(sig_name_copy, {});

            // Create null-terminated version for FFI call
            const sig_name_z = try self.allocator.dupeZ(u8, sig_name);
            defer self.allocator.free(sig_name_z);

            if (ffi.getSignalValueByName(sig_name_z)) |v| {
                self.store.addSignal(sig_name, v) catch {
                    self.store.updateSignal(sig_name, v) catch {};
                };
                sig_count += 1;
            } else |err| {
                std.debug.print("refreshSignals: skipping {s}: {}\n", .{ sig_name, err });
            }
        }

        std.debug.print("refreshSignals: discovered {d} signals from HAL\n", .{sig_count});

        // Remove signals from cache that are no longer in HAL
        const cached_names = try self.store.listSignals(self.allocator);
        defer {
            for (cached_names) |n| self.allocator.free(n);
            self.allocator.free(cached_names);
        }

        for (cached_names) |name| {
            if (discovered_names.get(name) == null) {
                self.store.removeSignal(name) catch {};
                std.debug.print("refreshSignals: removed stale signal {s}\n", .{name});
            }
        }
    }

    /// Refresh all parameters from HAL
    ///
    /// This function:
    /// 1. Discovers all parameters from HAL using halcmd
    /// 2. Updates all parameter values from HAL
    ///
    /// Thread safety:
    ///   - Reads HAL parameters without holding cache lock
    fn refreshParams(self: *RefreshThread) !void {
        // Track all discovered param names in this refresh cycle
        // Note: HashMap owns copies of param names to avoid dangling pointers
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer {
            // Free owned param name copies
            var iter = discovered_names.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered_names.deinit();
        }

        // Discover all params by calling halcmd list param
        std.debug.print("refreshParams: discovering all params from HAL\n", .{});

        const param_names = discovery.listParamNames(self.allocator) catch |err| {
            std.log.err("refreshParams: halcmd failed: {}", .{err});
            return err;
        };
        defer {
            for (param_names.items) |name| {
                self.allocator.free(name);
            }
            param_names.deinit();
        }

        var param_count: usize = 0;
        for (param_names.items) |param_name| {
            std.debug.print("  param: {s}\n", .{param_name});

            // Copy the param name so HashMap owns it (param_names memory gets freed)
            const param_name_copy = try self.allocator.dupe(u8, param_name);
            try discovered_names.put(param_name_copy, {});

            // Create null-terminated version for FFI call
            const param_name_z = try self.allocator.dupeZ(u8, param_name);
            defer self.allocator.free(param_name_z);

            if (ffi.getParamValueByName(param_name_z)) |v| {
                self.store.addParam(param_name, v) catch {
                    self.store.updateParam(param_name, v) catch {};
                };
                param_count += 1;
            } else |err| {
                std.debug.print("refreshParams: skipping {s}: {}\n", .{ param_name, err });
            }
        }

        std.debug.print("refreshParams: discovered {d} params from HAL\n", .{param_count});

        // Remove params from cache that are no longer in HAL
        const cached_names = try self.store.listParams(self.allocator);
        defer {
            for (cached_names) |n| self.allocator.free(n);
            self.allocator.free(cached_names);
        }

        for (cached_names) |name| {
            if (discovered_names.get(name) == null) {
                self.store.removeParam(name) catch {};
            }
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
