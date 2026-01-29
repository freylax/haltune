// Unit tests for HAL pin operations
//
// These tests verify pin creation, reading, writing, and type safety.
//
// Run tests with: zig build test
//
// Note: These tests require LinuxCNC HAL library to be installed.

const std = @import("std");
const testing = std.testing;
const c = @import("ffi/c.zig").c;
const safe = @import("ffi/safe.zig");
const hal_pin_dir_t = @import("ffi/types.zig").hal_pin_dir_t;

// Helper function to initialize HAL for testing
fn initTestComponent() !c_int {
    const comp_id = try safe.halInit("pin-test-component");
    errdefer safe.halExit(comp_id);
    _ = try safe.halReady(comp_id);
    return comp_id;
}

test "pinFloatNew creates float pin and returns pointer" {
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create float pin
    const pin = try safe.pinFloatNew(comp_id, "test-float-pin", hal_pin_dir_t.HAL_OUT);

    // Verify pin is not null
    try testing.expect(pin != null);

    // Write value
    pin.* = 3.14159;

    // Read back
    const value = pin.*;
    try testing.expectEqual(3.14159, value);
}

test "pinBitNew creates bit pin and returns pointer" {
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create bit pin
    const pin = try safe.pinBitNew(comp_id, "test-bit-pin", hal_pin_dir_t.HAL_OUT);

    // Verify pin is not null
    try testing.expect(pin != null);

    // Write true
    pin.* = 1;
    try testing.expectEqual(@as(u8, 1), pin.*);

    // Write false
    pin.* = 0;
    try testing.expectEqual(@as(u8, 0), pin.*);
}

test "pinS32New creates s32 pin and returns pointer" {
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create s32 pin
    const pin = try safe.pinS32New(comp_id, "test-s32-pin", hal_pin_dir_t.HAL_OUT);

    // Verify pin is not null
    try testing.expect(pin != null);

    // Write value
    pin.* = -12345;

    // Read back
    try testing.expectEqual(@as(i32, -12345), pin.*);
}

test "pinU32New creates u32 pin and returns pointer" {
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create u32 pin
    const pin = try safe.pinU32New(comp_id, "test-u32-pin", hal_pin_dir_t.HAL_OUT);

    // Verify pin is not null
    try testing.expect(pin != null);

    // Write value
    pin.* = 54321;

    // Read back
    try testing.expectEqual(@as(u32, 54321), pin.*);
}

test "pin direction - HAL_IN" {
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create input pin
    const pin = try safe.pinFloatNew(comp_id, "test-input-pin", hal_pin_dir_t.HAL_IN);

    // Verify pin was created
    try testing.expect(pin != null);

    // Should be able to write to it (component sets input pins)
    pin.* = 1.23;
}

test "pin direction - HAL_IO" {
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create IO pin
    const pin = try safe.pinFloatNew(comp_id, "test-io-pin", hal_pin_dir_t.HAL_IO);

    // Verify pin was created
    try testing.expect(pin != null);

    // Should be able to write to it
    pin.* = 4.56;
}

test "multiple pins same component" {
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create multiple pins of different types
    const float_pin = try safe.pinFloatNew(comp_id, "multi-float", hal_pin_dir_t.HAL_OUT);
    const bit_pin = try safe.pinBitNew(comp_id, "multi-bit", hal_pin_dir_t.HAL_OUT);
    const s32_pin = try safe.pinS32New(comp_id, "multi-s32", hal_pin_dir_t.HAL_OUT);
    const u32_pin = try safe.pinU32New(comp_id, "multi-u32", hal_pin_dir_t.HAL_OUT);

    // Write values to all pins
    float_pin.* = 1.0;
    bit_pin.* = 1;
    s32_pin.* = 100;
    u32_pin.* = 200;

    // Read back and verify
    try testing.expectEqual(1.0, float_pin.*);
    try testing.expectEqual(@as(u8, 1), bit_pin.*);
    try testing.expectEqual(@as(i32, 100), s32_pin.*);
    try testing.expectEqual(@as(u32, 200), u32_pin.*);
}

test "concurrent pin writes - basic sanity check" {
    const comp_id = try initTestComponent();
    defer safe.halExit(comp_id);

    // Create multiple pins
    const pin1 = try safe.pinFloatNew(comp_id, "concurrent-1", hal_pin_dir_t.HAL_OUT);
    const pin2 = try safe.pinFloatNew(comp_id, "concurrent-2", hal_pin_dir_t.HAL_OUT);
    const pin3 = try safe.pinFloatNew(comp_id, "concurrent-3", hal_pin_dir_t.HAL_OUT);

    // Write to all pins rapidly
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        pin1.* = @as(f64, @floatFromInt(i));
        pin2.* = @as(f64, @floatFromInt(i)) * 2.0;
        pin3.* = @as(f64, @floatFromInt(i)) * 3.0;
    }

    // Verify final values
    try testing.expectEqual(@as(f64, 99), pin1.*);
    try testing.expectEqual(@as(f64, 198), pin2.*);
    try testing.expectEqual(@as(f64, 297), pin3.*);
}
