// Component type tests
//
// Test-driven development for HAL Component type with cached pin pointers

const std = @import("std");
const testing = std.testing;

const Component = @import("ffi/component.zig").Component;
const Pin = @import("ffi/pin.zig").Pin;
const PinType = @import("ffi/pin.zig").PinType;
const PinDir = @import("ffi/pin.zig").PinDir;

test "Component: init, ready, and exit lifecycle" {
    // Create a component
    var comp = try Component.init(testing.allocator, "test-component");
    defer comp.exit();

    // Component should not be ready yet
    try testing.expectEqual(false, comp.is_ready);

    // Mark component as ready
    try comp.ready();
    try testing.expectEqual(true, comp.is_ready);

    // Create a pin to verify component is working
    const pin = try comp.newPin("test-bit", .bit, .out);
    try testing.expectNotNull(pin);

    // Exit cleans up
    comp.exit();
    try testing.expectEqual(false, comp.is_ready);
}

test "Component: newPin creates bit pin with cached pointer" {
    var comp = try Component.init(testing.allocator, "test-bit-pin");
    defer comp.exit();

    try comp.ready();

    // Create a bit pin
    const pin = try comp.newPin("my-bit", .bit, .out);
    try testing.expectEqualStrings("my-bit", pin.name);
    try testing.expectEqual(PinType.bit, pin.pin_type);
    try testing.expectEqual(PinDir.out, pin.dir);

    // Verify data pointer is cached
    try testing.expect(pin.data_ptr != .none);
}

test "Component: newPin creates float pin with cached pointer" {
    var comp = try Component.init(testing.allocator, "test-float-pin");
    defer comp.exit();

    try comp.ready();

    // Create a float pin
    const pin = try comp.newPin("my-float", .float, .out);
    try testing.expectEqualStrings("my-float", pin.name);
    try testing.expectEqual(PinType.float, pin.pin_type);
    try testing.expectEqual(PinDir.out, pin.dir);

    // Verify data pointer is cached
    try testing.expect(pin.data_ptr != .none);
}

test "Component: newPin creates s32 pin with cached pointer" {
    var comp = try Component.init(testing.allocator, "test-s32-pin");
    defer comp.exit();

    try comp.ready();

    // Create an s32 pin
    const pin = try comp.newPin("my-s32", .s32, .out);
    try testing.expectEqualStrings("my-s32", pin.name);
    try testing.expectEqual(PinType.s32, pin.pin_type);

    // Verify data pointer is cached
    try testing.expect(pin.data_ptr != .none);
}

test "Component: newPin creates u32 pin with cached pointer" {
    var comp = try Component.init(testing.allocator, "test-u32-pin");
    defer comp.exit();

    try comp.ready();

    // Create a u32 pin
    const pin = try comp.newPin("my-u32", .u32, .out);
    try testing.expectEqualStrings("my-u32", pin.name);
    try testing.expectEqual(PinType.u32, pin.pin_type);

    // Verify data pointer is cached
    try testing.expect(pin.data_ptr != .none);
}

test "Component: newPin with HAL_IN direction" {
    var comp = try Component.init(testing.allocator, "test-in-pin");
    defer comp.exit();

    try comp.ready();

    const pin = try comp.newPin("input-pin", .bit, .in);
    try testing.expectEqual(PinDir.in, pin.dir);
}

test "Component: newPin with HAL_IO direction" {
    var comp = try Component.init(testing.allocator, "test-io-pin");
    defer comp.exit();

    try comp.ready();

    const pin = try comp.newPin("io-pin", .float, .io);
    try testing.expectEqual(PinDir.io, pin.dir);
}

test "Component: tracks created pins" {
    var comp = try Component.init(testing.allocator, "test-track-pins");
    defer comp.exit();

    try comp.ready();

    // Create multiple pins
    _ = try comp.newPin("pin1", .bit, .out);
    _ = try comp.newPin("pin2", .float, .out);
    _ = try comp.newPin("pin3", .s32, .in);

    // Verify count
    try testing.expectEqual(@as(usize, 3), comp.pins.items.len);
}
