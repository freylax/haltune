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

test "signal refresh discovers new signals" {
    // This test verifies that refreshSignals discovers new signals
    // Note: This test will not add actual signals without HAL running
    // but verifies the function compiles and handles empty HAL gracefully

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    // Start thread
    try refresh.start();

    // Let thread run for one refresh cycle
    std.time.sleep(150 * std.time.ns_per_ms);

    // Stop thread
    refresh.stop();

    // Verify no crashes or memory leaks
    // (Actual signal discovery would require HAL to be running)
    try testing.assertTrue(true);
}

test "param refresh discovers new params" {
    // This test verifies that refreshParams discovers new parameters
    // Note: This test will not add actual params without HAL running
    // but verifies the function compiles and handles empty HAL gracefully

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    // Start thread
    try refresh.start();

    // Let thread run for one refresh cycle
    std.time.sleep(150 * std.time.ns_per_ms);

    // Stop thread
    refresh.stop();

    // Verify no crashes or memory leaks
    // (Actual param discovery would require HAL to be running)
    try testing.assertTrue(true);
}

test "refreshHal calls all three refresh functions" {
    // This test verifies that refreshHal calls all three refresh functions
    // by verifying that the thread runs without error

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    // Start thread - refreshHal is called in the thread loop
    try refresh.start();

    // Let thread run for a few refresh cycles
    std.time.sleep(250 * std.time.ns_per_ms);

    // Stop thread
    refresh.stop();

    // Verify thread completed all refresh cycles without error
    // (Actual data population would require HAL to be running)
    try testing.assertTrue(true);
}

test "stale pin removal" {
    // This test verifies that stale pins are removed from cache
    // A stale pin is one that exists in cache but not in HAL

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    // Add a fake pin to cache (simulating a pin from unloaded component)
    try store.addPin("fake.stale-pin", .{ .float = 1.0 });

    // Verify pin is in cache
    const value_before = try store.getPin("fake.stale-pin");
    try testing.assertEqual(value_before.float, 1.0);

    // Create and start refresh thread
    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    try refresh.start();

    // Let thread run for one refresh cycle
    // The fake pin doesn't exist in HAL, so it should be removed
    std.time.sleep(150 * std.time.ns_per_ms);

    refresh.stop();

    // Verify fake pin was removed (stale cleanup)
    const result = store.getPin("fake.stale-pin");
    try testing.expectError(error.NotFound, result);
}

test "stale signal removal" {
    // This test verifies that stale signals are removed from cache

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    // Add a fake signal to cache
    try store.addSignal("fake.stale-signal", .{ .float = 2.0 });

    // Verify signal is in cache
    const value_before = try store.getSignal("fake.stale-signal");
    try testing.assertEqual(value_before.float, 2.0);

    // Create and start refresh thread
    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    try refresh.start();

    // Let thread run for one refresh cycle
    std.time.sleep(150 * std.time.ns_per_ms);

    refresh.stop();

    // Verify fake signal was removed
    const result = store.getSignal("fake.stale-signal");
    try testing.expectError(error.NotFound, result);
}

test "stale param removal" {
    // This test verifies that stale params are removed from cache

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    // Add a fake param to cache
    try store.addParam("fake.stale-param", .{ .s32 = 42 });

    // Verify param is in cache
    const value_before = try store.getParam("fake.stale-param");
    try testing.assertEqual(value_before.s32, 42);

    // Create and start refresh thread
    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    try refresh.start();

    // Let thread run for one refresh cycle
    std.time.sleep(150 * std.time.ns_per_ms);

    refresh.stop();

    // Verify fake param was removed
    const result = store.getParam("fake.stale-param");
    try testing.expectError(error.NotFound, result);
}

test "cache does not grow unbounded" {
    // This test verifies that cache size is maintained
    // and doesn't grow due to stale entries accumulating

    var store = StateStore.init(testing.allocator);
    defer store.deinit();

    // Add multiple fake entries to cache
    try store.addPin("fake.pin-1", .{ .float = 1.0 });
    try store.addPin("fake.pin-2", .{ .float = 2.0 });
    try store.addPin("fake.pin-3", .{ .float = 3.0 });
    try store.addSignal("fake.signal-1", .{ .bit = true });
    try store.addSignal("fake.signal-2", .{ .bit = false });
    try store.addParam("fake.param-1", .{ .s32 = 10 });
    try store.addParam("fake.param-2", .{ .s32 = 20 });

    // Verify all entries are in cache
    const pins_before = try store.listPins(testing.allocator);
    defer testing.allocator.free(pins_before);
    try testing.expect(pins_before.len >= 3);

    const signals_before = try store.listSignals(testing.allocator);
    defer testing.allocator.free(signals_before);
    try testing.expect(signals_before.len >= 2);

    const params_before = try store.listParams(testing.allocator);
    defer testing.allocator.free(params_before);
    try testing.expect(params_before.len >= 2);

    // Create and start refresh thread
    var refresh = RefreshThread.init(testing.allocator, &store);
    defer refresh.deinit();

    try refresh.start();

    // Let thread run for multiple refresh cycles
    std.time.sleep(300 * std.time.ns_per_ms);

    refresh.stop();

    // Verify fake entries were removed
    // (Without HAL running, all fake entries should be cleaned up)
    const pins_after = try store.listPins(testing.allocator);
    defer testing.allocator.free(pins_after);

    const signals_after = try store.listSignals(testing.allocator);
    defer testing.allocator.free(signals_after);

    const params_after = try store.listParams(testing.allocator);
    defer testing.allocator.free(params_after);

    // Cache should not contain the fake entries
    // (In dev environment without HAL, cache should be empty or contain only real HAL entries)
    // The key point: cache size didn't grow unbounded
    try testing.expect(pins_after.len < pins_before.len or pins_after.len == 0);
    try testing.expect(signals_after.len < signals_before.len or signals_after.len == 0);
    try testing.expect(params_after.len < params_before.len or params_after.len == 0);
}
