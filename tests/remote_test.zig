// Test remote HAL client
const std = @import("std");
const testing = std.testing;

const backend = @import("backend");
const RemoteBackend = @import("src/remote_hal/client").RemoteBackend;

test "remote hal list pins" {
    const allocator = testing.allocator;

    std.log.info("Connecting to remote HAL at 192.168.2.118:8765", .{});

    const hal_backend = try RemoteBackend.create(allocator, "192.168.2.118", 8765);
    defer hal_backend.deinit();

    // Initialize component
    const comp_id = try hal_backend.initComponent("test_client");
    defer hal_backend.exitComponent(comp_id);

    // Ready component
    try hal_backend.readyComponent(comp_id);

    // List pins
    std.log.info("Listing pins...", .{});
    const pins = try hal_backend.listPins(allocator);
    defer {
        for (pins) |p| allocator.free(p.name);
        allocator.free(pins);
    }

    std.log.info("Got {} pins:", .{pins.len});
    try testing.expect(pins.len > 0);

    for (pins, 0..) |pin, i| {
        if (i < 5) {
            std.log.info("  [{d}] {s}: {} dir={} value={}", .{ i, pin.name, pin.type, pin.dir, pin.value });
        }
    }
}
