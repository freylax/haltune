// Unit tests for HAL FFI operations
//
// These tests verify the FFI bindings work correctly with LinuxCNC HAL.
// Note: Pin creation/read/write functions are disabled in ULAPI because
// hal_pin_t is an opaque type in userspace API.
//
// Run tests with: zig build test
//
// Note: These tests require LinuxCNC HAL library to be installed.

const std = @import("std");
const testing = std.testing;
const c = @import("ffi/c.zig").c;
const safe = @import("ffi/safe.zig");
const HalError = @import("ffi/errors.zig").HalError;

test "HAL init and ready" {
    // Test that halInit creates a component
    const comp_id = safe.halInit("test-component") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);

    // Verify component ID is positive (success)
    try testing.expect(comp_id > 0);

    // Test that halReady marks the component as ready
    try safe.halReady(comp_id);
}

test "halInit with duplicate name fails" {
    // First component should succeed
    const comp_id1 = safe.halInit("duplicate-test") catch |err| {
        std.debug.print("First halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id1);

    // Second component with same name should fail
    const result = safe.halInit("duplicate-test");

    // Should return an error (component name already exists)
    try testing.expectError(error.InitFailed, result);
}

test "halExit accepts any component ID" {
    // halExit should not crash even with invalid ID
    // (it's designed to always succeed)
    safe.halExit(-1);
    safe.halExit(999);
}

test "discovery functions return null for non-existent pins" {
    // These tests verify the discovery API compiles and works
    // They don't require a live HAL instance

    // halprFindPinByName should return null for non-existent pin
    const pin = safe.halprFindPinByName("non-existent-pin-xyz123");
    try testing.expect(pin == null);
}

test "discovery functions accept null parameter" {
    // halprFindPinByName with null should return first pin or null
    // (depends on whether HAL is running)
    const pin = safe.halprFindPinByName(null);

    // We can't assert much here without knowing HAL state
    // Just verify the function compiles and doesn't crash
    _ = pin;
}

test "halInit/halReady/halExit sequence" {
    // Test the full lifecycle of a HAL component
    const comp_id = try safe.halInit("lifecycle-test");
    try testing.expect(comp_id > 0);

    // Component should not be ready yet
    // (can't test this directly without calling halReady)

    // Mark component as ready
    try safe.halReady(comp_id);

    // Clean exit
    safe.halExit(comp_id);

    // After exit, component ID is invalid
    // (halExit is designed to always succeed, even with invalid IDs)
}

// Note: Tests for pinNew, setPin*, getPin* are disabled because
// hal_pin_t is opaque in ULAPI (userspace API). These functions
// would require direct access to hal_pin_t internals which are
// not available in userspace components.
//
// To test pin operations, we would need to:
// 1. Use the RTAPI (realtime API) instead of ULAPI
// 2. Or implement name-based pin operations via HAL functions
// 3. Or test against a mock HAL implementation
