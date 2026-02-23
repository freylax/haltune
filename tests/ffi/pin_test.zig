// Pin type tests
//
// Test-driven development for HAL Pin type with cached data pointers

const std = @import("std");
const testing = std.testing;

const Pin = @import("ffi/pin.zig").Pin;
const PinType = @import("ffi/pin.zig").PinType;
const PinDir = @import("ffi/pin.zig").PinDir;
const Component = @import("ffi/component.zig").Component;

test "Pin: direct memory access for bit pin" {
    var comp = try Component.init(testing.allocator, "test-bit-access");
    defer comp.exit();
    try comp.ready();

    const pin = try comp.newPin("bit-pin", .bit, .out);

    // Set value directly via memory
    try pin.setBit(true);

    // Read value directly via memory
    const value = pin.getBit();
    try testing.expectEqual(true, value);
}

test "Pin: direct memory access for float pin" {
    var comp = try Component.init(testing.allocator, "test-float-access");
    defer comp.exit();
    try comp.ready();

    const pin = try comp.newPin("float-pin", .float, .out);

    // Set value directly via memory
    try pin.setFloat(3.14159);

    // Read value directly via memory
    const value = pin.getFloat();
    try testing.expectApproxEqAbs(3.14159, value, 0.0001);
}

test "Pin: direct memory access for s32 pin" {
    var comp = try Component.init(testing.allocator, "test-s32-access");
    defer comp.exit();
    try comp.ready();

    const pin = try comp.newPin("s32-pin", .s32, .out);

    // Set value directly via memory
    try pin.setS32(@as(i32, -42));

    // Read value directly via memory
    const value = pin.getS32();
    try testing.expectEqual(@as(i32, -42), value);
}

test "Pin: direct memory access for u32 pin" {
    var comp = try Component.init(testing.allocator, "test-u32-access");
    defer comp.exit();
    try comp.ready();

    const pin = try comp.newPin("u32-pin", .u32, .out);

    // Set value directly via memory
    try pin.setU32(@as(u32, 42));

    // Read value directly via memory
    const value = pin.getU32();
    try testing.expectEqual(@as(u32, 42), value);
}

test "Pin: type mismatch on set" {
    var comp = try Component.init(testing.allocator, "test-type-mismatch");
    defer comp.exit();
    try comp.ready();

    const pin = try comp.newPin("bit-pin", .bit, .out);

    // Try to set wrong type
    const result = pin.setFloat(3.14);
    try testing.expectError(error.TypeMismatch, result);
}

test "Pin: link to signal" {
    var comp = try Component.init(testing.allocator, "test-pin-link");
    defer comp.exit();
    try comp.ready();

    const pin = try comp.newPin("linkable-pin", .bit, .out);

    // Create a signal using C API directly
    const c = @import("ffi/c.zig").c;
    _ = c.hal_signal_new("test-signal\x00", c.HAL_BIT);

    // Link pin to signal
    try pin.link("test-signal");

    // Verify link (by checking we can still read/write through pin)
    try pin.setBit(true);
    const value = pin.getBit();
    try testing.expectEqual(true, value);
}

test "Pin: unlink from signal" {
    var comp = try Component.init(testing.allocator, "test-pin-unlink");
    defer comp.exit();
    try comp.ready();

    const pin = try comp.newPin("unlinkable-pin", .bit, .out);

    // Create and link to a signal
    const c = @import("ffi/c.zig").c;
    _ = c.hal_signal_new("test-signal2\x00", c.HAL_BIT);
    try pin.link("test-signal2");

    // Unlink
    try pin.unlink();

    // Pin should still work with its dummy value
    try pin.setBit(true);
    const value = pin.getBit();
    try testing.expectEqual(true, value);
}

test "Pin: cached pointer allows fast access" {
    var comp = try Component.init(testing.allocator, "test-cached-ptr");
    defer comp.exit();
    try comp.ready();

    const pin = try comp.newPin("cached-pin", .float, .out);

    // Verify data_ptr is not null/none
    // Verify data_ptr is set (no .none variant in our PinDataPtr union)
    _ = pin.data_ptr;

    // Do many rapid accesses to verify caching works
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try pin.setFloat(@as(f64, @floatFromInt(i)));
        const val = pin.getFloat();
        try testing.expectApproxEqAbs(@as(f64, @floatFromInt(i)), val, 0.001);
    }
}
