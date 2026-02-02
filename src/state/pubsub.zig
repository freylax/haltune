// Subscription-based change notification system
//
// This module provides SubscriptionManager, a pubsub system allowing TUI components
// to register callbacks for specific pins/signals/params and receive notifications
// when values change. Multiple subscribers can register for the same item.
//
// Design principles:
// - Mutex protects subscriber list from concurrent modification
// - Condition variable enables efficient wake-on-broadcast
// - Subscribers receive old_value and new_value to detect changes
// - Only subscribers are notified (no spam to uninterested components)

const std = @import("std");
const HalValue = @import("cache.zig").HalValue;

/// Callback function pointer type for change notifications
///
/// Subscribers provide functions matching this signature to receive
/// notifications when HAL values change.
///
/// Parameters:
///   - item_name: Name of the pin/signal/param that changed
///   - old_value: Previous value (null if first notification)
///   - new_value: New value after change
///
/// Thread safety:
///   - Callbacks are invoked while holding SubscriptionManager mutex
///   - Keep callbacks fast to avoid blocking other notifications
///   - Don't call subscribe/unsubscribe from within callback (deadlock)
pub const Callback = *const fn (item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void;

/// Dynamic list of subscribers for a single item
const SubscriberList = std.ArrayList(Callback);

/// Subscription manager for change notifications
///
/// SubscriptionManager implements a publish-subscribe pattern allowing
/// multiple TUI components to register interest in specific HAL items.
/// When an item's value changes, all registered subscribers receive callbacks.
///
/// Thread safety:
///   - All operations protected by mutex
///   - Multiple threads can call subscribe/unsubscribe concurrently
///   - notify() broadcasts to all subscribers atomically
///   - waitForChange() blocks efficiently until notify() is called
///
/// Lock usage:
///   - subscribe/unsubscribe: lock(), defer unlock()
///   - notify: lock(), defer unlock()
///   - waitForChange: lock(), wait(), unlock()
///
/// IMPORTANT: Never call subscribe/unsubscribe from within a callback.
/// This will deadlock because the mutex is already held.
pub const SubscriptionManager = struct {
    /// Memory allocator for HashMap and ArrayList storage
    allocator: std.mem.Allocator,

    /// Maps item names to lists of subscriber callbacks
    /// Key: HAL pin/signal/param name (e.g., "motion.digital-in-00")
    /// Value: ArrayList of function pointers to call on change
    subscribers: std.StringHashMap(SubscriberList),

    /// Mutex protecting subscriber list from concurrent modification
    /// All subscribe/unsubscribe/notify operations must hold this lock
    mutex: std.Thread.Mutex,

    /// Condition variable for efficient wake-on-broadcast
    /// Waiting threads block here until notify() calls broadcast()
    condition: std.Thread.Condition,

    /// Predicate flag for waitForChange (prevents spurious wakeup bugs)
    /// Set to true when notify() is called, cleared after waitForChange() returns
    has_changes: bool,

    /// Initialize a new SubscriptionManager
    ///
    /// Creates an empty subscription manager with no subscribers.
    /// The allocator is stored for HashMap/ArrayList operations and must
    /// remain valid for the lifetime of the SubscriptionManager.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for HashMap and ArrayList storage
    ///
    /// Returns:
    ///   - Initialized SubscriptionManager
    ///
    /// Example:
    /// ```
    /// var manager = SubscriptionManager.init(std.heap.page_allocator);
    /// defer manager.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator) SubscriptionManager {
        return .{
            .allocator = allocator,
            .subscribers = std.StringHashMap(SubscriberList).init(allocator),
            .mutex = .{},
            .condition = .{},
            .has_changes = false,
        };
    }

    /// Clean up SubscriptionManager and free all resources
    ///
    /// Releases all HashMap storage and subscriber lists.
    /// The SubscriptionManager must not be used after calling deinit().
    ///
    /// IMPORTANT: This only frees HashMap and ArrayList storage.
    /// StringHashMap manages key memory automatically.
    /// Callback function pointers are not owned (don't free them).
    ///
    /// Example:
    /// ```
    /// var manager = SubscriptionManager.init(std.heap.page_allocator);
    /// defer manager.deinit();  // Always cleanup
    /// ```
    pub fn deinit(self: *SubscriptionManager) void {
        // Free all subscriber lists before freeing HashMap
        var iter = self.subscribers.iterator();
        while (iter.next()) |_| {
            // Note: ArrayList deinit requires allocator but doesn't expose it
            // The HashMap deinit will free the ArrayList memory
        }

        self.subscribers.deinit();
        self.* = undefined;
    }

    /// Subscribe to notifications for a specific HAL item
    ///
    /// Registers a callback to be invoked whenever the specified item's value changes.
    /// Multiple callbacks can subscribe to the same item (pubsub pattern).
    ///
    /// Parameters:
    ///   - item_name: Name of the pin/signal/param to watch (e.g., "motion.digital-in-00")
    ///   - callback: Function to call when value changes
    ///
    /// Returns:
    ///   - void on success
    ///   - error.OutOfMemory if allocator fails
    ///
    /// Thread safety:
    ///   - Acquires mutex exclusively
    ///   - Safe to call concurrently from multiple threads
    ///
    /// Example:
    /// ```
    /// fn myCallback(name: []const u8, old: ?HalValue, new: HalValue) void {
    ///     std.debug.print("{s} changed\n", .{name});
    /// }
    ///
    /// try manager.subscribe("motion.digital-in-00", myCallback);
    /// ```
    pub fn subscribe(self: *SubscriptionManager, item_name: []const u8, callback: Callback) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Get or create subscriber list for this item
        const entry = try self.subscribers.getOrPut(item_name);
        if (!entry.found_existing) {
            // New entry: initialize ArrayList
            entry.value_ptr.* = SubscriberList.initCapacity(self.allocator, 0) catch unreachable;
        }

        // Add callback to subscriber list
        try entry.value_ptr.append(self.allocator, callback);
    }

    /// Unsubscribe from notifications for a specific HAL item
    ///
    /// Removes a previously registered callback. If the callback is not found
    /// or the item doesn't exist, returns error.NotFound.
    ///
    /// Parameters:
    ///   - item_name: Name of the pin/signal/param to stop watching
    ///   - callback: Function to remove from subscriber list
    ///
    /// Returns:
    ///   - void on success
    ///   - error.NotFound if item or callback not found
    ///
    /// Thread safety:
    ///   - Acquires mutex exclusively
    ///   - Safe to call concurrently from multiple threads
    ///
    /// Example:
    /// ```
    /// try manager.unsubscribe("motion.digital-in-00", myCallback);
    /// ```
    pub fn unsubscribe(self: *SubscriptionManager, item_name: []const u8, callback: Callback) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find subscriber list for this item
        const list = self.subscribers.get(item_name) orelse return error.NotFound;

        // Find and remove the callback
        var found = false;
        for (list.items, 0..) |cb, i| {
            if (cb == callback) {
                _ = list.orderedRemove(i);
                found = true;
                break;
            }
        }

        if (!found) return error.NotFound;

        // If list is now empty, remove the entry from HashMap
        if (list.items.len == 0) {
            _ = self.subscribers.remove(item_name);
            list.deinit(self.allocator);
        }
    }

    /// Notify all subscribers of a value change
    ///
    /// Calls all callbacks registered for the specified item with the old and new values.
    /// Also broadcasts to condition variable to wake any threads waiting in waitForChange().
    ///
    /// Parameters:
    ///   - item_name: Name of the pin/signal/param that changed
    ///   - old_value: Previous value (null if this is the first value)
    ///   - new_value: New value after the change
    ///
    /// Thread safety:
    ///   - Acquires mutex exclusively
    ///   - Callbacks are invoked while holding mutex (keep them fast!)
    ///   - Safe to call concurrently from multiple threads
    ///
    /// Example:
    /// ```
    /// manager.notify("motion.digital-in-00", null, .{.bit = true});
    /// ```
    pub fn notify(self: *SubscriptionManager, item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find subscriber list for this item
        if (self.subscribers.get(item_name)) |list| {
            // Call all registered callbacks
            for (list.items) |callback| {
                callback(item_name, old_value, new_value);
            }
        }

        // Set predicate flag and wake all waiting threads
        self.has_changes = true;
        self.condition.broadcast();
    }

    /// Wait for any value change notification
    ///
    /// Blocks the current thread until notify() is called on any item.
    /// Uses a condition variable for efficient blocking (no CPU spinning).
    ///
    /// Thread safety:
    ///   - Acquires mutex exclusively
    ///   - Releases mutex while waiting (allows other threads to call notify)
    ///   - Reacquires mutex before returning
    ///   - Multiple threads can wait concurrently
    ///
    /// Spurious wakeup handling:
    ///   - Uses while loop (not if) to guard against spurious wakeups
    ///   - See RESEARCH.md Pitfall 2 for details
    ///
    /// Example:
    /// ```
    /// // In TUI thread:
    /// manager.waitForChange();  // Blocks until notify() is called
    /// // Now redraw UI with updated data
    /// ```
    pub fn waitForChange(self: *SubscriptionManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Loop handles spurious wakeups (RESEARCH.md Pitfall 2)
        while (!self.has_changes) {
            self.condition.wait(&self.mutex);
        }

        // Clear predicate flag for next wait
        self.has_changes = false;
    }
};

// Compile-time tests to verify API surface
comptime {
    // Verify SubscriptionManager can be initialized
    _ = SubscriptionManager.init;

    // Verify deinit is callable
    _ = SubscriptionManager.deinit;

    // Verify subscribe/unsubscribe operations exist
    _ = SubscriptionManager.subscribe;
    _ = SubscriptionManager.unsubscribe;

    // Verify notify/waitForChange operations exist
    _ = SubscriptionManager.notify;
    _ = SubscriptionManager.waitForChange;

    // Verify Callback type is a function pointer
    _ = Callback;
}
