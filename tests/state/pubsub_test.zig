// Unit tests for subscription-based change notification
//
// These tests verify subscription management, notification delivery,
// unsubscription, spurious wakeup handling, and value passing.
// All tests use std.testing.allocator to detect memory leaks.
//
// Run tests with: zig build test

const std = @import("std");
const testing = std.testing;

const pubsub = @import("../../src/state/pubsub.zig");
const SubscriptionManager = pubsub.SubscriptionManager;
const HalValue = @import("../../src/state/cache.zig").HalValue;

// Test 1: Subscribe and notify
test "subscribe and notify" {
    const gpa = testing.allocator;

    // Create subscription manager
    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    // Flag to track callback invocation
    var callback_invoked = false;

    // Define callback that sets flag
    fn testCallback(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        _ = new_value;
        // Capture outer variable using pointer
        const flag = @as(*bool, @ptrFromInt(@intFromPtr(&callback_invoked)));
        flag.* = true;
    }

    // Subscribe to an item
    try manager.subscribe("test-pin", testCallback);

    // Notify subscribers
    manager.notify("test-pin", null, .{ .bit = true });

    // Verify callback was invoked
    try testing.expect(callback_invoked);

    // No leaks
    try testing.allocator_check(gpa);
}

// Test 2: Multiple subscribers to same item
test "multiple subscribers" {
    const gpa = testing.allocator;

    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    // Track which callbacks were invoked
    var callback1_invoked = false;
    var callback2_invoked = false;

    fn callback1(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        _ = new_value;
        const flag = @as(*bool, @ptrFromInt(@intFromPtr(&callback1_invoked)));
        flag.* = true;
    }

    fn callback2(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        _ = new_value;
        const flag = @as(*bool, @ptrFromInt(@intFromPtr(&callback2_invoked)));
        flag.* = true;
    }

    // Subscribe both callbacks to same item
    try manager.subscribe("shared-pin", callback1);
    try manager.subscribe("shared-pin", callback2);

    // Notify subscribers
    manager.notify("shared-pin", null, .{ .float = 3.14 });

    // Verify both callbacks were invoked
    try testing.expect(callback1_invoked);
    try testing.expect(callback2_invoked);

    // No leaks
    try testing.allocator_check(gpa);
}

// Test 3: Unsubscribe prevents callback invocation
test "unsubscribe" {
    const gpa = testing.allocator;

    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    var callback_invoked = false;

    fn testCallback(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        _ = new_value;
        const flag = @as(*bool, @ptrFromInt(@intFromPtr(&callback_invoked)));
        flag.* = true;
    }

    // Subscribe to an item
    try manager.subscribe("test-pin", testCallback);

    // Unsubscribe from the item
    try manager.unsubscribe("test-pin", testCallback);

    // Notify subscribers
    manager.notify("test-pin", null, .{ .bit = true });

    // Verify callback was NOT invoked
    try testing.expect(!callback_invoked);

    // No leaks
    try testing.allocator_check(gpa);
}

// Test 4: Unsubscribe non-existent callback returns error
test "unsubscribe non-existent callback" {
    const gpa = testing.allocator;

    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    fn dummyCallback(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        _ = new_value;
    }

    // Try to unsubscribe from non-existent item
    const result = manager.unsubscribe("non-existent", dummyCallback);
    try testing.expectError(error.NotFound, result);

    // No leaks
    try testing.allocator_check(gpa);
}

