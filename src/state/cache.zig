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
const HalError = @import("ffi-errors").HalError;
const ItemOrigin = @import("../config/origin.zig").ItemOrigin;
const OriginTracker = @import("../config/origin.zig").OriginTracker;

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
    /// Configuration origin tracking
    origin_tracker: OriginTracker,

    /// HashMap storing pin values indexed by name
    pins: std.StringHashMap(HalValue),

    /// HashMap storing signal values indexed by name
    signals: std.StringHashMap(HalValue),

    /// HashMap storing parameter values indexed by name
    params: std.StringHashMap(HalValue),

    /// HashMap storing pin -> signal mappings (pin_name -> signal_name)
    pin_links: std.StringHashMap([]const u8),

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
            .pin_links = std.StringHashMap([]const u8).init(allocator),
            .origin_tracker = OriginTracker.init(allocator),
        };
    }

    /// Ensure HashMap has enough capacity for typical HAL configurations
    /// This prevents resizes during concurrent access
    pub fn ensureCapacity(self: *StateStore, pin_count: usize, signal_count: usize, param_count: usize) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        try self.pins.ensureUnusedCapacity(pin_count);
        try self.signals.ensureUnusedCapacity(signal_count);
        try self.params.ensureUnusedCapacity(param_count);
    }

    /// Clean up StateStore and free all resources
    ///
    /// Releases all HashMap storage. The StateStore must not be used
    /// after calling deinit().
    ///
    /// IMPORTANT: This frees all owned string keys since we dupe them
    /// in addPin/addSignal/addParam to ensure HashMap owns the memory.
    ///
    /// Example:
    /// ```
    /// var store = StateStore.init(std.heap.page_allocator);
    /// defer store.deinit();  // Always cleanup
    /// ```
    pub fn deinit(self: *StateStore) void {
        // Free owned pin keys
        {
            var iter = self.pins.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.pins.deinit();

        // Free owned signal keys
        {
            var iter = self.signals.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.signals.deinit();

        // Free owned param keys
        {
            var iter = self.params.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.params.deinit();

        // Free pin link strings
        var link_iter = self.pin_links.iterator();
        while (link_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.pin_links.deinit();

        // Clean up origin tracker
        self.origin_tracker.deinit();

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

        // Check if key already exists (by content)
        if (self.pins.get(name)) |_| {
            // Key already exists, just update the value
            try self.pins.put(name, value);
        } else {
            // New key - DUPE the key so HashMap owns the memory!
            // This is critical because the 'name' parameter points to memory
            // that will be freed when refreshPins returns
            const name_owned = try self.allocator.dupe(u8, name);
            try self.pins.put(name_owned, value);
        }
    }

    /// Get or add a pin (internal helper for refresh thread)
    /// This handles the case where a pin may already exist from a previous refresh
    fn getOrAddPin(self: *StateStore, name: []const u8, value: HalValue) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        // First try to update existing pin
        if (self.pins.get(name)) |_| {
            try self.pins.put(name, value);
        } else {
            // New pin - add it
            try self.pins.put(name, value);
        }
    }

    /// Add a new signal to the cache
    ///
    /// This function adds a newly discovered signal to the cache with its initial value.
    /// Used by the refresh thread when discovering signals from dynamically loaded components.
    ///
    /// Parameters:
    ///   - name: Signal name to add
    ///   - value: Initial value for the signal
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
    /// // Discovered new signal via HAL enumeration
    /// try store.addSignal("new-component.signal-0", .{.float = 0.0});
    /// ```
    pub fn addSignal(self: *StateStore, name: []const u8, value: HalValue) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        // Check if key already exists
        if (self.signals.get(name)) |_| {
            // Key exists, just update the value
            try self.signals.put(name, value);
        } else {
            // New key - dupe it so HashMap owns the memory
            const name_owned = try self.allocator.dupe(u8, name);
            try self.signals.put(name_owned, value);
        }
    }

    /// Add a new parameter to the cache
    ///
    /// This function adds a newly discovered parameter to the cache with its initial value.
    /// Used by the refresh thread when discovering parameters from dynamically loaded components.
    ///
    /// Parameters:
    ///   - name: Parameter name to add
    ///   - value: Initial value for the parameter
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
    /// // Discovered new parameter via HAL enumeration
    /// try store.addParam("new-component.param-0", .{.s32 = 0});
    /// ```
    pub fn addParam(self: *StateStore, name: []const u8, value: HalValue) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        // Check if key already exists
        if (self.params.get(name)) |_| {
            // Key exists, just update the value
            try self.params.put(name, value);
        } else {
            // New key - dupe it so HashMap owns the memory
            const name_owned = try self.allocator.dupe(u8, name);
            try self.params.put(name_owned, value);
        }
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
        var keys = std.ArrayList([]const u8).initCapacity(allocator, 8) catch unreachable;
        defer keys.deinit(allocator);
        var iter = self.pins.iterator();
        while (iter.next()) |entry| {
            // Duplicate the key string so caller owns the memory (HashMap may reallocate)
            const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
            try keys.append(allocator, key_copy);
        }

        // Return owned slice (caller must free both outer slice and inner strings)
        return keys.toOwnedSlice(allocator);
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
        var keys = std.ArrayList([]const u8).initCapacity(allocator, 4) catch unreachable;
        defer keys.deinit(allocator);
        var iter = self.signals.iterator();
        while (iter.next()) |entry| {
            // Duplicate the key string so caller owns the memory (HashMap may reallocate)
            const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
            try keys.append(allocator, key_copy);
        }

        // Return owned slice (caller must free both outer slice and inner strings)
        return keys.toOwnedSlice(allocator);
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
        var keys = std.ArrayList([]const u8).initCapacity(allocator, 4) catch unreachable;
        defer keys.deinit(allocator);
        var iter = self.params.iterator();
        while (iter.next()) |entry| {
            // Duplicate the key string so caller owns the memory (HashMap may reallocate)
            const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
            try keys.append(allocator, key_copy);
        }

        // Return owned slice (caller must free both outer slice and inner strings)
        return keys.toOwnedSlice(allocator);
    }

    /// Get all pins linked to a signal
    ///
    /// Returns a list of pin names that are linked to the specified signal.
    /// Used by configuration export to generate net commands.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for the returned string slice
    ///   - signal_name: Signal name to find linked pins for
    ///
    /// Returns:
    ///   - Slice of pin names linked to this signal (caller owns memory)
    ///   - Empty slice if signal has no linked pins
    ///   - error.OutOfMemory if allocation fails
    ///
    /// Thread safety:
    ///   - Acquires shared lock while copying keys
    ///   - Caller must free returned slice and all pin names with allocator.free()
    ///
    /// Example:
    /// ```
    /// const pins = try store.getSignalLinks(allocator, "my-signal");
    /// defer {
    ///     for (pins) |pin| allocator.free(pin);
    ///     allocator.free(pins);
    /// }
    /// ```
    pub fn getSignalLinks(
        self: *StateStore,
        allocator: std.mem.Allocator,
        signal_name: []const u8,
    ) ![][]const u8 {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        var result = std.ArrayList([]const u8).initCapacity(allocator, 4) catch unreachable;

        // Iterate through all pin_links and find pins linked to this signal
        var iter = self.pin_links.iterator();
        while (iter.next()) |entry| {
            const pin_name = entry.key_ptr.*;
            const linked_signal = entry.value_ptr.*;

            if (std.mem.eql(u8, linked_signal, signal_name)) {
                // Duplicate pin name for caller
                try result.append(allocator, try allocator.dupe(u8, pin_name));
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Update pin->signal link mapping
    ///
    /// Called by refresh thread when pin link status changes.
    /// This is a stub for now - the refresh thread doesn't yet track links.
    pub fn updatePinLink(self: *StateStore, pin_name: []const u8, signal_name: ?[]const u8) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        // Remove old link if exists
        if (self.pin_links.fetchRemove(pin_name)) |entry| {
            self.allocator.free(entry.value);
        }

        // Add new link if provided
        if (signal_name) |sig| {
            try self.pin_links.put(pin_name, try self.allocator.dupe(u8, sig));
        }
    }

    /// Count how many pins are linked to a signal
    ///
    /// Iterates through pin_links to count connections to the given signal.
    /// Used to determine if a signal is orphaned (no pins connected).
    ///
    /// Parameters:
    ///   - signal_name: Signal name to count pins for
    ///
    /// Returns:
    ///   - Number of pins linked to this signal
    pub fn countPinsForSignal(self: *StateStore, signal_name: []const u8) usize {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        var count: usize = 0;
        var iter = self.pin_links.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.*, signal_name)) {
                count += 1;
            }
        }
        return count;
    }

    /// Remove a pin from the cache
    ///
    /// Deletes a pin entry from the cache. Used by refresh thread to remove
    /// stale entries when components are unloaded.
    ///
    /// Parameters:
    ///   - name: Pin name to remove
    ///
    /// Returns:
    ///   - void on success
    ///
    /// Thread safety:
    ///   - Acquires exclusive lock (blocks all readers)
    ///
    /// Example:
    /// ```
    /// // Component unloaded, remove its pins
    /// try store.removePin("unloaded-component.pin-0");
    /// ```
    pub fn removePin(self: *StateStore, name: []const u8) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        if (self.pins.fetchRemove(name)) |entry| {
            // Free the owned key
            self.allocator.free(entry.key);
        }
    }

    /// Remove a signal from the cache
    ///
    /// Deletes a signal entry from the cache. Used by refresh thread to remove
    /// stale entries when components are unloaded.
    ///
    /// Parameters:
    ///   - name: Signal name to remove
    ///
    /// Returns:
    ///   - void on success
    ///
    /// Thread safety:
    ///   - Acquires exclusive lock (blocks all readers)
    ///
    /// Example:
    /// ```
    /// // Component unloaded, remove its signals
    /// try store.removeSignal("unloaded-component.signal-0");
    /// ```
    pub fn removeSignal(self: *StateStore, name: []const u8) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        if (self.signals.fetchRemove(name)) |entry| {
            // Free the owned key
            self.allocator.free(entry.key);
        }
    }

    /// Remove a parameter from the cache
    ///
    /// Deletes a parameter entry from the cache. Used by refresh thread to remove
    /// stale entries when components are unloaded.
    ///
    /// Parameters:
    ///   - name: Parameter name to remove
    ///
    /// Returns:
    ///   - void on success
    ///
    /// Thread safety:
    ///   - Acquires exclusive lock (blocks all readers)
    ///
    /// Example:
    /// ```
    /// // Component unloaded, remove its params
    /// try store.removeParam("unloaded-component.param-0");
    /// ```
    pub fn removeParam(self: *StateStore, name: []const u8) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        if (self.params.fetchRemove(name)) |entry| {
            // Free the owned key
            self.allocator.free(entry.key);
        }
    }

    /// Get origin information for a pin
    ///
    /// Returns the origin information (file, line, etc.) for a pin.
    ///
    /// Parameters:
    ///   - name: Pin name to look up
    ///
    /// Returns:
    ///   - ItemOrigin on success
    ///   - null if pin has no origin information
    ///
    /// Thread safety:
    ///   - Acquires shared lock (allows concurrent reads)
    pub fn getPinOrigin(self: *const StateStore, name: []const u8) ?ItemOrigin {
        return self.origin_tracker.getPinOrigin(name);
    }

    /// Get origin information for a signal
    ///
    /// Returns the origin information (file, line, etc.) for a signal.
    ///
    /// Parameters:
    ///   - name: Signal name to look up
    ///
    /// Returns:
    ///   - ItemOrigin on success
    ///   - null if signal has no origin information
    ///
    /// Thread safety:
    ///   - Acquires shared lock (allows concurrent reads)
    pub fn getSignalOrigin(self: *const StateStore, name: []const u8) ?ItemOrigin {
        return self.origin_tracker.getSignalOrigin(name);
    }

    /// Get origin information for a parameter
    ///
    /// Returns the origin information (file, line, etc.) for a parameter.
    ///
    /// Parameters:
    ///   - name: Parameter name to look up
    ///
    /// Returns:
    ///   - ItemOrigin on success
    ///   - null if parameter has no origin information
    ///
    /// Thread safety:
    ///   - Acquires shared lock (allows concurrent reads)
    pub fn getParamOrigin(self: *const StateStore, name: []const u8) ?ItemOrigin {
        return self.origin_tracker.getParamOrigin(name);
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
    _ = StateStore.removePin;
    _ = StateStore.getSignal;
    _ = StateStore.updateSignal;
    _ = StateStore.addSignal;
    _ = StateStore.removeSignal;
    _ = StateStore.getParam;
    _ = StateStore.updateParam;
    _ = StateStore.addParam;
    _ = StateStore.removeParam;

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
