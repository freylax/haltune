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

// Remote HAL backend support
const HalBackend = @import("../hal/backend.zig").HalBackend;

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

    /// Optional redraw flag to trigger UI updates when StateStore is populated
    /// If set, this flag will be set to true when pins/signals/params are first discovered
    redraw_flag: ?*std.atomic.Value(bool) = null,

    /// Optional vxfw App to schedule tick events for redraw
    /// This is more reliable than redraw_flag for triggering initial population
    vxfw_app: ?*anyopaque = null,

    /// Track if we've ever populated StateStore (for initial redraw trigger)
    populated: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// Optional remote HAL backend (null = use local HAL)
    remote_backend: ?*const anyopaque = null,

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

    /// Set the redraw flag for UI updates
    pub fn setRedrawFlag(self: *RefreshThread, flag: *std.atomic.Value(bool)) void {
        self.redraw_flag = flag;
    }

    /// Set the remote HAL backend (null = use local HAL)
    pub fn setRemoteBackend(self: *RefreshThread, backend: ?*const anyopaque) void {
        self.remote_backend = backend;
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
                consecutive_errors += 1;

                // If we get multiple consecutive errors, HAL is likely shut down
                // Exit the thread to prevent assertion failures
                if (consecutive_errors >= 3) {
                    std.log.warn("Multiple refresh errors - assuming HAL shutdown, exiting thread", .{});
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

    /// Refresh pins from remote HAL backend
    fn refreshPinsRemote(self: *RefreshThread, backend_ptr: *const anyopaque) !void {
        const backend: *const HalBackend = @ptrCast(@alignCast(backend_ptr));

        // Get list of pins from remote backend
        const pin_infos = backend.listPins(self.allocator) catch |err| {
            std.log.err("refreshPinsRemote: listPins failed: {}", .{err});
            // For remote backend with empty implementation, return silently
            return;
        };
        defer {
            for (pin_infos) |pin| {
                self.allocator.free(pin.name);
            }
            self.allocator.free(pin_infos);
        }

        // Track discovered names
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer {
            var iter = discovered_names.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered_names.deinit();
        }

        // Process each pin
        for (pin_infos) |pin| {
            const name_copy = try self.allocator.dupe(u8, pin.name);
            discovered_names.put(name_copy, {}) catch |err| {
                self.allocator.free(name_copy);
                return err;
            };

            // Get current value and update store
            const backend_value = backend.getPinValue(pin.name) catch |err| {
                std.log.err("refreshPinsRemote: getPinValue({s}) failed: {}", .{ pin.name, err });
                continue;
            };

            // Convert backend.HalValue to cache.HalValue
            const value: HalValue = switch (backend_value) {
                .bit => |v| HalValue{ .bit = v },
                .float => |v| HalValue{ .float = v },
                .s32 => |v| HalValue{ .s32 = v },
                .u32 => |v| HalValue{ .u32 = v },
            };

            self.store.updatePin(pin.name, value) catch |err| {
                std.log.err("refreshPinsRemote: updatePin({s}) failed: {}", .{ pin.name, err });
            };
        }

        // Remove stale pins
        const cached_names = try self.store.listPins(self.allocator);
        defer {
            for (cached_names) |n| self.allocator.free(n);
            self.allocator.free(cached_names);
        }

        for (cached_names) |name| {
            if (discovered_names.get(name) == null) {
                self.store.removePin(name) catch {};
            }
        }
    }

    /// Refresh signals from remote HAL backend
    fn refreshSignalsRemote(self: *RefreshThread, backend_ptr: *const anyopaque) !void {
        const backend: *const HalBackend = @ptrCast(@alignCast(backend_ptr));

        // Get list of signals from remote backend
        const signal_infos = backend.listSignals(self.allocator) catch |err| {
            std.log.err("refreshSignalsRemote: listSignals failed: {}", .{err});
            return error.UnexpectedResponse;
        };
        defer {
            for (signal_infos) |sig| {
                self.allocator.free(sig.name);
                self.allocator.free(sig.writers);
                self.allocator.free(sig.readers);
            }
            self.allocator.free(signal_infos);
        }

        // Track discovered names
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer {
            var iter = discovered_names.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered_names.deinit();
        }

        // Process each signal - just track existence for now
        for (signal_infos) |sig| {
            const name_copy = try self.allocator.dupe(u8, sig.name);
            discovered_names.put(name_copy, {}) catch |err| {
                self.allocator.free(name_copy);
                return err;
            };

            // TODO: Get signal values when backend supports it
            _ = sig.value;
        }

        // Remove stale signals
        const cached_names = try self.store.listSignals(self.allocator);
        defer {
            for (cached_names) |n| self.allocator.free(n);
            self.allocator.free(cached_names);
        }

        for (cached_names) |name| {
            if (discovered_names.get(name) == null) {
                self.store.removeSignal(name) catch {};
            }
        }
    }

    /// Refresh params from remote HAL backend
    fn refreshParamsRemote(self: *RefreshThread, backend_ptr: *const anyopaque) !void {
        const backend: *const HalBackend = @ptrCast(@alignCast(backend_ptr));

        // Get list of params from remote backend
        const param_infos = backend.listParams(self.allocator) catch |err| {
            std.log.err("refreshParamsRemote: listParams failed: {}", .{err});
            return error.UnexpectedResponse;
        };
        defer {
            for (param_infos) |param| {
                self.allocator.free(param.name);
            }
            self.allocator.free(param_infos);
        }

        // Track discovered names
        var discovered_names = std.StringHashMap(void).init(self.allocator);
        defer {
            var iter = discovered_names.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered_names.deinit();
        }

        // Process each param
        for (param_infos) |param| {
            const name_copy = try self.allocator.dupe(u8, param.name);
            discovered_names.put(name_copy, {}) catch |err| {
                self.allocator.free(name_copy);
                return err;
            };

            // Get current value and update store
            const backend_value = backend.getParamValue(param.name) catch |err| {
                std.log.err("refreshParamsRemote: getParamValue({s}) failed: {}", .{ param.name, err });
                continue;
            };

            // Convert backend.HalValue to cache.HalValue
            const value: HalValue = switch (backend_value) {
                .bit => |v| HalValue{ .bit = v },
                .float => |v| HalValue{ .float = v },
                .s32 => |v| HalValue{ .s32 = v },
                .u32 => |v| HalValue{ .u32 = v },
            };

            self.store.updateParam(param.name, value) catch |err| {
                std.log.err("refreshParamsRemote: updateParam({s}) failed: {}", .{ param.name, err });
            };
        }

        // Remove stale params
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

        // Trigger redraw on first successful population (after ALL types are loaded)
        // Check if we have any data now
        const has_data = blk: {
            self.store.rwlock.lockShared();
            defer self.store.rwlock.unlockShared();
            break :blk self.store.pins.count() > 0 or
                      self.store.signals.count() > 0 or
                      self.store.params.count() > 0;
        };

        if (has_data and !self.populated.load(.acquire)) {
            self.populated.store(true, .release);
            if (self.redraw_flag) |flag| {
                flag.store(true, .release);
                std.log.info("RefreshThread: StateStore populated, triggering redraw", .{});
            }
        }
    }

    /// Refresh all pins from HAL
    ///
    /// This function:
    /// 1. Discovers all pins from HAL using halcmd (local) or remote backend
    /// 2. Updates all pin values from HAL
    ///
    /// Thread safety:
    ///   - Reads HAL pins without holding cache lock
    fn refreshPins(self: *RefreshThread) !void {
        // Check if using remote HAL backend
        if (self.remote_backend) |backend_ptr| {
            return self.refreshPinsRemote(backend_ptr);
        }

        // Local HAL refresh path
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
        var pin_names = discovery.listPinNames(self.allocator) catch |err| {
            std.log.err("refreshPins: halcmd failed: {}", .{err});
            return err;
        };
        defer {
            for (pin_names.items) |name| {
                self.allocator.free(name);
            }
            pin_names.deinit(self.allocator);
        }

        var pin_count: usize = 0;
        for (pin_names.items) |pin_name| {
            // Copy the pin name so HashMap owns it (pin_names memory gets freed)
            const pin_name_copy = try self.allocator.dupe(u8, pin_name);
            discovered_names.put(pin_name_copy, {}) catch |err| {
                self.allocator.free(pin_name_copy);
                return err;
            };

            // Create null-terminated version for FFI call
            const pin_name_z = try self.allocator.dupeZ(u8, pin_name);
            defer self.allocator.free(pin_name_z);

            if (ffi.getPinValueByName(pin_name_z)) |v| {
                self.store.addPin(pin_name, v) catch {
                    self.store.updatePin(pin_name, v) catch {};
                };
                pin_count += 1;
            } else |err| {
                std.log.err("refreshPins: skipping {s}: {}\n", .{ pin_name, err });
            }
        }

        // Remove pins from cache that are no longer in HAL
        const cached_names = try self.store.listPins(self.allocator);
        defer {
            for (cached_names) |n| self.allocator.free(n);
            self.allocator.free(cached_names);
        }

        for (cached_names) |name| {
            if (discovered_names.get(name) == null) {
                self.store.removePin(name) catch {};
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
        // Check if using remote HAL backend
        if (self.remote_backend) |backend_ptr| {
            return self.refreshSignalsRemote(backend_ptr);
        }

        // Local HAL refresh path
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
        var sig_names = discovery.listSignalNames(self.allocator) catch |err| {
            std.log.err("refreshSignals: halcmd failed: {}", .{err});
            return err;
        };
        defer {
            for (sig_names.items) |name| {
                self.allocator.free(name);
            }
            sig_names.deinit(self.allocator);
        }

        for (sig_names.items) |sig_name| {
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
            } else |err| {
                std.log.err("refreshSignals: skipping {s}: {}\n", .{ sig_name, err });
            }
        }

        // Remove signals from cache that are no longer in HAL
        const cached_names = try self.store.listSignals(self.allocator);
        defer {
            for (cached_names) |n| self.allocator.free(n);
            self.allocator.free(cached_names);
        }

        for (cached_names) |name| {
            if (discovered_names.get(name) == null) {
                self.store.removeSignal(name) catch {};
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
        // Check if using remote HAL backend
        if (self.remote_backend) |backend_ptr| {
            return self.refreshParamsRemote(backend_ptr);
        }

        // Local HAL refresh path
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
        var param_names = discovery.listParamNames(self.allocator) catch |err| {
            std.log.err("refreshParams: halcmd failed: {}", .{err});
            return err;
        };
        defer {
            for (param_names.items) |name| {
                self.allocator.free(name);
            }
            param_names.deinit(self.allocator);
        }

        for (param_names.items) |param_name| {
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
            } else |err| {
                std.log.err("refreshParams: skipping {s}: {}\n", .{ param_name, err });
            }
        }

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
