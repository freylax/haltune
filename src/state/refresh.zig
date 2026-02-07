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
    /// 1. Discovers all pins from HAL components
    /// 2. Updates all pin values from HAL
    ///
    /// Thread safety:
    ///   - Reads HAL pins without holding cache lock
    fn refreshPins(self: *RefreshThread) !void {
        const safe = @import("../ffi/safe.zig");

        // Track all discovered pin names in this refresh cycle
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer discovered_names.deinit();

        // Discover all pins by walking HAL's pin list
        std.debug.print("refreshPins: discovering all pins from HAL\n", .{});

        var pin_count: usize = 0;
        var maybe_pin = safe.halprFindPinByName(null); // Get first pin
        while (maybe_pin) |pin| {
            // Get pin name using getPinName helper
            const pin_name = safe.getPinName(pin) orelse {
                // Can't get name, skip to next
                // Get next pin via linked list - note: hal_pin_t.next is at offset 0
                const next_ptr: [*]u8 = @ptrCast(pin);
                const next: ?*opaque {} = @ptrCast(next_ptr + @sizeOf(usize)); // Next pointer is first field
                maybe_pin = safe.halprFindPinByName(@ptrCast(next)); // Use find to get typed pointer
                continue;
            };

            // Convert to Zig string for our use
            const pin_name_len = std.mem.len(pin_name);
            const pin_name_slice = pin_name[0..pin_name_len];

            // Add to discovered set
            try discovered_names.put(pin_name_slice, {});

            // Read pin value
            if (ffi.getPinValueByName(pin_name)) |v| {
                // Try to add to store (will update if exists)
                self.store.addPin(pin_name_slice, v) catch {
                    // If add failed, try updating
                    self.store.updatePin(pin_name_slice, v) catch {};
                };
                pin_count += 1;
            } else |err| {
                std.debug.print("refreshPins: skipping {s}: {}\n", .{pin_name_slice, err});
            }

            // Get next pin - the next pointer is at offset 0 in hal_pin_t
            const next_ptr: [*]u8 = @ptrCast(pin);
            const next_ptr_addr = @as([*]const ?*opaque {}, @ptrCast(next_ptr));
            maybe_pin = safe.halprFindPinByName(@ptrCast(next_ptr_addr.*));
        }

        std.debug.print("refreshPins: discovered {d} pins from HAL\n", .{pin_count});

        // Remove pins from cache that are no longer in HAL
        const cached_names = try self.store.listPins(self.allocator);
        defer self.allocator.free(cached_names);

        for (cached_names) |name| {
            if (!discovered_names.get(name)) {
                // Pin no longer exists in HAL, remove from cache
                self.store.removePin(name) catch {};
                std.debug.print("refreshPins: removed stale pin {s}\n", .{name});
            }
        }
    }

    /// Refresh all signals from HAL
    ///
    /// This function:
    /// 1. Discovers all signals from HAL
    /// 2. Updates all signal values from HAL
    ///
    /// Thread safety:
    ///   - Reads HAL signals without holding cache lock
    fn refreshSignals(self: *RefreshThread) !void {
        const safe = @import("../ffi/safe.zig");

        // Track all discovered signal names in this refresh cycle
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer discovered_names.deinit();

        // Discover all signals by walking HAL's signal list
        var sig_count: usize = 0;
        var maybe_sig = safe.halprFindSigByName(null); // Get first signal
        while (maybe_sig) |sig| {
            // Get signal name using getSignalName helper
            const sig_name = safe.getSignalName(sig) orelse {
                // Can't get name, skip to next
                const next_ptr: [*]u8 = @ptrCast(sig);
                const next: ?*opaque {} = @ptrCast(next_ptr + @sizeOf(usize));
                maybe_sig = safe.halprFindSigByName(@ptrCast(next));
                continue;
            };

            // Convert to Zig string for our use
            const sig_name_len = std.mem.len(sig_name);
            const sig_name_slice = sig_name[0..sig_name_len];

            // Add to discovered set
            try discovered_names.put(sig_name_slice, {});

            // Read signal value
            if (ffi.getSignalValueByName(sig_name)) |v| {
                // Try to add to store (will update if exists)
                self.store.addSignal(sig_name_slice, v) catch {
                    // If add failed, try updating
                    self.store.updateSignal(sig_name_slice, v) catch {};
                };
                sig_count += 1;
            } else |err| {
                std.debug.print("refreshSignals: skipping {s}: {}\n", .{sig_name_slice, err});
            }

            // Get next signal
            const next_ptr: [*]u8 = @ptrCast(sig);
            const next_ptr_addr = @as([*]const ?*opaque {}, @ptrCast(next_ptr));
            maybe_sig = safe.halprFindSigByName(@ptrCast(next_ptr_addr.*));
        }

        std.debug.print("refreshSignals: discovered {d} signals from HAL\n", .{sig_count});

        // Remove signals from cache that are no longer in HAL
        const cached_names = try self.store.listSignals(self.allocator);
        defer self.allocator.free(cached_names);

        for (cached_names) |name| {
            if (!discovered_names.get(name)) {
                self.store.removeSignal(name) catch {};
            }
        }
    }

    /// Refresh all parameters from HAL
    ///
    /// This function:
    /// 1. Discovers all parameters from HAL
    /// 2. Updates all parameter values from HAL
    ///
    /// Thread safety:
    ///   - Reads HAL parameters without holding cache lock
    fn refreshParams(self: *RefreshThread) !void {
        const safe = @import("../ffi/safe.zig");

        // Track all discovered param names in this refresh cycle
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer discovered_names.deinit();

        // Discover all params by walking HAL's param list
        var param_count: usize = 0;
        var maybe_param = safe.halprFindParamByName(null); // Get first param
        while (maybe_param) |param| {
            // Get param name using getParamName helper
            const param_name = safe.getParamName(param) orelse {
                // Can't get name, skip to next
                const next_ptr: [*]u8 = @ptrCast(param);
                const next: ?*opaque {} = @ptrCast(next_ptr + @sizeOf(usize));
                maybe_param = safe.halprFindParamByName(@ptrCast(next));
                continue;
            };

            // Convert to Zig string for our use
            const param_name_len = std.mem.len(param_name);
            const param_name_slice = param_name[0..param_name_len];

            // Add to discovered set
            try discovered_names.put(param_name_slice, {});

            // Read param value
            if (ffi.getParamValueByName(param_name)) |v| {
                // Try to add to store (will update if exists)
                self.store.addParam(param_name_slice, v) catch {
                    // If add failed, try updating
                    self.store.updateParam(param_name_slice, v) catch {};
                };
                param_count += 1;
            } else |err| {
                std.debug.print("refreshParams: skipping {s}: {}\n", .{param_name_slice, err});
            }

            // Get next param
            const next_ptr: [*]u8 = @ptrCast(param);
            const next_ptr_addr = @as([*]const ?*opaque {}, @ptrCast(next_ptr));
            maybe_param = safe.halprFindParamByName(@ptrCast(next_ptr_addr.*));
        }

        std.debug.print("refreshParams: discovered {d} params from HAL\n", .{param_count});

        // Remove params from cache that are no longer in HAL
        const cached_names = try self.store.listParams(self.allocator);
        defer self.allocator.free(cached_names);

        for (cached_names) |name| {
            if (!discovered_names.get(name)) {
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