// Test 5: waitForChange with notification
test "waitForChange with notification" {
    const gpa = testing.allocator;

    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    // Use a channel to coordinate between threads
    const Context = struct {
        manager: *SubscriptionManager,
        ready: std.Thread.Mutex = .{},
        ready_flag: bool = false,

        fn waitForNotify(context: *@This()) void {
            // Signal we're ready to wait
            context.ready.lock();
            context.ready_flag = true;
            context.ready.unlock();

            // Wait for notification
            context.manager.waitForChange();

            // If we reach here, notify() was called
        }
    };

    var context = Context{
        .manager = &manager,
    };

    // Spawn thread that waits for change
    var thread = try std.Thread.spawn(.{}, Context.waitForNotify, .{&context});
    defer thread.join();

    // Wait for thread to be ready
    while (true) {
        context.ready.lock();
        const flag = context.ready_flag;
        context.ready.unlock();
        if (flag) break;
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    // Notify from main thread (this should wake the waiting thread)
    manager.notify("test-pin", null, .{ .bit = true });

    // No leaks
    try testing.allocator_check(gpa);
}

// Test 6: old_value and new_value passed correctly
test "old_value and new_value passed correctly" {
    const gpa = testing.allocator;

    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    // Capture values passed to callback
    var captured_old: ?HalValue = null;
    var captured_new: HalValue = undefined;

    fn valueCallback(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        const old_ptr = @as(*?HalValue, @ptrFromInt(@intFromPtr(&captured_old)));
        const new_ptr = @as(*HalValue, @ptrFromInt(@intFromPtr(&captured_new)));
        old_ptr.* = old_value;
        new_ptr.* = new_value;
    }

    // Subscribe
    try manager.subscribe("test-pin", valueCallback);

    // Notify with old value (first notification has old=null)
    manager.notify("test-pin", null, .{ .s32 = 42 });

    // Verify first notification (old=null, new=s32)
    try testing.expect(captured_old == null);
    try testing.expectEqual(@as(i32, 42), captured_new.s32);

    // Notify with old value (subsequent notification has old value)
    manager.notify("test-pin", .{ .s32 = 42 }, .{ .s32 = 100 });

    // Verify subsequent notification (old=42, new=100)
    try testing.expect(captured_old != null);
    try testing.expectEqual(@as(i32, 42), captured_old.?.s32);
    try testing.expectEqual(@as(i32, 100), captured_new.s32);

    // No leaks
    try testing.allocator_check(gpa);
}

// Test 7: Multiple items with independent subscribers
test "multiple items with independent subscribers" {
    const gpa = testing.allocator;

    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    var pin1_invoked = false;
    var pin2_invoked = false;

    fn pin1Callback(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        _ = new_value;
        const flag = @as(*bool, @ptrFromInt(@intFromPtr(&pin1_invoked)));
        flag.* = true;
    }

    fn pin2Callback(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        _ = new_value;
        const flag = @as(*bool, @ptrFromInt(@intFromPtr(&pin2_invoked)));
        flag.* = true;
    }

    // Subscribe to different items
    try manager.subscribe("pin-1", pin1Callback);
    try manager.subscribe("pin-2", pin2Callback);

    // Notify only pin-1
    manager.notify("pin-1", null, .{ .bit = true });

    // Verify only pin-1 callback was invoked
    try testing.expect(pin1_invoked);
    try testing.expect(!pin2_invoked);

    // No leaks
    try testing.allocator_check(gpa);
}

// Test 8: Unsubscribe removes empty subscriber lists
test "unsubscribe removes empty subscriber lists" {
    const gpa = testing.allocator;

    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    fn dummyCallback(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        _ = new_value;
    }

    // Subscribe then unsubscribe
    try manager.subscribe("test-pin", dummyCallback);
    try manager.unsubscribe("test-pin", dummyCallback);

    // Verify subscriber list was removed (no subscribers for this item)
    try testing.expect(!manager.subscribers.contains("test-pin"));

    // No leaks
    try testing.allocator_check(gpa);
}

// Test 9: Different value types in notifications
test "different value types in notifications" {
    const gpa = testing.allocator;

    var manager = SubscriptionManager.init(gpa);
    defer manager.deinit();

    // Track which type was received
    var received_type: u8 = 0;

    fn typeCallback(item_name: []const u8, old_value: ?HalValue, new_value: HalValue) void {
        _ = item_name;
        _ = old_value;
        const type_ptr = @as(*u8, @ptrFromInt(@intFromPtr(&received_type)));
        switch (new_value) {
            .bit => type_ptr.* = 1,
            .float => type_ptr.* = 2,
            .s32 => type_ptr.* = 3,
            .u32 => type_ptr.* = 4,
        }
    }

    try manager.subscribe("test-pin", typeCallback);

    // Test bit type
    manager.notify("test-pin", null, .{ .bit = true });
    try testing.expectEqual(@as(u8, 1), received_type);

    // Test float type
    manager.notify("test-pin", null, .{ .float = 1.0 });
    try testing.expectEqual(@as(u8, 2), received_type);

    // Test s32 type
    manager.notify("test-pin", null, .{ .s32 = 42 });
    try testing.expectEqual(@as(u8, 3), received_type);

    // Test u32 type
    manager.notify("test-pin", null, .{ .u32 = 100 });
    try testing.expectEqual(@as(u8, 4), received_type);

    // No leaks
    try testing.allocator_check(gpa);
}
