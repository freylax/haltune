// Thread-safe state cache for HAL pin/signal/parameter values
//
// This module provides StateStore, a concurrent-access cache that stores
// HAL values indexed by name. Multiple TUI threads can read simultaneously
// using RwLock shared access, while refresh thread has exclusive write access.
//
// Design principles:
// - Use RwLock for concurrent reads (TUI) vs exclusive writes (refresh)
// - StringHashMap provides O(1) name-based lookups
// - Never call HAL functions while holding rwlock (prevents deadlock)
// - Return error.NotFound for missing keys

const std = @import("std");
const HalError = @import("../ffi/errors.zig").HalError;

/// HAL value union supporting all four HAL data types
///
/// This tagged union can store any HAL pin/signal/parameter value type.
/// The tag ensures type safety - you must check which field is valid
/// before accessing the value.
pub const HalValue = union(enum) {
    /// Boolean value (HAL_BIT pins/signals)
    bit: bool,

    /// Floating-point value (HAL_FLOAT pins/signals)
    float: f64,

    /// Signed 32-bit integer (HAL_S32 pins/signals/params)
    s32: i32,

    /// Unsigned 32-bit integer (HAL_U32 pins/signals/params)
    u32: u32,
};

/// Thread-safe state store for HAL values
///
/// StateStore maintains three separate HashMaps for pins, signals, and parameters.
/// All access is protected by a single RwLock to allow concurrent reads while
/// ensuring exclusive writes.
///
/// Lock usage:
/// - Read operations (get/list): lockShared(), defer unlockShared()
/// - Write operations (update): lock(), defer unlock()
///
/// IMPORTANT: Never call HAL FFI functions while holding rwlock.
/// This prevents deadlock with HAL's internal mutex (see RESEARCH.md Pitfall 1).
pub const StateStore = struct {
    /// Memory allocator for HashMap storage
    allocator: std.mem.Allocator,

    /// HashMap storing pin values indexed by name
    pins: std.StringHashMap(HalValue),

    /// HashMap storing signal values indexed by name
    signals: std.StringHashMap(HalValue),

    /// HashMap storing parameter values indexed by name
    params: std.StringHashMap(HalValue),

    /// Reader-writer lock for concurrent access
    /// Multiple threads can hold shared lock for reading
    /// Only one thread can hold exclusive lock for writing
    rwlock: std.Thread.RwLock = .{},

    /// Initialize a new StateStore
    ///
    /// Creates an empty state store with all HashMaps initialized.
    /// The allocator is stored for HashMap operations and must remain
    /// valid for the lifetime of the StateStore.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for HashMap storage
    ///
    /// Returns:
    ///   - Initialized StateStore
    ///
    /// Example:
    /// ```
    /// var store = StateStore.init(std.heap.page_allocator);
    /// defer store.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator) StateStore {
        return .{
            .allocator = allocator,
            .pins = std.StringHashMap(HalValue).init(allocator),
            .signals = std.StringHashMap(HalValue).init(allocator),
            .params = std.StringHashMap(HalValue).init(allocator),
        };
    }

    /// Clean up StateStore and free all resources
    ///
    /// Releases all HashMap storage. The StateStore must not be used
    /// after calling deinit().
    ///
    /// IMPORTANT: This only frees HashMap storage, not the string keys
    /// themselves. StringHashMap manages key memory automatically.
    ///
    /// Example:
    /// ```
    /// var store = StateStore.init(std.heap.page_allocator);
    /// defer store.deinit();  // Always cleanup
    /// ```
    pub fn deinit(self: *StateStore) void {
        self.pins.deinit();
        self.signals.deinit();
        self.params.deinit();
        self.* = undefined;
    }

    /// Get a pin value by name
    ///
    /// Retrieves the current value of a pin from the cache.
    /// Multiple TUI threads can call this simultaneously.
    ///
    /// Parameters:
    ///   - name: Pin name to look up (e.g., "motion.digital-in-00")
    ///
    /// Returns:
    ///   - HalValue on success
    ///   - error.NotFound if pin doesn't exist in cache
    ///
    /// Thread safety:
    ///   - Acquires shared lock (allows concurrent reads)
    ///
    /// Example:
    /// ```
    /// const value = try store.getPin("motion.digital-in-00");
    /// std.debug.print("Pin value: {}\n", .{value});
    /// ```
    pub fn getPin(self: *StateStore, name: []const u8) !HalValue {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        return self.pins.get(name) orelse return error.NotFound;
    }

    /// Update a pin value in the cache
    ///
    /// Stores or updates a pin value. Called by refresh thread
    /// after reading from HAL.
    ///
    /// Parameters:
    ///   - name: Pin name to update
    ///   - value: New value to store
    ///
    /// Returns:
    ///   - void on success
    ///   - error.OutOfMemory if allocator fails
    ///
    /// Thread safety:
    ///   - Acquires exclusive lock (blocks all readers)
    ///   - IMPORTANT: Call HAL functions BEFORE acquiring lock
    ///
    /// Example:
    /// ```
    /// // Read from HAL first (no lock held)
    /// const pin_value = try ffi.getPinFloat(pin);
    ///
    /// // Then update cache with lock
    /// try store.updatePin("motion.digital-in-00", .{.float = pin_value});
    /// ```
    pub fn updatePin(self: *StateStore, name: []const u8, value: HalValue) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        try self.pins.put(name, value);
    }

    /// Add a new pin to the cache
    ///
    /// This function adds a newly discovered pin to the cache with its initial value.
    /// Used by the refresh thread when discovering pins from dynamically loaded components.
    ///
    /// Parameters:
    ///   - name: Pin name to add
    ///   - value: Initial value for the pin
    ///
    /// Returns:
    ///   - void on success
    ///   - error.OutOfMemory if allocator fails
    ///
    /// Thread safety:
    ///   - Acquires exclusive lock (blocks all readers)
    ///
    /// Example:
    /// ```
    /// // Discovered new pin via HAL enumeration
    /// try store.addPin("new-component.pin-0", .{.float = 0.0});
    /// ```
    pub fn addPin(self: *StateStore, name: []const u8, value: HalValue) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        try self.pins.put(name, value);
    }

    /// Get a signal value by name
    ///
    /// Retrieves the current value of a signal from the cache.
    /// Multiple TUI threads can call this simultaneously.
    ///
    /// Parameters:
    ///   - name: Signal name to look up
    ///
    /// Returns:
    ///   - HalValue on success
    ///   - error.NotFound if signal doesn't exist in cache
    ///
    /// Thread safety:
    ///   - Acquires shared lock (allows concurrent reads)
    pub fn getSignal(self: *StateStore, name: []const u8) !HalValue {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        return self.signals.get(name) orelse return error.NotFound;
    }

    /// Update a signal value in the cache
    ///
    /// Stores or updates a signal value. Called by refresh thread
    /// after reading from HAL.
    ///
    /// Parameters:
    ///   - name: Signal name to update
    ///   - value: New value to store
    ///
    /// Returns:
    ///   - void on success
    ///   - error.OutOfMemory if allocator fails
    ///
    /// Thread safety:
    ///   - Acquires exclusive lock (blocks all readers)
    ///   - IMPORTANT: Call HAL functions BEFORE acquiring lock
    pub fn updateSignal(self: *StateStore, name: []const u8, value: HalValue) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        try self.signals.put(name, value);
    }

    /// Get a parameter value by name
    ///
    /// Retrieves the current value of a parameter from the cache.
    /// Multiple TUI threads can call this simultaneously.
    ///
    /// Parameters:
    ///   - name: Parameter name to look up
    ///
    /// Returns:
    ///   - HalValue on success
    ///   - error.NotFound if parameter doesn't exist in cache
    ///
    /// Thread safety:
    ///   - Acquires shared lock (allows concurrent reads)
    pub fn getParam(self: *StateStore, name: []const u8) !HalValue {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        return self.params.get(name) orelse return error.NotFound;
    }

    /// Update a parameter value in the cache
    ///
    /// Stores or updates a parameter value. Called by refresh thread
    /// after reading from HAL.
    ///
    /// Parameters:
    ///   - name: Parameter name to update
    ///   - value: New value to store
    ///
    /// Returns:
    ///   - void on success
    ///   - error.OutOfMemory if allocator fails
    ///
    /// Thread safety:
    ///   - Acquires exclusive lock (blocks all readers)
    ///   - IMPORTANT: Call HAL functions BEFORE acquiring lock
    pub fn updateParam(self: *StateStore, name: []const u8, value: HalValue) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        try self.params.put(name, value);
    }

    /// List all pin names in the cache
    ///
    /// Returns a snapshot of all pin names. Used by TUI to enumerate
    /// available pins for display and selection.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for the returned string slice
    ///
    /// Returns:
    ///   - Slice of pin names (caller owns memory)
    ///   - error.OutOfMemory if allocation fails
    ///
    /// Thread safety:
    ///   - Acquires shared lock while copying keys
    ///   - Returns owned slice (safe to iterate after lock release)
    ///
    /// IMPORTANT: Caller must free returned slice with allocator.free()
    ///
    /// Example:
    /// ```
    /// const pin_names = try store.listPins(allocator);
    /// defer allocator.free(pin_names);  // Free outer slice
    /// for (pin_names) |name| {
    ///     std.debug.print("{s}\n", .{name});
    /// }
    /// ```
    pub fn listPins(self: *StateStore, allocator: std.mem.Allocator) ![][]const u8 {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        // Snapshot keys while holding lock
        var keys = std.ArrayList([]const u8).init(allocator);
        var iter = self.pins.iterator();
        while (iter.next()) |entry| {
            try keys.append(entry.key_ptr.*);
        }

        // Return owned slice (iterator no longer needed)
        return keys.toOwnedSlice();
    }

    /// List all signal names in the cache
    ///
    /// Returns a snapshot of all signal names. Used by TUI to enumerate
    /// available signals for display and selection.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for the returned string slice
    ///
    /// Returns:
    ///   - Slice of signal names (caller owns memory)
    ///   - error.OutOfMemory if allocation fails
    ///
    /// Thread safety:
    ///   - Acquires shared lock while copying keys
    ///   - Returns owned slice (safe to iterate after lock release)
    ///
    /// IMPORTANT: Caller must free returned slice with allocator.free()
    ///
    /// Example:
    /// ```
    /// const signal_names = try store.listSignals(allocator);
    /// defer allocator.free(signal_names);  // Free outer slice
    /// for (signal_names) |name| {
    ///     std.debug.print("{s}\n", .{name});
    /// }
    /// ```
    pub fn listSignals(self: *StateStore, allocator: std.mem.Allocator) ![][]const u8 {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        // Snapshot keys while holding lock
        var keys = std.ArrayList([]const u8).init(allocator);
        var iter = self.signals.iterator();
        while (iter.next()) |entry| {
            try keys.append(entry.key_ptr.*);
        }

        // Return owned slice (iterator no longer needed)
        return keys.toOwnedSlice();
    }

    /// List all parameter names in the cache
    ///
    /// Returns a snapshot of all parameter names. Used by TUI to enumerate
    /// available parameters for display and selection.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for the returned string slice
    ///
    /// Returns:
    ///   - Slice of parameter names (caller owns memory)
    ///   - error.OutOfMemory if allocation fails
    ///
    /// Thread safety:
    ///   - Acquires shared lock while copying keys
    ///   - Returns owned slice (safe to iterate after lock release)
    ///
    /// IMPORTANT: Caller must free returned slice with allocator.free()
    ///
    /// Example:
    /// ```
    /// const param_names = try store.listParams(allocator);
    /// defer allocator.free(param_names);  // Free outer slice
    /// for (param_names) |name| {
    ///     std.debug.print("{s}\n", .{name});
    /// }
    /// ```
    pub fn listParams(self: *StateStore, allocator: std.mem.Allocator) ![][]const u8 {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        // Snapshot keys while holding lock
        var keys = std.ArrayList([]const u8).init(allocator);
        var iter = self.params.iterator();
        while (iter.next()) |entry| {
            try keys.append(entry.key_ptr.*);
        }

        // Return owned slice (iterator no longer needed)
        return keys.toOwnedSlice();
    }
};

// Compile-time tests to verify API surface
comptime {
    // Verify StateStore can be initialized
    _ = StateStore.init;

    // Verify deinit is callable
    _ = StateStore.deinit;

    // Verify get/update operations exist
    _ = StateStore.getPin;
    _ = StateStore.updatePin;
    _ = StateStore.addPin;
    _ = StateStore.getSignal;
    _ = StateStore.updateSignal;
    _ = StateStore.getParam;
    _ = StateStore.updateParam;

    // Verify list operations exist
    _ = StateStore.listPins;
    _ = StateStore.listSignals;
    _ = StateStore.listParams;

    // Verify HalValue union has all expected fields
    _ = HalValue.bit;
    _ = HalValue.float;
    _ = HalValue.s32;
    _ = HalValue.u32;
}
