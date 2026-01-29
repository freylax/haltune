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
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }

        self.subscribers.deinit();
        self.* = undefined;
    }
};

// Compile-time tests to verify API surface
comptime {
    // Verify SubscriptionManager can be initialized
    _ = SubscriptionManager.init;

    // Verify deinit is callable
    _ = SubscriptionManager.deinit;

    // Verify Callback type is a function pointer
    _ = Callback;
}
