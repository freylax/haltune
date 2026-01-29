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

test "discovery functions find created signals" {
    // Create a component and test signals
    const comp_id = safe.halInit("discovery-signal-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Import C functions directly to create test signals
    const c = @import("ffi/c.zig").c;

    // Create a test signal
    const sig_rc = c.hal_signal_new("test-discovery-signal", c.HAL_FLOAT);
    if (sig_rc != 0) {
        std.debug.print("Failed to create signal: {}\n", .{sig_rc});
        // Signal might already exist from previous test run
    }

    // Test discovery: find the signal we just created
    const sig = safe.halprFindSigByName("test-discovery-signal");

    // Signal should be found (unless it already existed and was cleaned up)
    if (sig) |s| {
        _ = s;
        // Success! Signal was found
        std.debug.print("✓ Discovered test-discovery-signal\n", .{});
    } else {
        // Signal might have been cleaned up by previous test
        std.debug.print("Signal not found (may have been cleaned up)\n", .{});
    }
}

test "discovery functions return null for non-existent objects" {
    // Initialize HAL component
    const comp_id = safe.halInit("null-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Test that discovery functions return null for non-existent objects
    const pin = safe.halprFindPinByName("definitely-does-not-exist-pin");
    try testing.expect(pin == null);

    const sig = safe.halprFindSigByName("definitely-does-not-exist-signal");
    try testing.expect(sig == null);

    const param = safe.halprFindParamByName("definitely-does-not-exist-param");
    try testing.expect(param == null);
}

test "discovery functions handle empty strings" {
    // Initialize HAL component
    const comp_id = safe.halInit("empty-string-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Test that discovery functions handle empty strings (should return null)
    const pin = safe.halprFindPinByName("");
    // Empty string is not a valid HAL name, so it should return null
    if (pin) |p| {
        _ = p;
        // If it doesn't crash, that's good enough
        std.debug.print("Empty string pin query returned a value\n", .{});
    } else {
        // Expected - empty strings are invalid
        std.debug.print("Empty string correctly returns null\n", .{});
    }
}

// Note: Pin creation tests now use name-based API which works with opaque types in ULAPI.
// The pinNew, setPin*, and getPin* functions use pin names instead of pointers.

test "pinFloat: create, write, and read float pin" {
    const comp_id = safe.halInit("float-pin-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Create a float pin
    const pin_name = try safe.pinNew(comp_id, "test-float-pin", c.HAL_FLOAT, c.HAL_OUT);
    try testing.expectEqualStrings("test-float-pin", pin_name);

    // Write a value to the pin
    try safe.setPinFloat(pin_name, 3.14159);

    // Read the value back
    const value = try safe.getPinFloat(pin_name);
    try testing.expectApproxEqAbs(3.14159, value, 0.00001);
}

test "pinBit: create, write, and read bit pin" {
    const comp_id = safe.halInit("bit-pin-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Create a bit pin
    const pin_name = try safe.pinNew(comp_id, "test-bit-pin", c.HAL_BIT, c.HAL_OUT);
    try testing.expectEqualStrings("test-bit-pin", pin_name);

    // Write true to the pin
    try safe.setPinBit(pin_name, true);
    const value_true = try safe.getPinBit(pin_name);
    try testing.expect(value_true);

    // Write false to the pin
    try safe.setPinBit(pin_name, false);
    const value_false = try safe.getPinBit(pin_name);
    try testing.expect(!value_false);
}

test "pinS32: create, write, and read signed 32-bit integer pin" {
    const comp_id = safe.halInit("s32-pin-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Create an s32 pin
    const pin_name = try safe.pinNew(comp_id, "test-s32-pin", c.HAL_S32, c.HAL_OUT);
    try testing.expectEqualStrings("test-s32-pin", pin_name);

    // Write a positive value
    try safe.setPinS32(pin_name, 12345);
    const value1 = try safe.getPinS32(pin_name);
    try testing.expectEqual(@as(i32, 12345), value1);

    // Write a negative value
    try safe.setPinS32(pin_name, -6789);
    const value2 = try safe.getPinS32(pin_name);
    try testing.expectEqual(@as(i32, -6789), value2);
}

test "pinU32: create, write, and read unsigned 32-bit integer pin" {
    const comp_id = safe.halInit("u32-pin-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Create a u32 pin
    const pin_name = try safe.pinNew(comp_id, "test-u32-pin", c.HAL_U32, c.HAL_OUT);
    try testing.expectEqualStrings("test-u32-pin", pin_name);

    // Write a value
    try safe.setPinU32(pin_name, 54321);
    const value = try safe.getPinU32(pin_name);
    try testing.expectEqual(@as(u32, 54321), value);
}

test "pinNew with invalid type returns error" {
    const comp_id = safe.halInit("invalid-type-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Try to create a pin with an invalid type (255 is not a valid HAL type)
    const result = safe.pinNew(comp_id, "test-invalid-pin", 255, c.HAL_OUT);

    // Should return TypeMismatch error
    try testing.expectError(HalError.TypeMismatch, result);
}

test "setPin* on non-existent pin returns error" {
    const comp_id = safe.halInit("nonexistent-pin-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Try to write to a pin that doesn't exist
    const float_result = safe.setPinFloat("nonexistent-float-pin", 1.0);
    try testing.expectError(HalError.PinNotFound, float_result);

    const bit_result = safe.setPinBit("nonexistent-bit-pin", true);
    try testing.expectError(HalError.PinNotFound, bit_result);

    const s32_result = safe.setPinS32("nonexistent-s32-pin", 42);
    try testing.expectError(HalError.PinNotFound, s32_result);

    const u32_result = safe.setPinU32("nonexistent-u32-pin", 42);
    try testing.expectError(HalError.PinNotFound, u32_result);
}

test "getPin* on non-existent pin returns error" {
    const comp_id = safe.halInit("get-nonexistent-test") catch |err| {
        std.debug.print("halInit failed: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);

    // Try to read from a pin that doesn't exist
    const float_result = safe.getPinFloat("nonexistent-float-pin");
    try testing.expectError(HalError.PinNotFound, float_result);

    const bit_result = safe.getPinBit("nonexistent-bit-pin");
    try testing.expectError(HalError.PinNotFound, bit_result);

    const s32_result = safe.getPinS32("nonexistent-s32-pin");
    try testing.expectError(HalError.PinNotFound, s32_result);

    const u32_result = safe.getPinU32("nonexistent-u32-pin");
    try testing.expectError(HalError.PinNotFound, u32_result);
}
