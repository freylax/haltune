// Unit tests for RefreshThread
//
// This test suite verifies the refresh thread lifecycle, timing, and
// memory ordering semantics.

const std = @import("std");
const testing = std.testing;

const RefreshThread = @import("../../src/state/refresh.zig").RefreshThread;
const StateStore = @import("../../src/state/cache.zig").StateStore;

test "start and stop" {
    // Create StateStore with testing allocator
    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    // Create RefreshThread
    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    // Start the thread
    try refresh.start();

    // Verify thread is running (give it a moment to start)
    std.time.sleep(10 * std.time.ns_per_ms);
    try testing.assertTrue(refresh.running.load(.monotonic));

    // Stop the thread
    refresh.stop();

    // Verify thread has stopped
    try testing.assertFalse(refresh.running.load(.monotonic));
}

test "interval configuration" {
    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    // Default interval should be 100ms
    try testing.assertEqual(refresh.interval_ns, 100 * std.time.ns_per_ms);

    // Change to 50ms
    refresh.setInterval(50);
    try testing.assertEqual(refresh.interval_ns, 50 * std.time.ns_per_ms);

    // Change to 200ms
    refresh.setInterval(200);
    try testing.assertEqual(refresh.interval_ns, 200 * std.time.ns_per_ms);
}

test "memory ordering" {
    // This test verifies that the running flag uses proper memory ordering
    // to ensure visibility across threads

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    // Start thread in background
    try refresh.start();

    // Give thread time to start running
    std.time.sleep(10 * std.time.ns_per_ms);

    // Set running flag to false from main thread
    // Using .release to ensure visibility
    refresh.running.store(false, .release);

    // Wait for thread to exit
    // The thread should see the change via .acquire and exit
    refresh.thread.join();

    // Verify thread stopped
    try testing.assertFalse(refresh.running.load(.acquire));
}

test "refresh without HAL" {
    // This test verifies that refreshHal handles errors gracefully
    // when HAL is not available (dev environment)

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    // Start thread - it will fail to read from HAL but shouldn't crash
    try refresh.start();

    // Let it run for a bit
    std.time.sleep(50 * std.time.ns_per_ms);

    // Stop thread cleanly
    refresh.stop();

    // Verify no memory leaks (testing.allocator will catch them)
    try testing.assertTrue(true);
}
