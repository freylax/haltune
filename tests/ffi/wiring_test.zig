// Wiring save/restore tests
//
// Test-driven development for HAL signal connection save/restore

const std = @import("std");
const testing = std.testing;

const wiring = @import("ffi/wiring.zig");

test "Wiring: save and restore connection" {
    // Initially no connection
    const state = try wiring.saveConnection("test-pin", testing.allocator);
    defer wiring.freeWiringState(state, testing.allocator);

    // In mock environment, no pin exists - returns null
    try testing.expect(state == null);
}

test "Wiring: WiringState struct compiles" {
    // Verify the WiringState struct compiles correctly
    const state = wiring.WiringState{
        .pin_name = "test-pin",
        .old_signal = null,
    };
    try testing.expectEqualStrings("test-pin", state.pin_name);
}

test "Wiring: connectPin and disconnectPin compile" {
    // These will fail in mock environment but verify the API compiles
    const result = wiring.connectPin("test-pin", "test-signal");
    // In mock environment, this will fail
    _ = result catch |err| {
        // Expected to fail in mock environment
        try testing.expect(err == error.LinkFailed);
    };

    const result2 = wiring.disconnectPin("test-pin");
    _ = result2 catch |err| {
        try testing.expect(err == error.UnlinkFailed);
    };
}

