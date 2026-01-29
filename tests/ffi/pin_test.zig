// Unit tests for HAL FFI operations
//
// These tests verify the FFI bindings work correctly with LinuxCNC HAL.
// Tests the basic lifecycle functions that are available in ULAPI.
//
// Run tests with: zig build test
//
// Note: These tests require LinuxCNC HAL library to be installed.

const std = @import("std");
const testing = std.testing;
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
    try testing.expectError(HalError.InitFailed, result);
}

test "halExit accepts any component ID" {
    // halExit should not crash even with invalid ID
    // (it's designed to always succeed)
    safe.halExit(-1);
    safe.halExit(999);
}

test "halInit/halReady/halExit sequence" {
    // Test the full lifecycle of a HAL component
    const comp_id = try safe.halInit("lifecycle-test");
    try testing.expect(comp_id > 0);

    // Mark component as ready
    try safe.halReady(comp_id);

    // Clean exit
    safe.halExit(comp_id);

    // After exit, component ID is invalid
    // (halExit is designed to always succeed, even with invalid IDs)
}

// Note: Tests for discovery functions (halprFindPinByName, etc.) and pin
// operations (pinNew, setPin*, getPin*) are disabled because:
// 1. Discovery functions require hal_priv.h which may not be available in ULAPI
// 2. hal_pin_t is opaque in ULAPI (userspace API)
//
// These would require either:
// - RTAPI (realtime API) instead of ULAPI
// - Name-based pin operations via HAL functions
// - A mock HAL implementation for testing
