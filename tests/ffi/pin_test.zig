// Unit tests for HAL pin operations
//
// These tests verify pin creation, reading, writing, and type safety.
// All tests use std.testing.allocator to detect memory leaks.
//
// Run tests with: zig build test
//
// Note: These tests require LinuxCNC HAL library to be installed.

const std = @import("std");
const testing = std.testing;
const c = @import("ffi/c.zig").c;
const safe = @import("ffi/safe.zig");
const HalError = @import("ffi/errors.zig").HalError;

// Helper function to initialize HAL for testing
fn initTestComponent() !c_int {
    const comp_id = try safe.halInit("pin-test-component");
    errdefer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);
    return comp_id;
}

test "pin creation and cleanup" {
    const gpa = testing.allocator;

    // Initialize HAL component
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create a float pin (returns pin name, not pointer)
    const pin_name = try safe.pinNew(comp_id, "test-float-pin", c.HAL_FLOAT, c.HAL_OUT);

    // Verify pin name matches what we requested
    try testing.expectEqualStrings("test-float-pin", pin_name);

    // No leaks should be detected
    try testing.allocator_check(gpa);
}

test "pin write and read - float" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create float pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-float-write", c.HAL_FLOAT, c.HAL_OUT);

    // Write value
    const test_value: f64 = 3.14159;
    try safe.setPinFloat(pin_name, test_value);

    // Read back
    const read_value = try safe.getPinFloat(pin_name);

    // Verify value matches
    try testing.expectEqual(test_value, read_value);

    // No leaks
    try testing.allocator_check(gpa);
}

test "pin write and read - bit" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create bit pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-bit-write", c.HAL_BIT, c.HAL_OUT);

    // Write true
    try safe.setPinBit(pin_name, true);
    try testing.expectEqual(true, try safe.getPinBit(pin_name));

    // Write false
    try safe.setPinBit(pin_name, false);
    try testing.expectEqual(false, try safe.getPinBit(pin_name));

    // No leaks
    try testing.allocator_check(gpa);
}

test "pin write and read - s32" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create s32 pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-s32-write", c.HAL_S32, c.HAL_OUT);

    // Write value
    const test_value: i32 = -12345;
    try safe.setPinS32(pin_name, test_value);

    // Read back
    const read_value = try safe.getPinS32(pin_name);

    // Verify value matches
    try testing.expectEqual(test_value, read_value);

    // No leaks
    try testing.allocator_check(gpa);
}

test "pin write and read - u32" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create u32 pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-u32-write", c.HAL_U32, c.HAL_OUT);

    // Write value
    const test_value: u32 = 54321;
    try safe.setPinU32(pin_name, test_value);

    // Read back
    const read_value = try safe.getPinU32(pin_name);

    // Verify value matches
    try testing.expectEqual(test_value, read_value);

    // No leaks
    try testing.allocator_check(gpa);
}

test "type mismatch error - float pin with bit operation" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create float pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-float-mismatch", c.HAL_FLOAT, c.HAL_OUT);

    // Try to use bit operation on float pin - should return PinNotFound (wrong type)
    const result = safe.setPinBit(pin_name, true);

    // Verify error is returned
    try testing.expectError(HalError.PinNotFound, result);

    // No leaks
    try testing.allocator_check(gpa);
}

test "type mismatch error - bit pin with float operation" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create bit pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-bit-mismatch", c.HAL_BIT, c.HAL_OUT);

    // Try to use float operation on bit pin - should return PinNotFound (wrong type)
    const result = safe.setPinFloat(pin_name, 3.14);

    // Verify error is returned
    try testing.expectError(HalError.PinNotFound, result);

    // No leaks
    try testing.allocator_check(gpa);
}

test "type mismatch error - read wrong type" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create float pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-read-mismatch", c.HAL_FLOAT, c.HAL_OUT);

    // Try to read as s32 - should return PinNotFound (wrong type)
    const result = safe.getPinS32(pin_name);

    // Verify error is returned
    try testing.expectError(HalError.PinNotFound, result);

    // No leaks
    try testing.allocator_check(gpa);
}

test "pin direction - input pin" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create input pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-input-pin", c.HAL_FLOAT, c.HAL_IN);

    // Should be able to write to it (component sets input pins)
    try safe.setPinFloat(pin_name, 1.23);

    // No leaks
    try testing.allocator_check(gpa);
}

test "pin direction - IO pin" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create IO pin (returns pin name)
    const pin_name = try safe.pinNew(comp_id, "test-io-pin", c.HAL_FLOAT, c.HAL_IO);

    // Should be able to write to it
    try safe.setPinFloat(pin_name, 4.56);

    // No leaks
    try testing.allocator_check(gpa);
}

test "multiple pins same component" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create multiple pins of different types (returns pin names)
    const float_pin = try safe.pinNew(comp_id, "multi-float", c.HAL_FLOAT, c.HAL_OUT);
    const bit_pin = try safe.pinNew(comp_id, "multi-bit", c.HAL_BIT, c.HAL_OUT);
    const s32_pin = try safe.pinNew(comp_id, "multi-s32", c.HAL_S32, c.HAL_OUT);
    const u32_pin = try safe.pinNew(comp_id, "multi-u32", c.HAL_U32, c.HAL_OUT);

    // Write values to all pins
    try safe.setPinFloat(float_pin, 1.0);
    try safe.setPinBit(bit_pin, true);
    try safe.setPinS32(s32_pin, 100);
    try safe.setPinU32(u32_pin, 200);

    // Read back and verify
    try testing.expectEqual(1.0, try safe.getPinFloat(float_pin));
    try testing.expectEqual(true, try safe.getPinBit(bit_pin));
    try testing.expectEqual(@as(i32, 100), try safe.getPinS32(s32_pin));
    try testing.expectEqual(@as(u32, 200), try safe.getPinU32(u32_pin));

    // No leaks
    try testing.allocator_check(gpa);
}

test "concurrent pin writes - basic sanity check" {
    const gpa = testing.allocator;

    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create multiple pins (returns pin names)
    const pin1 = try safe.pinNew(comp_id, "concurrent-1", c.HAL_FLOAT, c.HAL_OUT);
    const pin2 = try safe.pinNew(comp_id, "concurrent-2", c.HAL_FLOAT, c.HAL_OUT);
    const pin3 = try safe.pinNew(comp_id, "concurrent-3", c.HAL_FLOAT, c.HAL_OUT);

    // Write to all pins rapidly (simulates concurrent access)
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try safe.setPinFloat(pin1, @as(f64, @floatFromInt(i)));
        try safe.setPinFloat(pin2, @as(f64, @floatFromInt(i)) * 2.0);
        try safe.setPinFloat(pin3, @as(f64, @floatFromInt(i)) * 3.0);
    }

    // Verify final values
    try testing.expectEqual(@as(f64, 99), try safe.getPinFloat(pin1));
    try testing.expectEqual(@as(f64, 198), try safe.getPinFloat(pin2));
    try testing.expectEqual(@as(f64, 297), try safe.getPinFloat(pin3));

    // No leaks
    try testing.allocator_check(gpa);
}
